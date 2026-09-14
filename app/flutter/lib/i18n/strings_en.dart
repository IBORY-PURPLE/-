// 사용자 노출 UI 문자열 — 한 파일에만 둔다 (제출 전 금지어 grep 대상).
// 문구 출처: Docs/mockup/01_landing.html · 05_states.html · mockup.js (그대로).
// 금지어 목록은 프로젝트 CLAUDE.md · TSD §9 참조 — 이 파일 자체가 grep 에 걸리지 않도록 여기엔 적지 않는다.
// 수치는 개수와 「N in 1,000」「N in 10」만. 모든 수치에 산출일. 이미지에 「ⓒ한국관광공사」.

abstract final class S {
  // ── 공통 ──
  static const String appTitleKo = '말길';
  static const String appTitleEn = 'Malgil';
  static const String sourceCaption = 'ⓒ한국관광공사'; // KtoImage 자동 캡션

  // ── 랜딩 (01_landing.html) ──
  static const String landingHeadline = 'Where does your Korean actually work?';
  static const String landingDescription =
      'Pick your TOPIK level. The map shows which regions open at that level — and where locals will only speak Korean to you.';
  static const String showMyMap = 'Show my map';
  static const String judgePreview = 'Judge preview — start at Lv3';

  /// 급수 카드 4장: (급수 숫자, 라벨, TOPIK, 설명)
  static const List<LevelCardText> levelCards = [
    LevelCardText(2, 'Lv1~2', 'TOPIK 1–2 or none',
        'Places where foreign visitors already come. Survival Korean: ordering, buying.'),
    LevelCardText(3, 'Lv3', 'TOPIK 3',
        'Metropolitan districts and well-visited cities where staff simply answer in Korean.'),
    LevelCardText(4, 'Lv4', 'TOPIK 4', 'Counties and small cities. Korean from the bus stop to the diner.'),
    LevelCardText(5, 'Lv5', 'TOPIK 5–6', 'Rural counties where 4 in 10 residents are 65+. Dialect, stories, asking back.'),
  ];

  // ── 푸터 (01_landing.html .footer-source) ──
  static String footerSource(String asOf) =>
      'Regional levels from public data: visitor mix (ⓒ한국관광공사), Korean-language listing count, resident age (행정안전부 주민등록). Computed $asOf.';
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
      'Reorganized on 2026-07-01 — only $months ${months == 1 ? 'month' : 'months'} of visitor data. Level pending.';
  static const String excludedText = 'Fewer than 20 listed places — not enough to draw a map.';

  /// whyText 폴백 조각 (근거_en 이 빈 행에서만) — 자산 근거_en 과 같은 표기: 「4 foreign visitors per 1,000 · county · 4 in 10 residents aged 65+ · 106 Korean-language listings」
  static String whyForeign(int per1000) => '$per1000 foreign visitors per 1,000';
  static const Map<String, String> whyGubun = {'자치구': 'metropolitan district', '시': 'city', '군': 'county'};
  static String whyAged65(int in10) => '$in10 in 10 residents aged 65+';
  static String whyListings(int n) => '$n Korean-language listings';

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

  // ── 지도 화면 (02_map.html) ──
  static const String yourMap = 'Your map';
  static const String openNow = 'Open now ';
  static String ofRegions(int total) => ' of $total regions';
  static const String depopPrefix = 'Depopulation areas: ';
  static String depopSuffix(int total89) => ' of $total89 open';
  static String atNextLevel(String lvLabel) => 'At $lvLabel: ';
  static String plusRegions(int delta) => '+$delta';
  static const String regionsDash = ' regions — ';
  static const String everyRegionOpen = 'Every region is open at this level.';
  static const String provinceHint = 'Province';
  static const String districtHint = 'District';
  static const String toggle89 = '89 depopulation areas';
  static const String legendAnyLevel = 'Any level (foreign visitors already come)';
  static const String legendLocked = 'Opens at a higher level';
  static const String legend89 = 'Depopulation area (89)';
  static const String legendHold = 'On hold (reorganized 2026-07)';
  static const String legendExcluded = 'Not enough data';
  static const String legendNote =
      'Color = the TOPIK level at which a region opens, from public visitor and population data. Not a measure of on-site foreign-language service.';
  static const String pickRegionHint = 'Tap a region on the map, or pick a district above, to see its details.';

  // ── 지역 시트 (mockup.js fillSheet) ──
  static String computedSource(String asOf) => 'Computed $asOf · 출처: ⓒ한국관광공사 · 행정안전부 주민등록 인구';
  static const String placesLive = 'Places · live';
  static const String localCompanion = 'Local companion';
  static const String localCompanionBody = 'Recruiting in this area. Until then, book a licensed cultural tourism interpreter.';
  static const String openKctg = 'Open kctg.or.kr ↗';
  static const String kctgUrl = 'https://www.kctg.or.kr';
  static const String stayedToday = 'I stayed here today (self-reported)';
  static String nthStay(int n, String nm) => 'This is your ${ordinal(n)} stay in $nm';
  static const String stayNoteKo1 = '생활인구로 산정되는 것과 같은 형태의 체류입니다.';
  static const String stayNoteKo2 = '본 지표는 행정안전부 생활인구 산정 결과가 아니며, 사용자가 스스로 확인하도록 만든 자체 지표입니다.';

