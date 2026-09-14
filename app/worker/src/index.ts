/**
 * 말길 · 단일 워커 — 정적 자산(Flutter Web) + /api/* 프록시 + cron
 *
 * 엔드포인트 ↔ 공사 오퍼레이션 (KorService2)
 *   GET /api/health                              — (상류 호출 없음)
 *   GET /api/ldong[?regn=NN]                     — ldongCode2        캐시 3600s
 *   GET /api/places?code=NNNNN[&type=..]         — areaBasedList2    캐시 300s (rows 는 서버 고정 1000 · 공개 파라미터 아님)
 *   GET /api/place/:id                           — detailCommon2     캐시 300s
 *   GET /api/place/:id/intro?type=NN             — detailIntro2      캐시 300s
 *   cron 0 0 * * *                               — ldongCode2 1콜 + areaBasedList2 1콜(89곳 순환)
 *
 * 클라이언트는 위 경로만 호출할 수 있다. 오퍼레이션·파라미터는 서버가 고정하고
 * 화이트리스트 밖의 값은 400 으로 거절한다. 인증키는 클라이언트에 절대 내려가지 않는다.
 */
import { Hono, type Context } from 'hono';
import { cors } from 'hono/cors';
import { ktoFetch, splitCode, type Env, type KtoOp, type KtoResult } from './kto';
import { REGIONS_89 } from './regions89';

// ── 정책 상수 ────────────────────────────────────────────────────────────────
/** 말길이 다루는 국문 contentTypeId (TSD §4-6). 38 쇼핑은 항상 제외 */
const CONTENT_TYPES = ['12', '14', '15', '39'] as const;
const TTL = { ldong: 3600, places: 300, place: 300 } as const;
/** 목록은 항상 상류 최대 1콜(공개 파라미터로 노출하지 않는다 — 값을 바꿔 캐시를 우회하며 한도를 태우는 구멍 방지) */
const ROWS_FIXED = 1000;
/** 한도 초과(429) · 없는 contentId(404) 응답의 부정 캐시(메모리만) — 이 동안은 상류를 두드리지 않는다 */
const NEG_TTL = 60;
const RE_CODE5 = /^\d{5}$/;
const RE_REGN = /^\d{2}$/;
const RE_ID = /^\d{1,12}$/;
const RE_DEV_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

type Bindings = { Bindings: Env };
const app = new Hono<Bindings>();

// ── CORS: 같은 오리진이 기본. 로컬 Flutter 개발(localhost/127.0.0.1 어떤 포트든)만 허용 ──
app.use(
  '/api/*',
  cors({
    origin: (origin) => (RE_DEV_ORIGIN.test(origin) ? origin : ''),
    allowMethods: ['GET', 'OPTIONS'],
    exposeHeaders: ['x-malgil-remaining', 'x-malgil-cache', 'x-malgil-cache-layer'],
    maxAge: 600,
  }),
);

// ── 레이트리밋: [[ratelimits]] API_RL 바인딩이 있으면 IP 별로 제한 (없으면 통과 — 로컬 dev) ──
app.use('/api/*', async (c, next) => {
  const rl = c.env.API_RL;
  if (rl) {
    const ip = c.req.header('cf-connecting-ip') ?? c.req.header('x-forwarded-for') ?? 'local';
    const { success } = await rl.limit({ key: ip });
    if (!success) {
      return c.json({ ok: false, kind: 'rate_limited', message: 'too many requests — try again in a minute' }, 429);
    }
  }
  await next();
});

// ── 응답 헬퍼 ────────────────────────────────────────────────────────────────
function bad(message: string): Response {
  return Response.json({ ok: false, kind: 'bad_request', message }, { status: 400 });
}

/** 쿼리 키 화이트리스트 — 허용 밖의 키가 하나라도 있으면 400. 같은 키 중복(?type=39&type=38)도 400 (첫 값만 검증되고 캐시 키만 달라지는 구멍 방지) */
function onlyKeys(url: URL, allowed: readonly string[]): string | null {
  const seen = new Set<string>();
  for (const k of url.searchParams.keys()) {
    if (!allowed.includes(k)) return `unknown parameter: ${k} (allowed: ${allowed.join(', ')})`;
    if (seen.has(k)) return `duplicate parameter: ${k}`;
    seen.add(k);
  }
  return null;
}

