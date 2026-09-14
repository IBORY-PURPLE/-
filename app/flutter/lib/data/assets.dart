// 앱 자산(assets/data/build_app_assets.json) 파싱 · 모델 · 급수 상태 규칙.
// 규칙은 Docs/mockup/mockup.js(stateOf · isOpen · baseRows · summary)와 같다.
//
// ★ 앱의 「열린 곳수 · 89곳 곳수」는 자산 `요약` 값을 그대로 쓴다(재계산하지 않음).
//   [summaryOf]는 테스트에서 지역 행 재계산 == 요약 검사용이다.
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/services.dart' show rootBundle;

const String assetPath = 'assets/data/build_app_assets.json';

/// 시군구 급수 라벨 ↔ 숫자 (mockup.js LV_NUM / LV_LABEL)
const Map<String, int> lvNum = {'Lv1~2': 2, 'Lv3': 3, 'Lv4': 4, 'Lv5': 5};
const Map<int, String> lvLabel = {2: 'Lv1~2', 3: 'Lv3', 4: 'Lv4', 5: 'Lv5'};
const List<String> lvOrder = ['Lv1~2', 'Lv3', 'Lv4', 'Lv5'];
const String lvHold = '보류';
const String lvExcluded = '제외';

/// 지역 → 화면 상태 (mockup.js stateOf)
enum RegionState { lv12, lv3, lv4, lv5, locked, hold, excluded }

RegionState stateOf(Region r, int userLevel) {
  final lv = r.lv;
  if (lv == lvHold) return RegionState.hold;
  if (lv == lvExcluded) return RegionState.excluded;
  if (lv == 'Lv1~2') return RegionState.lv12;
  final n = lvNum[lv];
  if (n == null) return RegionState.excluded;
  if (n > userLevel) return RegionState.locked;
  return switch (n) { 3 => RegionState.lv3, 4 => RegionState.lv4, _ => RegionState.lv5 };
}

bool isOpen(Region r, int userLevel) {
  final s = stateOf(r, userLevel);
  return s == RegionState.lv12 || s == RegionState.lv3 || s == RegionState.lv4 || s == RegionState.lv5;
}

/// 시군구 행 (자산 `지역` 1행 — 필드 전부)
class Region {
  const Region({
    required this.code,
    required this.sido,
    required this.nm,
    required this.gubun,
    required this.lv,
    required this.reasonKo,
    required this.reasonEn,
    required this.share,
    required this.pb,
    required this.kor,
    required this.e65,
    required this.pop,
    required this.is89,
    required this.months,
    required this.parent,
  });

  final String code; // 행정표준코드 5자리
  final String sido;
  final String nm;
  final String gubun; // 구분: 군 · 자치구 · 시
  final String lv; // Lv1~2 · Lv3 · Lv4 · Lv5 · 제외 · 보류
  final String reasonKo; // 근거_ko
  final String reasonEn; // 근거_en
  final double? share; // 외국인 방문 비중 %
  final double? pb; // 내국인 방문 규모 백분위 (보류면 null)
  final int? kor; // 국문 관광자원 건수
  final double? e65; // 65세 이상 비율 %
  final int? pop; // 주민등록 총인구
  final bool is89; // 인구감소지역
  final int? months; // 방문자 집계 개월 수
  final String? parent; // 일반구가 속한 시 code. 기초지자체는 null

  /// 기초지자체 행인가 (일반구는 parent 로 접음 — mockup.js baseRows)
  bool get isBase => parent == null || parent == code;

  /// 「1,000명 중 N명」 정수 (최소 1) — 백분율 표기 금지 규칙용
  int? get foreignPer1000 => share == null ? null : (share! * 10).round().clamp(1, 1000);

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        code: j['code'] as String,
        sido: j['sido'] as String,
        nm: j['nm'] as String,
        gubun: (j['구분'] as String?) ?? '',
        lv: j['lv'] as String,
        reasonKo: (j['근거_ko'] as String?) ?? '',
        reasonEn: (j['근거_en'] as String?) ?? '',
        share: (j['share'] as num?)?.toDouble(),
        pb: (j['pb'] as num?)?.toDouble(),
        kor: (j['kor'] as num?)?.toInt(),
        e65: (j['e65'] as num?)?.toDouble(),
        pop: (j['pop'] as num?)?.toInt(),
        is89: j['is89'] == true,
        months: (j['months'] as num?)?.toInt(),
        parent: j['parent'] as String?,
      );
}