  // ── 동네 말벗 세션 (PRD F7 · 기획서 §5-3) — 지역 시트·장소 상세의 Local companion 카드 안에만 (별도 탭 없음) ──
  //  상태는 전부 recruiting (허위 슬롯 금지). 가격·좌석·날짜 없음. 잠금 문구는 「Opens at …」 + 지도는 계속 쓸 수 있다는 꼬리만.
  static const String sessionS2Title = 'Market regulars alley';
  static const String sessionS2Body =
      'Thirty years at the same market — your companion walks you in and introduces you to the stallholders they greet by name.';
  static const String sessionS1Title = "Driver's diner table";
  static const String sessionS1Body =
      "A set-meal diner where you'll be the only visitor. Share the table; order and pay in Korean, yourself.";
  static const String sessionMax5 = 'Max 5 — the size where stories flow';
  static const String sessionRecruiting = 'Recruiting a local companion here';
  static String sessionOpensAt(String lv) => 'Opens at $lv — keep exploring; the map still works';
  static const String interestCta = "I'm interested (stays on this device)";
  static const String interestNoted = 'Noted on this device — sessions here will show first once a companion is recruited';
  static const String malbeotNoticeKo =
      '동네 말벗은 지도의 마지막 핀이며 별도 상품이 아닙니다. 오프라인 진행은 지역 시니어가 담당하며, 본 공모전 및 한국관광공사의 지원사업과는 무관합니다.';
  static const String malbeotNoticeEn = 'Free pilot sessions only — no price, no booking here.';

  // ── 지도 「Your stays」 (F8 · 체류 자기신고 요약 — 한국어 각주는 시트에 있으니 지도에는 짧은 영어 꼬리만) ──
  static String yourStays(int regions, int days) =>
      'Your stays (self-reported, on this device): $regions ${regions == 1 ? 'region' : 'regions'} · $days ${days == 1 ? 'day' : 'days'}';
  static const String notOfficial = 'Not an official statistic';

  /// 1st · 2nd · 3rd · 4th … 11th · 12th · 13th · 21st
  static String ordinal(int n) {
    final r100 = n % 100;
    if (r100 >= 11 && r100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  // ── 공통 내비게이션 ──
  static const String backToLanding = 'Choose level';
  static const String back = 'Back';
  static const String placeTitle = 'Place';

  // ── 장소 목록 (03_places.html) ──
  static const String livePrefix = 'Live · fetched '; // ● 점 + 시각 hh:mm
  static const String liveSource = ' · 출처: ⓒ한국관광공사';
  static const String typeAll = 'All';
  static const String catAny = 'Any topic';

  /// contenttypeid → 칩 라벨 (03_places.html TYPE)
  static const Map<String, String> typeLabel = {'12': 'Sights', '14': 'Culture', '15': 'Festivals', '39': 'Food'};

  /// lclsSystm1 → 칩 라벨 (03_places.html CAT)
  static const Map<String, String> catLabel = {
    'FD': 'Food',
    'HS': 'History',
    'NA': 'Nature',
    'VE': 'Culture',
    'EX': 'Experience',
    'LS': 'Leisure',
    'EV': 'Events',
    'AC': 'Stay',
    'C01': 'Course',
  };

  /// total = 상류 전체 유형 건수(쇼핑 포함) — 괄호는 「보이지 않는 것」을 설명한다 (total 에 걸리지 않게)
  static String placesFooter(int shown, int total, String fetchedAt) =>
      '$shown shown · $total in the public list (shopping and other types not shown) · areaBasedList2 · fetched $fetchedAt';
  static const String unknownRegion = 'Region not in the level table';

  // ── 장소 상세 (04_place.html) ──
  static String thisRegion(String lv) => 'This region: $lv';
  static const String why = 'why ▸';
  static const String type3Caption = ' · 변경금지(Type3)';
  static const String koreanHereTitle = "Korean you'll use here";
  static const String koreanHereSub = 'From the menu as listed (firstmenu · treatmenu). Nothing invented.';
  static const String tryPrefix = 'Try: ';
  static String tryOrder(String menu) => '「$menu 하나 주세요」';
  static const String tryPrice = '「이거 얼마예요?」';
  static const String about = 'About';
  static const String readMore = 'Read more';
  static const String showLess = 'Show less';
  static const String hours = 'Hours';
  static const String closed = 'Closed';
  static const String parking = 'Parking';
  static const String phone = 'Phone';
  static const String reservation = 'Reservation';
  static const String localCompanionBodyLong =
      'Recruiting in this area — a resident who has lived here 10+ years, talking with you in Korean. Not a tour; no price, no booking here.';
  static const String licensedInterpreter = 'Licensed interpreter booking (kctg.or.kr) ↗';
  static const String visitedHere = 'I visited here (self-reported, stays on this device)';
  static String placeFooter(String fetchedAt, {required bool withIntro}) =>
      'Fetched $fetchedAt · detailCommon2${withIntro ? ' + detailIntro2' : ''} · 출처: ⓒ한국관광공사 · nothing stored on our server';
  static const String placeNotListed = 'This place is no longer listed';
  static const String placeNotListedBody = 'The listing was removed from the public tourism database.';
}

class LevelCardText {
  const LevelCardText(this.level, this.label, this.topik, this.description);
  final int level;
  final String label;
  final String topik;
  final String description;
}
