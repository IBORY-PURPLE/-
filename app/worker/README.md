# 말길 워커 (Cloudflare Workers)

Flutter Web이 **공사 인증키를 노출하지 않고** TourAPI 4.0 을 실시간 호출하게 하는 단일 워커.
정적 자산(`/*`) + API 프록시(`/api/*`) + cron(매일 1회 호출 이력)을 한 워커에 담는다.

```
Flutter Web ──► /api/*   ──► KorService2 (apis.data.go.kr/B551011)   키는 Workers Secret에만
            └─► /*       ──► [assets]  (지금은 public/, 나중에 ../flutter/build/web)
cron 0 0 * * * (UTC 00:00 = KST 09:00) ──► ldongCode2 1콜 + 89곳 순환 1곳 areaBasedList2 1콜
```

참조: `Docs/TSD.md` §4(실측 스펙) · §8(호출 전략).

## 실행

```bash
# 이 디렉터리(C:\Users\chewo\StudioProjects\malgil\worker)에서
npm run typecheck        # tsc --noEmit
npm run dev              # wrangler dev --port 8787  (로그인 불필요, .dev.vars 의 KTO_KEY 사용)
npm run deploy           # wrangler deploy  (Cloudflare 로그인 + `wrangler secret put KTO_KEY` 선행)
npm run tail             # 운영 로그 스트리밍
```

- 로컬 비밀: `.dev.vars` 에 `KTO_KEY=<인증키>` 한 줄. **.gitignore 대상 — 커밋 금지.**
- 운영 비밀: `npx wrangler secret put KTO_KEY` (배포 전 1회).
- 로컬 cron 수동 실행: `curl http://127.0.0.1:8787/cdn-cgi/local/scheduled`

## 엔드포인트

모든 응답은 JSON. 성공 `{ok:true, fetchedAt, remaining, totalCount, items[]}` · 실패 `{ok:false, kind, message}`.
응답 헤더 `x-malgil-remaining`(상류 X-RateLimit-Remaining · hit 이면 저장 시점 값) · `x-malgil-cache`(hit/miss) · `x-malgil-cache-layer`(mem/kv/edge).

| 경로 | 파라미터 (화이트리스트 — 그 외 400) | 캐시 | 비고 |
|---|---|---|---|
| `GET /api/health` | — | — | 상류 호출 없음. `keyConfigured`(Secret) · `cache.kv`(KV 바인딩) · `rateLimit` 확인 |
| `GET /api/ldong` | `regn` 2자리 (선택) | 3600s | 없으면 시도 16건, 있으면 해당 시도의 시군구 |
| `GET /api/places` | `code` 5자리 필수 · `type` 12\|14\|15\|39 (선택) | 300s | `numOfRows` 는 서버 고정 1000(공개 파라미터 아님). `type` 없으면 1콜 후 서버에서 12·14·15·39만 남김(38 쇼핑 등 제외). 이때 `totalCount`는 상류 전체 유형 건수, `count`는 남긴 건수 |
| `GET /api/place/:id` | `:id` 숫자 1..12자리 | 300s | contentId 단독 (YN 계열 파라미터는 상류가 거부) |
| `GET /api/place/:id/intro` | `type` 12\|14\|15\|39 필수 | 300s | 음식점(39)이면 `firstmenu` `treatmenu` `opentimefood` `infocenterfood` … |

- **캐시 3층** — 아이솔레이트 메모리(Map, 최대 500건) → KV(`CACHE` 바인딩이 있을 때) → Cache API. **`*.workers.dev` 에서는 Cache API 가 동작하지 않으므로 배포 후 KV 를 반드시 붙인다**(`wrangler.toml` 주석 참조). 200 만 저장. 429(한도)는 메모리에 60s 부정 캐시.
- **레이트리밋** — `[[ratelimits]] API_RL`(IP 별 분당 120). 초과 시 429 `{kind:'rate_limited'}`. 바인딩이 없으면(로컬) 통과.
- **429** `{ok:false, kind:'quota'}` — 상류가 한도 초과(XML `LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR`)를 보낼 때. (잔여 0 이어도 그 호출이 성공했으면 200 — 마지막 1콜의 데이터를 버리지 않는다)
- **502** `{ok:false, kind:'upstream'|'param_error'|'api_error'}` — 상류 오류 3형태(TSD §4-4).
- **400** `{ok:false, kind:'bad_request'}` — 파라미터 형식·화이트리스트 위반·같은 키 중복. 404 — 정의되지 않은 `/api/*`, 그리고 `/api/place/:id` 의 존재하지 않는 contentId(`kind:'not_found'`).
- CORS: 같은 오리진 기본. `Origin`이 `http://localhost:*` · `http://127.0.0.1:*` 이면 허용(로컬 Flutter 개발용).