/// 자산 `메타` — 산출일 · viewBox · 표시문구 · 곳수
class Meta {
  const Meta({
    required this.asOf,
    required this.generatedOn,
    required this.viewBox,
    required this.bbox,
    required this.sourceNotice,
    required this.ruleConstants,
    required this.counts,
    required this.raw,
  });

  final String asOf; // 산출일 (P-T05 — 화면 병기)
  final String generatedOn; // 생성일
  final String viewBox; // "0 0 1000 1300"
  final List<int> bbox; // [xmin, ymin, xmax, ymax]
  final String sourceNotice; // 라이선스.표시문구
  final Map<String, num> ruleConstants; // KOR_T · SHARE_T · OLD65_T · PB_T
  final Map<String, int> counts; // 시군구수 · 기초지자체수 · 일반구수 · 인구감소지역수 · 경계수
  final Map<String, dynamic> raw;

  double get viewW => double.tryParse(viewBox.split(' ')[2]) ?? 1000;
  double get viewH => double.tryParse(viewBox.split(' ')[3]) ?? 1300;

  factory Meta.fromJson(Map<String, dynamic> j) {
    final lic = (j['라이선스'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rc = (j['규칙상수'] as Map?)?.cast<String, dynamic>() ?? const {};
    const countKeys = ['시군구수', '기초지자체수', '일반구수', '인구감소지역수', '경계수', '급수후보수'];
    return Meta(
      asOf: (j['산출일'] as String?) ?? (j['생성일'] as String?) ?? '',
      generatedOn: (j['생성일'] as String?) ?? '',
      viewBox: (j['viewBox'] as String?) ?? '0 0 1000 1300',
      bbox: ((j['bbox'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      sourceNotice: (lic['표시문구'] as String?) ?? '',
      ruleConstants: {for (final e in rc.entries) e.key: e.value as num},
      counts: {for (final k in countKeys) if (j[k] is num) k: (j[k] as num).toInt()},
      raw: j,
    );
  }
}

/// 급수 칸 하나의 곳수 (전체 · 89곳)
class LevelCount {
  const LevelCount({required this.total, required this.of89});
  final int total;
  final int of89;

  factory LevelCount.fromJson(Map<String, dynamic> j) =>
      LevelCount(total: (j['전체'] as num).toInt(), of89: (j['89곳'] as num).toInt());
}

/// 사용자 급수별 누적 열린 곳 1행
class OpenRow {
  const OpenRow({required this.userLv, required this.openLv, required this.total, required this.of89});
  final String userLv; // 'Lv3'
  final String openLv; // 'Lv1~2 + Lv3'
  final int total;
  final int of89;

  int get userLevel => lvNum[userLv] ?? 0;

  factory OpenRow.fromJson(Map<String, dynamic> j) => OpenRow(
        userLv: j['사용자급수'] as String,
        openLv: (j['열린lv'] as String?) ?? '',
        total: (j['전체'] as num).toInt(),
        of89: (j['89곳'] as num).toInt(),
      );
}

/// 자산 `요약` 그대로 — 앱 화면의 곳수는 여기서만 읽는다.
class Summary {
  const Summary({required this.baseCount, required this.count89, required this.byLevel, required this.openByUser, required this.raw});
  final int baseCount; // 기초지자체 230
  final int count89; // 인구감소지역 89
  final Map<String, LevelCount> byLevel; // 급수별곳수
  final List<OpenRow> openByUser; // 사용자급수별누적열린곳
  final Map<String, dynamic> raw;

  OpenRow? openFor(int userLevel) {
    for (final r in openByUser) {
      if (r.userLevel == userLevel) return r;
    }
    return null;
  }

  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
        baseCount: (j['기초지자체'] as num).toInt(),
        count89: (j['인구감소지역'] as num).toInt(),
        byLevel: {
          for (final e in ((j['급수별곳수'] as Map?) ?? const {}).entries)
            e.key as String: LevelCount.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        openByUser: ((j['사용자급수별누적열린곳'] as List?) ?? const [])
            .map((e) => OpenRow.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        raw: j,
      );
}

/// 자산 전체
class MalgilAssets {
  const MalgilAssets({
    required this.meta,
    required this.rules,
    required this.summary,
    required this.regions,
    required this.boundaries,
    required this.description,
  });

  final Meta meta;
  final Map<String, dynamic> rules; // 급수규칙 (상수 · 순서 · 감도표) 원본
  final Summary summary;
  final List<Region> regions; // 269행 (자산 순서)
  final Map<String, List<List<Offset>>> boundaries; // code → 링들(정수→double)
  final Map<String, dynamic> description; // `_설명` 원본 (있으면)

  Map<String, Region> get byCode => {for (final r in regions) r.code: r};

  /// 기초지자체 행만 (일반구 제외) — mockup.js baseRows
  List<Region> get baseRegions => regions.where((r) => r.isBase).toList();

  /// 경계 폴리곤에 칠할 급수의 출처 행 — 일반구면 parent 시 행 (mockup.js renderMap src)
  Region? sourceRegionFor(String boundaryCode) {
    final map = byCode;
    final row = map[boundaryCode];
    if (row == null) return null;
    if (row.parent != null && row.parent != row.code) return map[row.parent!] ?? row;
    return row;
  }

  /// JSON 파싱 — `데이터` 키가 있으면 그것, 없으면 최상위(하위호환).
  factory MalgilAssets.fromJson(Map<String, dynamic> root) {
    final data = (root['데이터'] is Map) ? (root['데이터'] as Map).cast<String, dynamic>() : root;
    final meta = Meta.fromJson(((data['메타'] as Map?) ?? const {}).cast<String, dynamic>());
    final rules = ((data['급수규칙'] as Map?) ?? const {}).cast<String, dynamic>();
    final summary = Summary.fromJson(((data['요약'] as Map?) ?? const {}).cast<String, dynamic>());
    final regions = ((data['지역'] as List?) ?? const [])
        .map((e) => Region.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final boundaries = <String, List<List<Offset>>>{};
    ((data['경계'] as Map?) ?? const {}).forEach((code, rings) {
      boundaries[code as String] = (rings as List)
          .map((ring) => (ring as List)
              .map((p) => Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()))
              .toList())
          .toList();
    });
    final desc = (root['_설명'] is Map) ? (root['_설명'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return MalgilAssets(meta: meta, rules: rules, summary: summary, regions: regions, boundaries: boundaries, description: desc);
  }

  static MalgilAssets parse(String jsonText) => MalgilAssets.fromJson((jsonDecode(jsonText) as Map).cast<String, dynamic>());
}

/// rootBundle 에서 자산을 읽는다 (runApp 전 1회).
Future<MalgilAssets> loadAssets() async {
  final text = await rootBundle.loadString(assetPath);
  return MalgilAssets.parse(text);
}

/// 지역 행 재계산 결과 (mockup.js summary 와 같은 규칙) — 테스트 대조용.
class ComputedSummary {
  const ComputedSummary({required this.total, required this.open, required this.total89, required this.open89, required this.next, required this.nextLv});
  final int total; // 판정 대상(보류·제외 제외) 기초지자체 수
  final int open; // 내 급수에 열린 곳
  final int total89;
  final int open89;
  final List<Region> next; // 다음 급수에 새로 열릴 곳
  final int? nextLv;
}

ComputedSummary summaryOf(MalgilAssets a, int userLevel) {
  final rows = a.baseRegions;
  final countable = rows.where((r) => r.lv != lvHold && r.lv != lvExcluded).toList();
  final open = countable.where((r) => isOpen(r, userLevel)).toList();
  final r89 = rows.where((r) => r.is89).toList();
  final open89 = r89.where((r) => isOpen(r, userLevel)).toList();
  final nextLv = userLevel < 5 ? userLevel + 1 : null;
  final next = nextLv == null ? <Region>[] : countable.where((r) => lvNum[r.lv] == nextLv).toList();
  return ComputedSummary(total: countable.length, open: open.length, total89: r89.length, open89: open89.length, next: next, nextLv: nextLv);
}
