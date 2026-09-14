// 사용자 노출 UI 문자열 — 한 파일에만 둔다 (제출 전 금지어 grep 대상).
// 문구 출처: Docs/mockup/01_landing.html · 05_states.html · mockup.js (그대로).
// 금지어 목록은 프로젝트 CLAUDE.md · TSD §9 참조 — 이 파일 자체가 grep 에 걸리지 않도록 여기엔 적지 않는다.
// 수치는 개수와 「N in 1,000」「N in 10」만. 모든 수치에 산출일. 이미지에 「ⓒ한국관광공사」.

abstract final class S {
  // ── 공통 ──
  static const String appTitleKo = '말길';
  static const String appTitleEn = 'Malgil';
  static const String sourceCaption = 'ⓒ한국관광공사'; // KtoImage 자동 캡션
  static const String computedPrefix = 'Computed '; // + 산출일

  // ── 랜딩 (01_landing.html) ──
  static const String landingHeadline = 'Where does your Korean actually work?';
  static const String landingDescription =
      'Pick your TOPIK level. The map shows which regions open at that level — and where locals will only speak Korean to you.';
  static const String showMyMap = 'Show my map';
  static const String judgePreview = 'Judge preview — start at Lv3';

  /// 급수 카드 4장: (급수 숫자, 라벨, TOPIK, 설명)
  static const List<LevelCardText> levelCards = [
    LevelCardText(2, 'Lv1–2', 'TOPIK 1–2 or none',
        'Places where foreign visitors already come. Survival Korean: ordering, buying.'),
    LevelCardText(3, 'Lv3', 'TOPIK 3',
        'Metropolitan districts and well-visited cities where staff simply answer in Korean.'),
    LevelCardText(4, 'Lv4', 'TOPIK 4', 'Counties and small cities. Korean from the bus stop to the diner.'),
    LevelCardText(5, 'Lv5', 'TOPIK 5–6', 'Rural counties where 4 in 10 residents are 65+. Dialect, stories, asking back.'),
  ];

  // ── 푸터 (01_landing.html .footer-source) ──
  static String footerSource(String asOf) =>
      'Regional levels from public data: visitor mix (ⓒ한국관광공사), Korean-only listings, resident age (행정안전부 주민등록). Computed $asOf.';
  static const String footerBoundaries = 'Boundaries: 통계청 SGIS via vuski/admdongkor (CC BY 4.0).';

  // ── 급수 칩 (mockup.js LV_LABEL · fillSheet lvText) ──
  static const String chipLv12 = 'Lv1~2';
  static const String chipLv3 = 'Lv3';
  static const String chipLv4 = 'Lv4';
  static const String chipLv5 = 'Lv5';
  static const String chipAnyLevel = 'Any level';
  static const String chipHold = 'On hold';
  static const String chipExcluded = 'Not enough data';
  static const String badge89 = 'Depopulation area';
  static const Map<int, String> topikOf = {2: 'TOPIK 1–2 or none', 3: 'TOPIK 3', 4: 'TOPIK 4', 5: 'TOPIK 5–6'};

  /// 잠긴 지역 문구 (mockup.js lockedText) — 「방문 불가」류 표현 금지, 「you can still visit」를 유지
  static String lockedText(String lv) => 'Opens at $lv — you can still visit; expect Korean for transport and ordering';
  static String holdText(int months) =>
      'Reorganized on 2026-07-01 — only $months month of visitor data. Level pending.';
  static const String excludedText = 'Fewer than 20 listed places — not enough to draw a map.';

  // ── 상태 (05_states.html) ──
  static const String emptyTitle = 'No places listed in this category';
  static const String emptyDescription = 'Try another filter — nothing is broken.';
  static const String emptyAction = 'Show all';
  static const String errorTitle = 'Live data unavailable';
  static String errorCached(int minutes) => 'Showing listings from $minutes min ago.';
  static const String errorNoCache = 'Could not reach live data.';
  static const String retry = 'Retry';
  static const String quotaTitle = 'Daily API quota reached';
  static const String quotaBody =
      'Live tourism data returns tomorrow (1,000 calls per operation per day). Levels and the map still work.';
  static String quotaNote(String asOf) =>
      'Map and level card are unaffected — they use bundled public data computed $asOf.';

  // ── 자리표시 화면 ──
  static const String comingSoon = 'Coming in the next build';
  static const String currentLevel = 'Your level';
  static const String noLevelYet = 'Not chosen yet';
  static const String backToLanding = 'Choose level';
  static const String mapTitle = 'Level map';
  static const String regionTitle = 'Region';
  static const String placeTitle = 'Place';
}

class LevelCardText {
  const LevelCardText(this.level, this.label, this.topik, this.description);
  final int level;
  final String label;
  final String topik;
  final String description;
}
