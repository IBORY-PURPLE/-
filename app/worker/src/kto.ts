/**
 * 말길 · 공사 관광정보 API (KorService2) 공통 호출 + 응답 파서
 *
 * 참조: Docs/TSD.md §4-3 공통 파라미터 · §4-4 에러 응답 3형태 · §4-5 지역 코드
 *
 * parseKto 분기 (TSD §4-4 참조 구현을 옮기고, 한도 초과(XML) 분기를 더함)
 *   (a) HTTP 비정상 또는 본문이 XML(OpenAPI_ServiceResponse / errMsg / returnAuthMsg)
 *         → ok:false, kind:'quota'   (LIMITED_NUMBER… 문구 = 일일 한도 초과, returnReasonCode 22)
 *         → ok:false, kind:'upstream' (그 외: 키 미등록 403 · 키 누락 401 · 폐기 서비스 400 …)
 *   (b) HTTP 200인데 `response` 래퍼 없는 평면 JSON → ok:false, kind:'param_error'
 *   (c) resultCode ≠ '0000'                          → ok:false, kind:'api_error'
 *   (d) items 가 "" (빈 문자열)                       → ok:true, list:[]
 */

/** Cloudflare Rate Limiting 바인딩 ([[ratelimits]]) — 최소 인터페이스 */
export interface RateLimiter {
  limit(opts: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  KTO_KEY: string;   // Workers Secret (.dev.vars 로컬)
  KTO_BASE: string;  // https://apis.data.go.kr/B551011
  ASSETS: Fetcher;
  /** 선택 — KV 캐시. *.workers.dev 에서는 Cache API 가 동작하지 않으므로 KV 가 실질 캐시가 된다 */
  CACHE?: KVNamespace;
  /** 선택 — IP 별 레이트리밋 (남용으로 공사 한도 1,000/일이 고갈되는 것을 막는다) */
  API_RL?: RateLimiter;
}

export type KtoKind = 'quota' | 'upstream' | 'param_error' | 'api_error';

export interface RateInfo {
  /** 상류 응답 헤더 X-RateLimit-Remaining (없으면 null) */
  remaining: number | null;
  /** 상류 응답 헤더 X-RateLimit-Limit (없으면 null) */
  limit: number | null;
}

export interface KtoOk extends RateInfo {
  ok: true;
  list: Record<string, unknown>[];
  totalCount: number;
  status: number;
  ms: number;
}

export interface KtoErr extends RateInfo {
  ok: false;
  kind: KtoKind;
  code?: string;
  message?: string;
  status: number;
  ms: number;
}

export type KtoResult = KtoOk | KtoErr;

/** parseKto 의 반환 — 네트워크 계층이 붙이는 ms 만 빠진 형태 */
export type Parsed = Omit<KtoOk, 'ms'> | Omit<KtoErr, 'ms'>;

/** 말길이 실제로 호출하는 오퍼레이션 — 이 외는 호출 경로 자체가 없다 (기능설명서 4장 대조표) */
export type KtoOp = 'ldongCode2' | 'areaBasedList2' | 'detailCommon2' | 'detailIntro2';

const XML_MARKERS = ['OpenAPI_ServiceResponse', 'errMsg', 'returnAuthMsg'];

function tag(xml: string, name: string): string | undefined {
  const m = xml.match(new RegExp(`<${name}>([^<]*)</${name}>`));
  return m?.[1]?.trim();
}

/**
 * 응답 본문 파서. 네트워크 계층과 분리해 두어 단위 테스트가 가능하다.
 * @param status HTTP 상태
 * @param text   본문 원문 (JSON이든 XML이든)
 */
export function parseKto(status: number, text: string): Parsed {
  const base: RateInfo & { status: number } = { remaining: null, limit: null, status };
  const trimmed = text.trimStart();
  // '{' 로 시작하는 정상 JSON 본문은 마커 검사에서 제외 — 관광지 overview 본문에 'errMsg' 같은 글자가 섞여도 오판하지 않게
  const isXml = trimmed.startsWith('<') || (!trimmed.startsWith('{') && XML_MARKERS.some((m) => trimmed.includes(m)));

  // (a) HTTP 비정상 또는 XML 본문
  if (status !== 200 || isXml) {
    const authMsg = isXml ? tag(trimmed, 'returnAuthMsg') ?? tag(trimmed, 'errMsg') : undefined;
    const reason = isXml ? tag(trimmed, 'returnReasonCode') : undefined;
    const message = authMsg ?? `HTTP ${status}`;
    const kind: KtoKind = /LIMITED_NUMBER/i.test(text) || reason === '22' ? 'quota' : 'upstream';
    return { ...base, ok: false, kind, code: reason ?? String(status), message };
  }

  let j: any;
  try {
    j = JSON.parse(text);
  } catch {
    return { ...base, ok: false, kind: 'upstream', code: String(status), message: 'non-JSON body' };
  }

  // (b) ★ HTTP 200이어도 response 래퍼가 없으면 에러다 (resultCode 10/11 평면 JSON)
  if (j?.response == null) {
    return { ...base, ok: false, kind: 'param_error', code: j?.resultCode, message: j?.resultMsg };
  }

  // (c) resultCode ≠ 0000
  const code = j.response?.header?.resultCode;
  if (code !== '0000') {
    return { ...base, ok: false, kind: 'api_error', code, message: j.response?.header?.resultMsg };
  }

  // (d) items 가 빈 문자열("")로 오는 케이스 방어
  const body = j.response.body;
  const item = body?.items?.item;
  const list: Record<string, unknown>[] = Array.isArray(item) ? item : item ? [item] : [];
  return { ...base, ok: true, list, totalCount: Number(body?.totalCount ?? 0) };
}

function readInt(h: Headers, name: string): number | null {
  const v = h.get(name);
  if (v == null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * 공사 API 1회 호출. 공통 파라미터(serviceKey · MobileOS=ETC · MobileApp=malgil · _type=json)를 붙인다.
 * 호출마다 콘솔에 한 줄 JSON 로그 {op, params, status, ms, remaining, cache:'miss'} 를 남긴다.
 */
export async function ktoFetch(env: Env, op: KtoOp, params: Record<string, string>): Promise<KtoResult> {
  const qs = new URLSearchParams({ MobileOS: 'ETC', MobileApp: 'malgil', _type: 'json', ...params });
  // serviceKey 는 URLSearchParams 를 거치지 않고 직접 encodeURIComponent 로 붙인다 (이중 인코딩 방지)
  const url = `${env.KTO_BASE}/KorService2/${op}?serviceKey=${encodeURIComponent(env.KTO_KEY)}&${qs}`;

  const t0 = Date.now();
  let status = 0;
  let text = '';
  let headers = new Headers();
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': 'malgil-worker' } });
    status = res.status;
    headers = res.headers;
    text = await res.text();
  } catch (e) {
    const ms = Date.now() - t0;
    console.log(JSON.stringify({ op, params, status: 0, ms, remaining: null, cache: 'miss', error: String(e) }));
    return { ok: false, kind: 'upstream', code: 'fetch_failed', message: String(e), remaining: null, limit: null, status: 0, ms };
  }
  const ms = Date.now() - t0;
  const parsed = parseKto(status, text);
  const rate: RateInfo = {
    remaining: readInt(headers, 'X-RateLimit-Remaining'),
    limit: readInt(headers, 'X-RateLimit-Limit'),
  };
  const result = { ...parsed, ...rate, ms } as KtoResult;
  console.log(
    JSON.stringify({
      op,
      params,
      status,
      ms,
      remaining: rate.remaining,
      cache: 'miss',
      ok: result.ok,
      ...(result.ok ? { totalCount: result.totalCount } : { kind: result.kind, code: result.code }),
    }),
  );
  return result;
}

/**
 * 행정표준코드 5자리 → lDongRegnCd(2) + lDongSignguCd(3)
 *
 * 세종특별자치시 36110 특례 — 2026-09-14 실호출로 확인:
 *   lDongRegnCd=36 & lDongSignguCd=110     → totalCount 0
 *   lDongRegnCd=36110 & lDongSignguCd=36110 → totalCount 204   ← 이쪽이 맞다
 */
export function splitCode(code: string): { lDongRegnCd: string; lDongSignguCd: string } {
  if (code === '36110') return { lDongRegnCd: '36110', lDongSignguCd: '36110' };
  return { lDongRegnCd: code.slice(0, 2), lDongSignguCd: code.slice(2) };
}