/** 캐시 키 = 정규화된 요청 URL (경로 + 키 정렬 쿼리). 오리진은 고정값으로 두어 dev/운영이 같은 규칙을 쓴다 */
function cacheKeyOf(url: URL): Request {
  const params = [...url.searchParams.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const q = new URLSearchParams(params).toString();
  return new Request(`https://malgil.cache${url.pathname}${q ? '?' + q : ''}`, { method: 'GET' });
}

/** 상류 결과 → 클라이언트 응답. quota / remaining 0 → 429 */
function toResponse(
  r: KtoResult,
  items: Record<string, unknown>[] | undefined,
  extra: Record<string, unknown> = {},
): Response {
  const remainingHeader = r.remaining == null ? 'unknown' : String(r.remaining);
  const headers = { 'x-malgil-remaining': remainingHeader, 'x-malgil-cache': 'miss' };

  if (!r.ok && r.kind === 'quota') {
    return Response.json(
      { ok: false, kind: 'quota', message: r.message ?? 'daily quota exceeded', remaining: r.remaining },
      { status: 429, headers },
    );
  }
  if (!r.ok) {
    return Response.json(
      { ok: false, kind: r.kind, code: r.code ?? null, message: r.message ?? null, remaining: r.remaining },
      { status: 502, headers },
    );
  }
  // remaining === 0 이어도 이 호출 자체는 성공한 「오늘의 마지막 1콜」이다 — 데이터를 버리지 않고 200 으로 내린다.
  // (다음 호출부터 상류가 XML LIMITED_NUMBER… 를 보내면 위 quota 분기가 429 를 낸다)
  return Response.json(
    {
      ok: true,
      fetchedAt: new Date().toISOString(),
      remaining: r.remaining,
      totalCount: r.totalCount,
      ...extra,
      items: items ?? r.list,
    },
    { status: 200, headers },
  );
}

/**
 * 3층 캐시 — ① 아이솔레이트 메모리(Map) → ② KV(바인딩이 있을 때) → ③ Cache API(caches.default).
 *
 * *.workers.dev 배포에서는 ③이 동작하지 않는다(커스텀 도메인 전용). 그래서 ②를 두고,
 * 같은 아이솔레이트 안의 반복 요청은 ①이 받는다. 200 만 저장하고, 429(한도)는 ①에만 NEG_TTL 동안
 * 부정 캐시해 한도 초과 뒤 요청마다 상류를 두드리지 않게 한다.
 * hit 응답의 x-malgil-remaining 은 저장 시점의 값이다.
 */
type CacheEntry = { exp: number; status: number; body: string; headers: Record<string, string> };
const MEM = new Map<string, CacheEntry>();
const MEM_MAX = 500;

function memSet(key: string, e: CacheEntry): void {
  if (MEM.size >= MEM_MAX) {
    const oldest = MEM.keys().next().value;
    if (oldest !== undefined) MEM.delete(oldest);
  }
  MEM.set(key, e);
}

function fromEntry(e: CacheEntry, layer: 'mem' | 'kv' | 'edge', op: KtoOp, key: string): Response {
  console.log(JSON.stringify({ op, params: key.replace('https://malgil.cache', ''), status: e.status, ms: 0, remaining: e.headers['x-malgil-remaining'] ?? null, cache: 'hit', layer }));
  return new Response(e.body, { status: e.status, headers: { ...e.headers, 'x-malgil-cache': 'hit', 'x-malgil-cache-layer': layer } });
}

async function cached(
  c: Context<Bindings>,
  ttl: number,
  op: KtoOp,
  produce: () => Promise<Response>,
): Promise<Response> {
  const keyReq = cacheKeyOf(new URL(c.req.url));
  const key = keyReq.url;
  const now = Date.now();

  // ① 메모리
  const m = MEM.get(key);
  if (m && m.exp > now) return fromEntry(m, 'mem', op, key);
  if (m) MEM.delete(key);

  // ② KV
  const kv = c.env.CACHE;
  if (kv) {
    const e = await kv.get<CacheEntry>(key, 'json');
    if (e && e.exp > now) {
      memSet(key, e);
      return fromEntry(e, 'kv', op, key);
    }
  }

  // ③ Cache API
  const hit = await caches.default.match(keyReq);
  if (hit) {
    const e: CacheEntry = {
      exp: now + ttl * 1000,
      status: hit.status,
      body: await hit.text(),
      headers: { 'content-type': hit.headers.get('content-type') ?? 'application/json', 'x-malgil-remaining': hit.headers.get('x-malgil-remaining') ?? 'unknown' },
    };
    memSet(key, e);
    return fromEntry(e, 'edge', op, key);
  }

  // miss → 상류 호출
  const res = await produce();
  const body = await res.clone().text();
  const headers = {
    'content-type': res.headers.get('content-type') ?? 'application/json',
    'x-malgil-remaining': res.headers.get('x-malgil-remaining') ?? 'unknown',
  };
  if (res.status === 200) {
    const e: CacheEntry = { exp: now + ttl * 1000, status: 200, body, headers };
    memSet(key, e);
    if (kv) c.executionCtx.waitUntil(kv.put(key, JSON.stringify(e), { expirationTtl: Math.max(60, ttl) }));
    const toStore = new Response(body, { status: 200, headers: { ...headers, 'Cache-Control': `public, s-maxage=${ttl}, max-age=0`, 'x-malgil-cache': 'miss' } });
    c.executionCtx.waitUntil(caches.default.put(keyReq, toStore));
  } else if (res.status === 429 || res.status === 404) {
    // 404(not_found) 도 부정 캐시 — 같은 죽은 contentId 를 다시 열 때마다 detailCommon2 1콜을 태우지 않는다 (2026-09-14 검증 중 /place/1 재방문 3콜 실측)
    memSet(key, { exp: now + NEG_TTL * 1000, status: res.status, body, headers });
  }
  return res;
}

// ── /api/health ──────────────────────────────────────────────────────────────
app.get('/api/health', (c) =>
  c.json({
    ok: true,
    service: 'malgil',
    now: new Date().toISOString(),
    // 배포 후 `wrangler secret put KTO_KEY` 누락을 바로 알 수 있게 (키 값은 절대 내리지 않는다)
    keyConfigured: typeof c.env.KTO_KEY === 'string' && c.env.KTO_KEY.length > 0,
    // 배포 후 캐시·레이트리밋 바인딩이 실제로 붙었는지 확인용 (workers.dev 에서는 kv 가 false 면 캐시가 사실상 없다)
    cache: { mem: MEM.size, kv: !!c.env.CACHE },
    rateLimit: !!c.env.API_RL,
    ops: ['ldongCode2', 'areaBasedList2', 'detailCommon2', 'detailIntro2'],
  }),
);

// ── /api/ldong[?regn=NN]  → ldongCode2 ───────────────────────────────────────
app.get('/api/ldong', async (c) => {
  const url = new URL(c.req.url);
  const badKey = onlyKeys(url, ['regn']);
  if (badKey) return bad(badKey);
  const regn = url.searchParams.get('regn');
  if (regn != null && !RE_REGN.test(regn)) return bad('regn must be 2 digits');

  return cached(c, TTL.ldong, 'ldongCode2', async () => {
    const params: Record<string, string> = { numOfRows: '1000', pageNo: '1' };
    if (regn) params.lDongRegnCd = regn;
    const r = await ktoFetch(c.env, 'ldongCode2', params);
    return toResponse(r, undefined, regn ? { regn } : {});
  });
});

// ── /api/places?code=NNNNN[&type=12|14|15|39]  → areaBasedList2 (numOfRows 는 서버 고정 1000) ──
app.get('/api/places', async (c) => {
  const url = new URL(c.req.url);
  const badKey = onlyKeys(url, ['code', 'type']);
  if (badKey) return bad(badKey);

  const code = url.searchParams.get('code') ?? '';
  if (!RE_CODE5.test(code)) return bad('code must be 5 digits (행정표준코드)');

  const type = url.searchParams.get('type');
  if (type != null && !(CONTENT_TYPES as readonly string[]).includes(type)) {
    return bad(`type must be one of ${CONTENT_TYPES.join('|')}`);
  }

  return cached(c, TTL.places, 'areaBasedList2', async () => {
    const params: Record<string, string> = {
      ...splitCode(code),
      numOfRows: String(ROWS_FIXED),
      pageNo: '1',
      arrange: 'C', // 수정일순
    };
    if (type) params.contentTypeId = type;
    const r = await ktoFetch(c.env, 'areaBasedList2', params);
    if (!r.ok) return toResponse(r, undefined);

    if (type) return toResponse(r, r.list, { code, type });

    // type 미지정: 1콜(contentTypeId 없음) 후 서버에서 12·14·15·39 만 남긴다 (38 쇼핑 · 25 · 28 · 32 제외)
    const items = r.list.filter((it) => (CONTENT_TYPES as readonly string[]).includes(String(it.contenttypeid ?? '')));
    return toResponse(r, items, {
      code,
      type: null,
      count: items.length,
      note: 'totalCount = 상류 전체 유형 건수. items 는 12·14·15·39 만 남긴 결과(쇼핑 38 등 제외)',
    });
  });
});

// ── /api/place/:id  → detailCommon2 (contentId 단독 — YN 계열·contentTypeId 파라미터는 상류가 거부) ──
app.get('/api/place/:id', async (c) => {
  const url = new URL(c.req.url);
  const badKey = onlyKeys(url, []);
  if (badKey) return bad(badKey);
  const id = c.req.param('id');
  if (!RE_ID.test(id)) return bad('id must be 1..12 digits (contentId)');

  return cached(c, TTL.place, 'detailCommon2', async () => {
    const r = await ktoFetch(c.env, 'detailCommon2', { contentId: id });
    // 존재하지 않는 contentId — 상류는 resultCode 0000 + totalCount 0 + items "" 로 온다 (2026-09-14 /api/place/1 실측) → 404
    if (r.ok && r.list.length === 0) {
      return Response.json(
        { ok: false, kind: 'not_found', message: `no place with contentId ${id}`, remaining: r.remaining },
        { status: 404, headers: { 'x-malgil-remaining': String(r.remaining ?? 'unknown'), 'x-malgil-cache': 'miss' } },
      );
    }
    return toResponse(r, undefined, { id });
  });
});

// ── /api/place/:id/intro?type=NN  → detailIntro2 (contentTypeId 필수) ────────
app.get('/api/place/:id/intro', async (c) => {
  const url = new URL(c.req.url);
  const badKey = onlyKeys(url, ['type']);
  if (badKey) return bad(badKey);
  const id = c.req.param('id');
  if (!RE_ID.test(id)) return bad('id must be 1..12 digits (contentId)');
  const type = url.searchParams.get('type') ?? '';
  if (!(CONTENT_TYPES as readonly string[]).includes(type)) {
    return bad(`type is required and must be one of ${CONTENT_TYPES.join('|')}`);
  }

  return cached(c, TTL.place, 'detailIntro2', async () => {
    const r = await ktoFetch(c.env, 'detailIntro2', { contentId: id, contentTypeId: type });
    return toResponse(r, undefined, { id, type });
  });
});

// ── 그 외 /api/* 는 404 (임의 오퍼레이션 호출 경로 없음) ───────────────────
app.all('/api/*', (c) => c.json({ ok: false, kind: 'not_found', message: 'no such endpoint' }, 404));

// ── 정적 자산 (Flutter Web) — SPA 폴백은 wrangler.toml not_found_handling 이 처리 ──
app.all('*', (c) => c.env.ASSETS.fetch(c.req.raw));

// ── cron: 매일 00:00 UTC — ldongCode2 1콜 + 89곳 중 날짜 순환 1곳 areaBasedList2 1콜 ──
async function scheduled(event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
  const dayIndex = Math.floor(event.scheduledTime / 86_400_000);
  const code = REGIONS_89[dayIndex % REGIONS_89.length]!;
  const run = async () => {
    const a = await ktoFetch(env, 'ldongCode2', { numOfRows: '1000', pageNo: '1' });
    const b = await ktoFetch(env, 'areaBasedList2', { ...splitCode(code), numOfRows: '50', pageNo: '1', arrange: 'C' });
    console.log(
      JSON.stringify({
        cron: event.cron,
        at: new Date(event.scheduledTime).toISOString(),
        dayIndex,
        region: code,
        ldong: a.ok ? { ok: true, count: a.list.length } : { ok: false, kind: a.kind },
        places: b.ok ? { ok: true, totalCount: b.totalCount } : { ok: false, kind: b.kind },
        remaining: b.remaining ?? a.remaining,
      }),
    );
  };
  const p = run();
  ctx.waitUntil(p);
  await p;
}

export default {
  fetch: app.fetch,
  scheduled,
} satisfies ExportedHandler<Env>;
