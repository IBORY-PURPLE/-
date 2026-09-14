# 말길 (Malgil) — Flutter Web

급수(TOPIK) 선택 → 시군구 급수 지도 → 장소 목록·상세. UI 문자열은 영어, 콘텐츠(지명·장소명)는 한국어 원문.
공사 API 는 워커(`../worker`, `/api/*`)를 통해서만 부른다 — 앱 코드에 `apis.data.go.kr` 직접 호출 없음.

## 실행

```bash
# 이 디렉터리(C:\Users\chewo\StudioProjects\malgil\flutter)에서
flutter pub get
flutter analyze
flutter test

# 로컬 개발 — 워커를 먼저 띄운다: (../worker) npm run dev   → http://127.0.0.1:8787
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8787

# 배포 빌드 (워커 [assets] 가 build/web 을 서빙)
flutter build web --no-web-resources-cdn
```

`API_BASE` 를 비우면(기본) 같은 오리진 상대경로 `/api/…` 를 부른다 — 워커가 정적 자산과 API 를 한 오리진에서 내므로 배포에서는 지정하지 않는다.
`?demo=1` 로 열면 급수 3(Lv3)을 저장하고 `/map` 으로 간다(심사 프리셋).
URL 은 경로 전략(`usePathUrlStrategy`, `main.dart`) — `/map` `/?demo=1` 같은 딥링크가 그대로 라우터에 닿는다(해시 `#/` 아님). 워커 `[assets] not_found_handling = "single-page-application"` 이 index.html 을 돌려주므로 새로고침도 된다.

### 로컬 서빙 확인 (워커 경유)

```bash
# (../worker) wrangler.toml [assets] directory = "../flutter/build/web"
npx wrangler dev --port 8790
curl -s http://127.0.0.1:8790/ | grep -c malgil-shell     # 로딩 셸 포함 index.html
curl -s http://127.0.0.1:8790/api/health                 # {"ok":true,...}
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8790/map   # 200 (SPA 폴백)
```

헤드리스 Edge 스크린샷은 `--window-size` 폭을 430 으로 줘도 innerWidth 가 492 로 보고된다(2026-09-14 실측 · 도구 최소 폭). 폭 500 이상으로 찍어야 잘리지 않는다.

## 구조 (lib/)

| 경로 | 역할 |
|---|---|
| `main.dart` | runApp 전에 자산(`assets/data/build_app_assets.json`) 로드 + AppState 복원 |
| `app.dart` | `MaterialApp.router` + GoRouter (`/` · `/map` · `/region/:code` · `/place/:id`) · `AppScope` · `?demo=1` redirect |
| `theme/tokens.dart` | 색·반경·타입 스케일 — `Docs/mockup/m3.css` 와 1:1 (hex grep 대조) |
| `state/app_state.dart` | 급수 · 방문 기록. shared_preferences 키 `malgil.level` / `malgil.visits`, 실패 시 메모리 폴백 |
| `data/assets.dart` | 자산 파싱(`데이터` 키 하위호환) · Region/Meta/Summary · `stateOf`/`isOpen` (mockup.js 와 같은 규칙) |
| `data/api.dart` | `ApiClient` — ok / quota(429) / error 3분기. `x-malgil-remaining`·`x-malgil-cache` 보존. 타임아웃 20s |
| `i18n/strings_en.dart` | 사용자 노출 문자열 전부 (금지어 grep 대상 파일) |
| `widgets/kto_image.dart` | 앱 유일 이미지 위젯 — Type1 만 cover, 그 외 contain+검정, 「ⓒ한국관광공사」 자동 캡션 |
| `widgets/state_views.dart` | loading · empty · error · quota (`05_states.html` 문구) |
| `widgets/source_footer.dart` · `level_chip.dart` | 출처 푸터(산출일) · 급수 칩 |
| `screens/landing_screen.dart` | `01_landing.html` — 급수 카드 4장 · Show my map · Judge preview |
| `screens/placeholder_screen.dart` | `/map` `/region` `/place` 자리표시 (다음 브랜치) |
| `web/index.html` | 정적 로딩 셸 — 엔진 부팅 전 즉시 페인트, `flutter-first-frame` 에서 제거 |

앱의 「열린 곳수 · 89곳 곳수」는 자산 `요약` 값을 그대로 쓴다(재계산하지 않음). 테스트 `test/assets_test.dart` 가 지역 행 재계산과 요약의 일치를 급수 2~5 전부에서 검사한다.

## 규칙

- 사용자 노출 문자열 금지어: TourAPI · KTO · Korea Tourism · Lv0 · Lv6 · 「한국의 N%」 · 「갈 수 없」 · can't go · cannot go · legal criteria.
  제출 전 `grep -riE 'TourAPI|KTO|Korea Tourism|Lv0|Lv6' lib/i18n/` → 0건.
- 수치는 개수와 「N in 1,000」「N in 10」만. 모든 수치에 산출일(`meta.asOf`). 이미지에 「ⓒ한국관광공사」.
