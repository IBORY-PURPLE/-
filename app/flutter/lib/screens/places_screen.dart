// /region/:code — Docs/mockup/03_places.html 과 1:1.
//  AppBar(← 지도 · 지역 이름) · LevelChip + 근거_en · 「● Live · fetched hh:mm · 출처」 ·
//  유형 칩(All · Sights · Culture · Festivals · Food = contenttypeid, 클라이언트 필터) ·
//  대분류 칩(Any topic + 응답의 lclsSystm1) · PlaceCard 목록 · 푸터
//  ★ ApiClient.places(code) 1콜 (type 미지정 → 서버가 12·14·15·39 만 남김). 칩 전환은 추가 호출 없음.
//  ★ 목록 카드에는 급수 배지를 두지 않는다 (PRD F5 — 급수는 지역 단위, 장소 단위가 아니다)
//  ★ 이미지는 KtoImage 로만 — Type1 만 cover, 그 외 contain (회귀 #5) · 이미지 없으면 텍스트 히어로 (회귀 #4)
//  상태: 로딩 스켈레톤 · 빈 필터 · quota 배너(일일 한도만) · error 배너 + Retry (직전 성공 응답이 있으면 그대로 두고 「N min ago」)
//  ★ 워커 IP 레이트리밋 429(kind rate_limited)는 한도가 아니므로 quota 배너를 쓰지 않는다 — error + Retry (TSD §8-3 정직한 배너)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../data/api.dart';
import '../data/assets.dart';
import '../data/format.dart';
import '../i18n/strings_en.dart';
import '../theme/tokens.dart';
import '../widgets/kto_image.dart';
import '../widgets/level_chip.dart';
import '../widgets/state_views.dart';

/// 목록 1행 (areaBasedList2 items[] 필드 중 화면이 쓰는 것)
class PlaceRow {
  const PlaceRow({
    required this.contentId,
    required this.typeId,
    required this.title,
    required this.addr1,
    required this.image,
    required this.cpyrhtDivCd,
    required this.cat1,
    required this.cat2,
  });

  final String contentId;
  final String typeId; // 12 · 14 · 15 · 39
  final String title;
  final String addr1;
  final String? image; // firstimage → 없으면 firstimage2 → 없으면 null (텍스트 히어로)
  final String? cpyrhtDivCd;
  final String cat1; // lclsSystm1
  final String cat2; // lclsSystm2

  static String _s(Map<String, dynamic> m, String k) => (m[k] ?? '').toString().trim();

  factory PlaceRow.fromJson(Map<String, dynamic> m) {
    final img1 = _s(m, 'firstimage');
    final img2 = _s(m, 'firstimage2');
    return PlaceRow(
      contentId: _s(m, 'contentid'),
      typeId: _s(m, 'contenttypeid'),
      title: _s(m, 'title'),
      addr1: _s(m, 'addr1'),
      image: img1.isNotEmpty ? img1 : (img2.isNotEmpty ? img2 : null),
      cpyrhtDivCd: _s(m, 'cpyrhtDivCd'),
      cat1: _s(m, 'lclsSystm1'),
      cat2: _s(m, 'lclsSystm2'),
    );
  }

  String get typeLabel => S.typeLabel[typeId] ?? typeId;

  /// 텍스트 히어로 라벨 — 대분류 라벨, 없으면 유형 라벨 (03_places.html)
  String get heroLabel => S.catLabel[cat1] ?? typeLabel;

  /// 「Food · FD02」 — 유형 라벨 + lclsSystm2 (있을 때만)
  String get kindLine => cat2.isEmpty ? typeLabel : '$typeLabel · $cat2';
}

/// 유형·대분류 필터 (mockup draw()) — '' 은 전체
List<PlaceRow> filterRows(List<PlaceRow> rows, {String type = '', String cat = ''}) =>
    rows.where((r) => (type.isEmpty || r.typeId == type) && (cat.isEmpty || r.cat1 == cat)).toList();

/// 응답에 등장한 lclsSystm1 값들 (등장 순 · 중복 제거)
List<String> catsOf(List<PlaceRow> rows) {
  final seen = <String>{};
  for (final r in rows) {
    if (r.cat1.isNotEmpty) seen.add(r.cat1);
  }
  return seen.toList();
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.code, this.apiClient});
  final String code; // 행정표준코드 5자리
  final ApiClient? apiClient; // 테스트 주입용

  static const double maxWidth = 560;
  static const List<String> typeKeys = ['', '12', '14', '15', '39'];

  @override
  State<PlacesScreen> createState() => PlacesScreenState();
}

