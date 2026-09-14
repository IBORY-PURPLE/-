# 말길 (Malgil)

> **배운 한국어를 실제로 써먹을 수 있는 곳을 찾아 주고, 그 끝에서 사람을 만나게 하는 여행 서비스**

말길은 한국관광공사 국문 관광정보 · 지역별 방문자수 · 주민등록 인구를 묶어 **「그 동네에 가면 한국어를 쓰게 되는가」**를 TOPIK 급수 눈금 위에 올립니다. 대전 중구는 방문자 1,000명 중 외국인이 4명(2026-09-10 산출)이고, 내국인은 상위 26% 수준으로 옵니다 — 한국인에게는 확실한 도시인데 외국인만 없는 곳입니다. 그런 동네에서만 한국어가 기본값입니다.

**말길**은 표준국어대사전 등재어입니다 — "말하는 기회 또는 실마리". **말길이 트이다** — "남에게 소개하는 의논의 길이 트이다".

---

## 프로젝트 개요

| 항목 | 내용 |
|---|---|
| 공모전 | 2026 관광데이터 활용 공모전 · ②-2 웹·앱 구현 부문 · 지정과제 4번 (일회성 관광의 한계 · 인구감소지역 생활인구 유입) |
| 병행 출품 | 모두의 창업 프로젝트 · 로컬 트랙 |
| 서비스 형태 | Flutter Web (반응형) + Cloudflare Workers 프록시 |
| 핵심 데이터 | 한국관광공사 OpenAPI `KorService2` · `DataLabService`(지역별 방문자수) · `Odii`(오디오가이드) · `LocgoHubTarService1`(중심관광지) — **외부 지도 SDK 없음** |
| 플러스알파 공공데이터 | 행정안전부 주민등록 연령별 인구 · 인구감소지역 89곳 고시 · 시군구 경계(통계청 SGIS → [vuski/admdongkor](https://github.com/vuski/admdongkor), CC BY 4.0) |

### 핵심 개념

- **레벨 눈금** — Lv1~Lv5 (TOPIK 급수). `Lv0` · `Lv6` 표기는 쓰지 않습니다.
- **지역 급수** — 기초지자체마다 「몇 급이면 열리는가」를 공공데이터 축(외국인 방문 비중 · 내국인 방문 백분위 · 국문 관광자원 두께 · 65세 이상 인구 비율)으로 배정합니다. 영문 카탈로그는 쓰지 않습니다(외국인은 영어권만이 아니므로).
- **동네 말벗** — 지도의 가장 깊은 층. 로컬에 닿으면 그 동네 시니어를 부를 수 있습니다(제출본은 관심 등록까지).

---

## 저장소 구조

```
├── data/
│   ├── AI/                 # AI가 읽는 것 — 수집·분석 스크립트
│   │   ├── pull_visitor.py         지역별 방문자수 수집 → _raw/
│   │   ├── dump.py                 국문 관광정보 전량 덤프 → _raw/dump.json (.gitignore)
│   │   ├── analyze_visitor_gap.py  「내국인은 오는데 외국인은 안 오는 곳」
│   │   ├── analyze_topik_local.py  급수 배정 (기초지자체)
│   │   ├── analyze_89_hypothesis.py 인구감소지역 89곳 급수 분포
│   │   ├── analyze_89_culture.py   89곳 문화관광 자원 두께
│   │   └── _raw/                   원본·중간 파일 (대용량은 .gitignore)
│   └── 인간/               # 사람이 읽는 산출물 — 파일 첫 키 `_설명`에 항목별 뜻·산식·범위·단위·실제 예시
│       ├── analyze_visitor_gap.json
│       ├── analyze_topik_local.json
│       ├── analyze_89_hypothesis.json
│       └── analyze_89_culture.json
│
├── app/                    # ★ 정션 → C:\Users\chewo\StudioProjects\malgil (ASCII 경로)
│   ├── flutter/            #   Flutter Web 앱
│   └── worker/             #   Cloudflare Workers 프록시 (Hono) — 공사 API 키를 여기서만 보관
│
├── Docs/
│   ├── 말길_기획서_v0.8.md  #   프로덕트 기획서 (현행 정본)
│   ├── PRD.md · TSD.md     #   기능 사양 · 기술 명세
│   ├── 말길_문제정의_v1.md
│   ├── plan/               #   데이터 활용 계획 · 실측 리포트 · 평가
│   ├── mockup/             #   HTML 목업 (Flutter 개발 기준 화면)
│   ├── 개발일지.md          #   브랜치별 개발 메모 (사람이 읽는 기록)
│   └── _archive/           #   기획서 버전 이력 (v0.4 ~ v0.7)
│
├── risk_Hypothesis/        # 위험가설 검증 리포트
└── CLAUDE.md               # 프로젝트 규칙 (문서 위계 · data/ 규칙 · 자기설명 규칙)
```

> `app/`이 정션이므로 **`git clean -d`를 쓰지 마세요** — 실파일이 지워집니다.

---

## 실행 방법

### 1. API 키

프로젝트 루트 `.env`에 공공데이터포털 **Decoding 키**를 둡니다 (`.gitignore` 대상).

```
Api_Key_Decoding=발급받은_서비스키
```

### 2. 데이터 파이프라인 (수집 → 분석 → 앱 자산)

```bash
python data/AI/pull_visitor.py          # 지역별 방문자수 12개월 → _raw/c1_visitor_raw.json
python data/AI/dump.py                  # 국문 관광정보 전량 → _raw/dump.json
python data/AI/analyze_visitor_gap.py   # → 인간/analyze_visitor_gap.json
python data/AI/analyze_topik_local.py   # → 인간/analyze_topik_local.json
python data/AI/analyze_89_hypothesis.py # → 인간/analyze_89_hypothesis.json
```

산출물마다 `_설명` 블록에 생성일 · 입력 · 정렬 · 행수 · 항목 설명이 있습니다. 모든 수치는 산출일과 함께 읽습니다(카탈로그와 방문자 데이터는 계속 바뀝니다).

### 3. 앱

```bash
cd app/flutter && flutter run -d chrome          # 로컬 실행
cd app/flutter && flutter build web --no-web-resources-cdn
cd app/worker  && npx wrangler dev               # 프록시 로컬 (.dev.vars 에 KTO_KEY)
cd app/worker  && npx wrangler deploy            # 배포 (wrangler login 필요)
```

---

## 데이터 출처

- 한국관광공사 OpenAPI — 국문 관광정보(`KorService2`) · 빅데이터 지역별 방문자수(`DataLabService`) · 관광지 오디오가이드(`Odii`) · 기초지자체 중심 관광지(`LocgoHubTarService1`) — 화면 표기 `출처: ⓒ한국관광공사`
- [행정안전부 인구감소지역 지정 현황 (89개 시군구)](https://www.mois.go.kr/frt/sub/a06/b06/populationDecline/screen.do)
- 행정안전부 주민등록 연령별 인구 통계
- 시군구 경계 — 통계청 SGIS(공공누리 제1유형) 원자료를 [vuski/admdongkor](https://github.com/vuski/admdongkor)가 정리한 `sgg_20260701_light.parquet` (CC BY 4.0, 2026-07-01 행정구역 개편 반영)

---

## 라이선스

기획 문서 및 분석 결과의 저작권은 작성자에게 있습니다.
공모전 출품작으로, 무단 복제 및 재사용을 금합니다.