### 지역 코드 규칙

`code`(행정표준코드 5자리) → `lDongRegnCd` 앞 2자리 + `lDongSignguCd` 뒤 3자리.
**세종 36110 특례** — 2026-09-14 실호출: `36/110` → 0건, `36110/36110` → 204건. 워커가 자동 처리한다.

## 공사 오퍼레이션 대조표 (기능설명서 4장 원본)

실제 코드가 호출하는 오퍼레이션만 적는다. 서비스: `KorService2`. 공통 파라미터 `MobileOS=ETC` `MobileApp=malgil` `_type=json`.

| 말길 엔드포인트 | 공사 오퍼레이션 | 넘기는 파라미터 | 호출 시점 |
|---|---|---|---|
| `/api/ldong` | `ldongCode2` | `numOfRows=1000` `pageNo=1` [`lDongRegnCd`] | 시군구 드롭다운(F3) · cron |
| `/api/places` | `areaBasedList2` | `lDongRegnCd` `lDongSignguCd` `numOfRows` `pageNo=1` `arrange=C` [`contentTypeId`] | 목록(F4) · cron |
| `/api/place/:id` | `detailCommon2` | `contentId` | 상세(F5) · 진단 지문(F1) |
| `/api/place/:id/intro` | `detailIntro2` | `contentId` `contentTypeId` | 상세(F5) 음식점 실무 필드 |

## 로그

상류 호출 1회마다 콘솔에 한 줄 JSON: `{op, params, status, ms, remaining, cache, ok, totalCount|kind}`.
캐시 hit 도 `cache:'hit'` 한 줄. cron 은 `{cron, at, dayIndex, region, ldong, places, remaining}`.
`npm run tail` 또는 Cloudflare 대시보드(observability 켜짐)에서 본다.

## 실측 (2026-09-14, wrangler dev)

| 요청 | HTTP | totalCount | items | remaining |
|---|---|---|---|---|
| `/api/ldong` | 200 | 16 | 16 | 943 |
| `/api/ldong?regn=30` | 200 | 5 | 5 | 942 |
| `/api/places?code=30140&type=39` | 200 | 39 | 39 | 920 |
| `/api/places?code=12730` | 200 | 142 | 106 (필터 후) | 919 |
| `/api/places?code=36110` | 200 | 204 | 169 (필터 후) | 918 |
| `/api/places?code=28125` | 200 | 189 | 162 (필터 후) | 917 |
| `/api/place/1807489` | 200 | 1 | 1 (광천식당) | 996 |
| `/api/place/1807489/intro?type=39` | 200 | 1 | 1 (firstmenu 두부두루치기) | 997 |

잔여 수치가 오퍼레이션마다 다르다 = **한도 1,000/일은 오퍼레이션별**로 센다.

## 배포 순서

1. `npx wrangler login` (브라우저 1회).
2. `npx wrangler secret put KTO_KEY` (.env 의 `Api_Key_Decoding` 값).
3. `npx wrangler kv namespace create MALGIL_CACHE` → 출력된 id 를 `wrangler.toml` `[[kv_namespaces]]` 에 넣고 주석 해제.
4. (Flutter 빌드가 있으면) `wrangler.toml` `[assets] directory` 를 `../flutter/build/web` 으로 교체.
5. `npm run deploy` → `*.workers.dev` URL 을 기획서·기능설명서에 기록.
6. 확인: `curl <URL>/api/health` 에서 `keyConfigured:true` · `cache.kv:true` · `rateLimit:true`, 같은 `/api/places?code=12730` 을 2회 호출해 두 번째가 `x-malgil-cache: hit` 인지, `npm run tail` 로 상류 로그가 찍히는지.
