/**
 * /api/* 라우트 테스트 — 상류 호출 0 (globalThis.fetch 를 목으로 바꿔 상류 URL 만 캡처한다).
 *
 * 고정하는 것: 화이트리스트 400 · rows 거부 · type=38 거부 · 세종/전남광주 상류 파라미터 · 38 서버 필터 ·
 * 429 부정 캐시(같은 URL 재요청은 상류를 두드리지 않음) · 404 not_found(없는 contentId · 미정의 경로) · health.
 * 메모리 캐시(MEM)가 모듈 전역이므로 테스트마다 다른 code/URL 을 쓴다.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';
import type { Env } from '../src/kto';

const XML_LIMIT =
  '<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg><returnAuthMsg>LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR</returnAuthMsg><returnReasonCode>22</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>';

const env = {
  KTO_KEY: 'k',
  KTO_BASE: 'https://upstream.test',
  ASSETS: { fetch: async () => new Response('asset', { status: 200 }) },
} as unknown as Env;
const ctx = { waitUntil() {}, passThroughOnException() {}, props: {} } as unknown as ExecutionContext;

const fetchMock = vi.fn<(input: string | URL | Request, init?: RequestInit) => Promise<Response>>();

/** 상류 정상 응답 (KorService2 JSON) */
function upstreamOk(items: Record<string, unknown>[] | '', totalCount?: number): Response {
  const body = {
    response: {
      header: { resultCode: '0000', resultMsg: 'OK' },
      body: { items: items === '' ? '' : { item: items }, numOfRows: 1000, pageNo: 1, totalCount: totalCount ?? (items === '' ? 0 : items.length) },
    },
  };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json', 'X-RateLimit-Remaining': '900', 'X-RateLimit-Limit': '1000' },
  });
}

const call = (path: string) => worker.fetch(new Request(`http://localhost${path}`), env, ctx);
const upstreamUrl = (i = 0) => String(fetchMock.mock.calls[i]![0]);

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal('fetch', fetchMock);
  vi.stubGlobal('caches', { default: { match: async () => undefined, put: async () => {} } });
  vi.spyOn(console, 'log').mockImplementation(() => {});
});

