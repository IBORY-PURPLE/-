# 말길 (Malgil)

> **배운 한국어를 실제로 써먹을 수 있는 곳을 찾아 주고, 그 끝에서 사람을 만나게 하는 여행 서비스**

한국관광공사 관광정보에 등재된 음식점 13,497곳 중 영문으로 열려 있는 곳은 **307곳(2.27%)**입니다.
말길은 공사의 국문·영문 관광정보 두 API의 **차이 자체를 지표로 환산**해, 사용자의 한국어 레벨에서 한국어가 실제로 필요한 곳이 어디인지 보여줍니다.

**말길** = 말 + 길. "말길이 트이다" — 말이 통하기 시작한다는 뜻의 한국어 관용구입니다.

---

## 프로젝트 개요

| 항목 | 내용 |
|---|---|
| 공모전 | 2026 관광데이터 활용 공모전 (웹·앱 구현 부문) |
| 지정과제 | 4번 — 일회성 관광의 한계 및 인구감소지역 생활인구 유입 |
| 서비스 형태 | 반응형 웹 |
| 핵심 데이터 | 한국관광공사 OpenAPI (`KorService2` / `EngService2`) |

### 핵심 개념

- **PLL (Place Language Level)** — `PLL n = TOPIK n급 화자가 통역 없이 이용할 수 있는 수준`
- **레벨 눈금** — Lv1~Lv5 (TOPIK 급수 기반)
- **RLL (Region Language Level)** — 시군구 229개 단위 다국어 커버리지

---

## 저장소 구조

```
├── data/                  # 관광공사 OpenAPI 수집·가공 스크립트
│   ├── dump.py            #   국문·영문 API 전수 수집
│   ├── join.py            #   국문·영문 카탈로그 대조
│   ├── cross.py           #   유형별 커버리지 교차 분석
│   ├── agejoin.py         #   시군구 연령 데이터 결합
│   ├── build89b.py        #   인구감소지역 89곳 레이어 생성
│   ├── deep.py            #   심층 분석
│   ├── age_sgg_utf8.csv   #   시군구 연령 데이터
│   ├── malgil_89_join.csv #   인구감소지역 89곳 결합 결과
│   └── malgil_18_join.csv #   18개 지역 결합 결과
│
├── Docs/                  # 기획 문서
│   ├── PRD.md             #   제품 요구사항 정의서
│   ├── TSD.md             #   기술 명세서
│   ├── 말길_공모전_통합가이드_v1.md
│   └── _archive/          #   기획서 버전 이력 (v0.4 ~ v0.6)
│
└── risk_Hypothesis/       # 위험가설 검증 리포트
    └── 위험가설검증_H1_세종학당_취업목적.md
```

---

## 실행 방법

### 1. API 키 설정

한국관광공사 OpenAPI 서비스키가 **환경변수**로 필요합니다.
[공공데이터포털](https://www.data.go.kr)에서 발급받은 **Decoding 키**를 사용하세요.

**PowerShell**
```powershell
$env:TOUR_API_KEY = "발급받은_서비스키"
```

**bash / zsh**
```bash
export TOUR_API_KEY="발급받은_서비스키"
```

> ⚠️ 서비스키를 소스코드에 직접 적지 마세요. `.gitignore`가 `.env`를 차단하고 있습니다.

### 2. 데이터 수집

```bash
python data/dump.py
```

국문(`KorService2`)·영문(`EngService2`) 관광정보를 전수 수집해 `dump.json`으로 저장합니다.
(`dump.json`은 용량 문제로 `.gitignore` 처리되어 있습니다 — 스크립트로 재생성하세요.)

### 3. 분석

```bash
python data/join.py     # 국문·영문 카탈로그 대조
python data/cross.py    # 유형별 커버리지 교차 분석
python data/build89b.py # 인구감소지역 89곳 레이어
```

---

## 데이터 출처

- [한국관광공사 국문 관광정보 서비스 (KorService2)](https://www.data.go.kr)
- [한국관광공사 영문 관광정보 서비스 (EngService2)](https://www.data.go.kr)
- [행정안전부 인구감소지역 지정 현황 (89개 시군구)](https://www.mois.go.kr/frt/sub/a06/b06/populationDecline/screen.do)

---

## 라이선스

기획 문서 및 분석 결과의 저작권은 작성자에게 있습니다.
공모전 출품작으로, 무단 복제 및 재사용을 금합니다.