class PlacesScreenState extends State<PlacesScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  bool _loading = true;
  ApiResult? _last; // 마지막 응답 (ok · quota · error)
  ApiOk? _lastOk; // 직전 성공 응답 — 오류 시 「Showing listings from N min ago」
  DateTime? _lastOkAt;
  List<PlaceRow> _rows = const [];
  String _type = '';
  String _cat = '';

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  /// 1콜. Retry 도 이 함수. 저장 없음 — 렌더 시점 호출.
  Future<void> reload() async {
    setState(() => _loading = true);
    final r = await _api.places(widget.code);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _last = r;
      if (r is ApiOk) {
        _lastOk = r;
        _lastOkAt = DateTime.now();
        _rows = r.items.map(PlaceRow.fromJson).toList();
      }
    });
  }

  void _showAll() => setState(() {
        _type = '';
        _cat = '';
      });

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context).assets;
    final region = a.sourceRegionFor(widget.code) ?? a.byCode[widget.code];
    final ok = _lastOk;
    final last = _last;
    final shown = filterRows(_rows, type: _type, cat: _cat);

    final children = <Widget>[
      _RegionHeader(region: region, code: widget.code),
      if (ok != null) _LiveLine(fetchedAt: ok.fetchedAt),
      if (last is ApiQuota && last.isDailyQuota) StateViews.quota(asOf: a.meta.asOf),
      if (last is ApiError || (last is ApiQuota && !last.isDailyQuota))
        StateViews.error(
          cachedMinutes: _lastOkAt == null ? null : minutesSince(_lastOkAt!),
          onRetry: _loading ? null : reload,
        ),
      if (_loading && ok == null)
        StateViews.loading()
      else if (ok != null) ...[
        _ChipRow(
          keyPrefix: 'type',
          keys: PlacesScreen.typeKeys,
          label: (k) => k.isEmpty ? S.typeAll : (S.typeLabel[k] ?? k),
          selected: _type,
          onSelect: (k) => setState(() => _type = k),
        ),
        _ChipRow(
          keyPrefix: 'cat',
          keys: ['', ...catsOf(_rows)],
          label: (k) => k.isEmpty ? S.catAny : (S.catLabel[k] ?? k),
          selected: _cat,
          onSelect: (k) => setState(() => _cat = k),
        ),
        if (shown.isEmpty)
          StateViews.empty(onAction: _showAll)
        else ...[
          // push — 상세의 ← 와 브라우저 뒤로가기가 이 목록(필터 유지)으로 돌아온다. go 면 스택이 없어 /map 으로 빠진다.
          for (final r in shown) PlaceCard(row: r, onTap: () => context.push('/place/${r.contentId}')),
          _Footer(text: S.placesFooter(shown.length, ok.totalCount, formatFetchedAt(ok.fetchedAt))),
        ],
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _back(context), tooltip: S.back),
        title: region == null
            ? Text(widget.code)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(region.nm, key: const Key('region-name')),
                  Text(region.sido, style: MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant)),
                ],
              ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PlacesScreen.maxWidth),
          child: ListView(key: const Key('places-list'), children: children),
        ),
      ),
    );
  }
}

/// 급수 칩 + 근거_en 한 줄 (.hdr.row) — 자산에서. 일반구면 parent 시 행.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.region, required this.code});
  final Region? region;
  final String code;

  @override
  Widget build(BuildContext context) {
    final muted = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant);
    final r = region;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: r == null
          ? Text(S.unknownRegion, style: muted)
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KeyedSubtree(key: const Key('region-chip'), child: LevelChip.ofRegion(r, anyLevel: false)),
                Text(r.reasonEn, style: muted),
              ],
            ),
    );
  }
}

/// 「● Live · fetched hh:mm · 출처: ⓒ한국관광공사」 (.live)
class _LiveLine extends StatelessWidget {
  const _LiveLine({required this.fetchedAt});
  final String? fetchedAt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text.rich(
          TextSpan(children: [
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF0CA30C), shape: BoxShape.circle))),
              ),
            ),
            TextSpan(text: '${S.livePrefix}${formatFetchedAt(fetchedAt, timeOnly: true)}${S.liveSource}'),
          ]),
          key: const Key('live-line'),
          style: MalgilType.labelSmall.copyWith(color: MalgilColors.onSurfaceVariant, letterSpacing: 0),
        ),
      );
}

/// 가로 스크롤 FilterChip 한 줄 (.chip-row) — 선택은 secondary-container + ✓ (M3 기본)
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.keyPrefix, required this.keys, required this.label, required this.selected, required this.onSelect});
  final String keyPrefix;
  final List<String> keys;
  final String Function(String) label;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            for (final k in keys) ...[
              FilterChip(
                key: Key('$keyPrefix-${k.isEmpty ? 'all' : k}'),
                label: Text(label(k)),
                selected: selected == k,
                showCheckmark: true,
                onSelected: (_) => onSelect(k),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MalgilShape.cornerSmall)),
              ),
              if (k != keys.last) const SizedBox(width: 8),
            ],
          ],
        ),
      );
}

/// 목록 카드 (.list-item) — 썸네일 96×72 KtoImage · 제목 1줄 말줄임 · addr1 · 유형·lclsSystm2. 급수 배지 없음.
class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.row, this.onTap});
  final PlaceRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        key: Key('place-${row.contentId}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MalgilColors.outlineVariant))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KtoImage(url: row.image, cpyrhtDivCd: row.cpyrhtDivCd, label: row.heroLabel, width: 96, height: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, style: MalgilType.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(row.addr1, style: MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(row.kindLine, style: MalgilType.labelSmall.copyWith(color: MalgilColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// .footer-source — 「n shown · N in the public list (shopping and other types not shown) · areaBasedList2 · fetched …」
class _Footer extends StatelessWidget {
  const _Footer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MalgilColors.outlineVariant))),
        child: Text(text, key: const Key('places-footer'), style: MalgilType.labelSmall.copyWith(fontWeight: FontWeight.w400, color: MalgilColors.onSurfaceVariant)),
      );
}