describe('/api/health', () => {
  it('상류 호출 없음 · keyConfigured · 오퍼레이션 4개', async () => {
    const res = await call('/api/health');
    expect(res.status).toBe(200);
    const j = (await res.json()) as Record<string, unknown>;
    expect(j.ok).toBe(true);
    expect(j.keyConfigured).toBe(true);
    expect(j.ops).toEqual(['ldongCode2', 'areaBasedList2', 'detailCommon2', 'detailIntro2']);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('/api/places — 파라미터 검증 (상류 호출 전 400)', () => {
  it('(1) rows 는 공개 파라미터가 아니다 → 400 bad_request · fetch 미호출', async () => {
    const res = await call('/api/places?code=27200&rows=5');
    expect(res.status).toBe(400);
    expect(((await res.json()) as { kind: string }).kind).toBe('bad_request');
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it('(2) 같은 키 중복 ?type=39&type=38 → 400', async () => {
    expect((await call('/api/places?code=27200&type=39&type=38')).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it('(3) type=38(쇼핑) → 400 · code 4자리 → 400', async () => {
    expect((await call('/api/places?code=27200&type=38')).status).toBe(400);
    expect((await call('/api/places?code=2720')).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('/api/places — 상류 파라미터 (회귀 #3)', () => {
  it('(4) 세종 36110 → lDongRegnCd=36110&lDongSignguCd=36110 · numOfRows 1000 고정 · pageNo 1 · arrange C', async () => {
    fetchMock.mockResolvedValue(upstreamOk([{ contentid: '1', contenttypeid: '12' }]));
    const res = await call('/api/places?code=36110');
    expect(res.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const u = upstreamUrl();
    expect(u.startsWith('https://upstream.test/KorService2/areaBasedList2?serviceKey=k&')).toBe(true);
    expect(u).toContain('MobileOS=ETC&MobileApp=malgil&_type=json');
    expect(u).toContain('lDongRegnCd=36110&lDongSignguCd=36110');
    expect(u).toContain('numOfRows=1000&pageNo=1&arrange=C');
    expect(u).not.toContain('contentTypeId');
  });
  it('(5) 전남광주 12730 → lDongRegnCd=12&lDongSignguCd=730', async () => {
    fetchMock.mockResolvedValue(upstreamOk([]));
    await call('/api/places?code=12730');
    expect(upstreamUrl()).toContain('lDongRegnCd=12&lDongSignguCd=730');
  });
  it('(6) 인천 신설 28155 → lDongRegnCd=28&lDongSignguCd=155', async () => {
    fetchMock.mockResolvedValue(upstreamOk([]));
    await call('/api/places?code=28155');
    expect(upstreamUrl()).toContain('lDongRegnCd=28&lDongSignguCd=155');
  });
  it('type=39 지정 → contentTypeId=39 가 붙고 서버 필터 없음', async () => {
    fetchMock.mockResolvedValue(upstreamOk([{ contentid: '5', contenttypeid: '39' }]));
    const res = await call('/api/places?code=30140&type=39');
    expect(upstreamUrl()).toContain('contentTypeId=39');
    const j = (await res.json()) as { items: unknown[]; type: string };
    expect(j.items.length).toBe(1);
    expect(j.type).toBe('39');
  });
});

describe('/api/places — 응답 형태', () => {
  it('(7) type 미지정: 12·14·15·39 만 남기고 38·25 제외 · count 2 · totalCount 는 상류 전체 4 · note', async () => {
    fetchMock.mockResolvedValue(
      upstreamOk([
        { contentid: '1', contenttypeid: '12' },
        { contentid: '2', contenttypeid: '38' },
        { contentid: '3', contenttypeid: '39' },
        { contentid: '4', contenttypeid: '25' },
      ]),
    );
    const res = await call('/api/places?code=27200');
    expect(res.status).toBe(200);
    expect(res.headers.get('x-malgil-remaining')).toBe('900');
    expect(res.headers.get('x-malgil-cache')).toBe('miss');
    const j = (await res.json()) as Record<string, unknown> & { items: { contenttypeid: string }[] };
    expect(j.ok).toBe(true);
    expect(j.items.map((i) => i.contenttypeid)).toEqual(['12', '39']);
    expect(j.count).toBe(2);
    expect(j.totalCount).toBe(4);
    expect(j.code).toBe('27200');
    expect(j.type).toBeNull();
    expect(typeof j.note).toBe('string');
    expect(typeof j.fetchedAt).toBe('string');
  });

  it('(8) 상류 LIMITED_NUMBER XML → 429 quota · 같은 URL 재요청은 60s 부정 캐시(hit) — 상류 0콜', async () => {
    fetchMock.mockResolvedValue(new Response(XML_LIMIT, { status: 200, headers: { 'content-type': 'application/xml' } }));
    const first = await call('/api/places?code=41110');
    expect(first.status).toBe(429);
    expect(((await first.json()) as { kind: string }).kind).toBe('quota');
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const second = await call('/api/places?code=41110');
    expect(second.status).toBe(429);
    expect(second.headers.get('x-malgil-cache')).toBe('hit');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('(9) 상류 200 + 평면 JSON resultCode 11 → 502 param_error (TSD §4-4 (b))', async () => {
    fetchMock.mockResolvedValue(new Response('{"resultCode":"11","resultMsg":"NO_MANDATORY_REQUEST_PARAMETERS_ERROR1(MobileOS)"}', { status: 200 }));
    const res = await call('/api/places?code=43740');
    expect(res.status).toBe(502);
    const j = (await res.json()) as { kind: string; code: string };
    expect(j.kind).toBe('param_error');
    expect(j.code).toBe('11');
  });

  it('성공 응답은 300s 메모리 캐시 — 같은 URL 2회째 hit · 상류 1콜', async () => {
    fetchMock.mockResolvedValue(upstreamOk([{ contentid: '1', contenttypeid: '14' }]));
    const a = await call('/api/places?code=47170');
    expect(a.headers.get('x-malgil-cache')).toBe('miss');
    const b = await call('/api/places?code=47170');
    expect(b.headers.get('x-malgil-cache')).toBe('hit');
    expect(b.headers.get('x-malgil-cache-layer')).toBe('mem');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe('/api/place/:id · /intro · 그 외', () => {
  it('(10) 없는 contentId — 상류 0000 + items "" → 404 not_found · 재요청은 부정 캐시', async () => {
    fetchMock.mockResolvedValue(upstreamOk(''));
    const res = await call('/api/place/1');
    expect(res.status).toBe(404);
    expect(((await res.json()) as { kind: string }).kind).toBe('not_found');
    expect(upstreamUrl()).toContain('/KorService2/detailCommon2?');
    expect(upstreamUrl()).toContain('contentId=1');
    await call('/api/place/1');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it('id 형식 오류 · 쿼리 금지 · intro 는 type 필수(38 금지) → 400', async () => {
    expect((await call('/api/place/abc')).status).toBe(400);
    expect((await call('/api/place/7?type=39')).status).toBe(400);
    expect((await call('/api/place/7/intro')).status).toBe(400);
    expect((await call('/api/place/7/intro?type=38')).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it('intro?type=39 → detailIntro2 · contentTypeId=39', async () => {
    fetchMock.mockResolvedValue(upstreamOk([{ contentid: '2842743', firstmenu: '노이스테이크' }]));
    const res = await call('/api/place/2842743/intro?type=39');
    expect(res.status).toBe(200);
    expect(upstreamUrl()).toContain('/KorService2/detailIntro2?');
    expect(upstreamUrl()).toContain('contentId=2842743&contentTypeId=39');
  });
  it('/api/ldong?regn=1 → 400 · ?regn=36 → lDongRegnCd=36', async () => {
    expect((await call('/api/ldong?regn=1')).status).toBe(400);
    fetchMock.mockResolvedValue(upstreamOk([{ code: '36110', name: '세종특별자치시' }]));
    const res = await call('/api/ldong?regn=36');
    expect(res.status).toBe(200);
    expect(upstreamUrl()).toContain('/KorService2/ldongCode2?');
    expect(upstreamUrl()).toContain('lDongRegnCd=36');
  });
  it('(11) /api/nope → 404 not_found · 상류 0콜', async () => {
    const res = await call('/api/nope');
    expect(res.status).toBe(404);
    expect(((await res.json()) as { kind: string }).kind).toBe('not_found');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
