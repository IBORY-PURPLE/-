// /map — Docs/mockup/02_map.html 과 1:1.
//  AppBar(← 랜딩 · Your map) · SegmentedButton(급수) + TOPIK · 레벨 카드 · 드롭다운 2단(시도→시군구, ldongCode2 런타임)
//  · 89곳 토글 · 지도(ChoroplethMap) · 범례 · SourceFooter
//  ★ 레벨 카드의 N·M·K 는 자산 `요약` 값 그대로 (재계산 금지 — mockup.js summary 와 같은 정의)
//  ★ 드롭다운은 ApiClient.ldong() 런타임 호출 (PRD F3). 실패·한도면 자산 `지역` 으로 조용히 폴백 (에러 화면 없음)
//  compact(<840) = 시트를 바텀시트로 · expanded(≥840) = 지도 60% : 우측 패널 40%
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../data/api.dart';
import '../data/assets.dart';
import '../i18n/strings_en.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/choropleth_map.dart';
import '../widgets/region_sheet.dart';
import '../widgets/source_footer.dart';

/// 레벨 카드 값 — 자산 `요약` 에서만 읽는다. 다음 급수 지명만 지역 행에서 고른다.
class LevelCardData {
  const LevelCardData({
    required this.level,
    required this.open,
    required this.total,
    required this.open89,
    required this.total89,
    required this.nextLevel,
    required this.nextDelta,
    required this.nextNames,
    required this.nextMore,
  });

  final int level;
  final int open; // 요약.사용자급수별누적열린곳[level].전체
  final int total; // 요약.기초지자체 − 보류 − 제외 (countable)
  final int open89; // 요약.사용자급수별누적열린곳[level].89곳
  final int total89; // 요약.인구감소지역
  final int? nextLevel; // Lv5 면 null
  final int nextDelta; // 다음 급수 누적 − 현재 누적
  final List<String> nextNames; // 다음 급수에 열리는 기초 행 이름 4개 (자산 순서)
  final bool nextMore; // 4개 넘게 있으면 「…」

  static const int namesShown = 4;

  factory LevelCardData.of(MalgilAssets a, int level) {
    final s = a.summary;
    final row = s.openFor(level);
    final total = s.baseCount - (s.byLevel[lvHold]?.total ?? 0) - (s.byLevel[lvExcluded]?.total ?? 0);
    final nextLevel = level < AppState.maxLevel ? level + 1 : null;
    final nextRow = nextLevel == null ? null : s.openFor(nextLevel);
    final delta = (row == null || nextRow == null) ? 0 : nextRow.total - row.total;
    final names = nextLevel == null ? const <String>[] : a.baseRegions.where((r) => lvNum[r.lv] == nextLevel).map((r) => r.nm).toList();
    return LevelCardData(
      level: level,
      open: row?.total ?? 0,
      total: total,
      open89: row?.of89 ?? 0,
      total89: s.count89,
      nextLevel: nextLevel,
      nextDelta: delta,
      nextNames: names.take(namesShown).toList(),
      nextMore: names.length > namesShown,
    );
  }
}

/// 드롭다운 항목 (시도: code 2자리·이름 / 시군구: code 5자리·이름)
class RegionOption {
  const RegionOption(this.code, this.name);
  final String code;
  final String name;
}

/// ldongCode2 응답 → 옵션. 시도는 code 2자리(세종은 5자리로 오므로 앞 2자리), 시군구는 regn + 3자리.
List<RegionOption> optionsFromLdong(List<Map<String, dynamic>> items, {String? regn}) {
  final out = <RegionOption>[];
  for (final it in items) {
    final code = (it['code'] ?? '').toString().trim();
    final name = (it['name'] ?? '').toString().trim();
    if (code.isEmpty || name.isEmpty) continue;
    if (regn == null) {
      out.add(RegionOption(code.length >= 2 ? code.substring(0, 2) : code, name));
    } else {
      out.add(RegionOption(code.length == 3 ? '$regn$code' : code, name));
    }
  }
  return out;
}

/// 폴백 — 자산 `지역` 에서 같은 목록을 만든다 (시도: 첫 등장 순 · 시군구: 기초 행만, mockup.js baseRows)
List<RegionOption> sidoFromAssets(MalgilAssets a) {
  final seen = <String, String>{};
  for (final r in a.regions) {
    seen.putIfAbsent(r.sido, () => r.code.substring(0, 2));
  }
  return [for (final e in seen.entries) RegionOption(e.value, e.key)];
}

List<RegionOption> sggFromAssets(MalgilAssets a, String sidoName) =>
    [for (final r in a.baseRegions) if (r.sido == sidoName) RegionOption(r.code, r.nm)];

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.apiClient});
  final ApiClient? apiClient; // 테스트 주입용. 없으면 같은 오리진 /api/*

  static const double expandedBreakpoint = 840;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  ChoroplethGeometry? _geometry;
  bool _show89 = true;
  String? _selected;
  List<RegionOption> _sidos = const [];
  List<RegionOption> _sggs = const [];
  RegionOption? _sido;
  final TextEditingController _sggCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSidos());
  }

  @override
  void dispose() {
    _sggCtl.dispose();
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  MalgilAssets get _assets => AppScope.of(context).assets;

  ChoroplethGeometry _geo(MalgilAssets a) => _geometry ??= ChoroplethGeometry(a);

  Future<void> _loadSidos() async {
    final a = _assets;
    List<RegionOption> opts = const [];
    try {
      final r = await _api.ldong();
      if (r is ApiOk) opts = optionsFromLdong(r.items);
    } catch (e) {
      debugPrint('MapScreen: ldong failed, asset fallback ($e)');
    }
    if (opts.isEmpty) opts = sidoFromAssets(a);
    if (mounted) setState(() => _sidos = opts);
  }

  Future<void> _loadSggs(RegionOption sido) async {
    final a = _assets;
    List<RegionOption> opts = const [];
    try {
      final r = await _api.ldong(regn: sido.code);
      if (r is ApiOk) opts = optionsFromLdong(r.items, regn: sido.code);
    } catch (e) {
      debugPrint('MapScreen: ldong($sido) failed, asset fallback ($e)');
    }
    if (opts.isEmpty) opts = sggFromAssets(a, sido.name);
    if (mounted && _sido?.code == sido.code) setState(() => _sggs = opts);
  }

  void _onSido(RegionOption? o) {
    if (o == null) return;
    setState(() {
      _sido = o;
      _sggs = const [];
      _sggCtl.clear();
    });
    _loadSggs(o);
  }

  void _onSgg(BuildContext context, String? code5, MalgilAssets a, int lv) {
    if (code5 == null) return;
    final r = a.sourceRegionFor(code5) ?? a.byCode[code5];
    if (r == null) return;
    _open(context, r.code, a, lv);
  }

  void _open(BuildContext context, String code, MalgilAssets a, int lv) {
    final r = a.byCode[code];
    if (r == null) return;
    setState(() => _selected = code);
    final expanded = MediaQuery.sizeOf(context).width >= MapScreen.expandedBreakpoint;
    if (!expanded) {
      RegionSheet.showAsBottomSheet(context, region: r, userLevel: lv, asOf: a.meta.asOf, appState: AppScope.of(context).appState)
          .whenComplete(() {
        if (mounted) setState(() => _selected = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final a = scope.assets;
    final appState = scope.appState;
    final geo = _geo(a);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/'), tooltip: S.backToLanding),
        title: const Text(S.yourMap),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final lv = appState.level ?? demoLevel;
          final card = LevelCardData.of(a, lv);
          final expanded = MediaQuery.sizeOf(context).width >= MapScreen.expandedBreakpoint;
          final selectedRegion = _selected == null ? null : a.byCode[_selected!];

          final mapColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _controls(context, a, lv),
              _MapBox(
                child: ChoroplethMap(
                  geometry: geo,
                  userLevel: lv,
                  show89: _show89,
                  selectedCode: _selected,
                  onSelect: (code) => _open(context, code, a, lv),
                ),
              ),
              const _Legend(),
            ],
          );

          final page = ListView(
            children: [
              _LevelPicker(level: lv, onChanged: (n) => appState.setLevel(n)),
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _LevelCard(data: card)),
              if (expanded)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: mapColumn),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
                        child: _SidePanel(
                          child: selectedRegion == null
                              ? Text(S.pickRegionHint, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant))
                              : RegionSheet(
                                  key: ValueKey('panel-${selectedRegion.code}'),
                                  region: selectedRegion,
                                  userLevel: lv,
                                  asOf: a.meta.asOf,
                                  appState: appState,
                                  showHandle: false,
                                ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                mapColumn,
              SourceFooter(asOf: a.meta.asOf),
            ],
          );
          return page;
        },
      ),
    );
  }

  Widget _controls(BuildContext context, MalgilAssets a, int lv) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownMenu<RegionOption>(
            key: const Key('sido-menu'),
            width: 176,
            hintText: S.provinceHint,
            enableSearch: false,
            requestFocusOnTap: false,
            inputDecorationTheme: _menuDecoration,
            onSelected: _onSido,
            dropdownMenuEntries: [for (final o in _sidos) DropdownMenuEntry(value: o, label: o.name)],
          ),
          DropdownMenu<String>(
            key: const Key('sgg-menu'),
            width: 176,
            hintText: S.districtHint,
            enableSearch: false,
            requestFocusOnTap: false,
            controller: _sggCtl,
            inputDecorationTheme: _menuDecoration,
            onSelected: (code) => _onSgg(context, code, a, lv),
            dropdownMenuEntries: [for (final o in _sggs) DropdownMenuEntry(value: o.code, label: o.name)],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(key: const Key('show89'), value: _show89, onChanged: (v) => setState(() => _show89 = v)),
              const SizedBox(width: 6),
              Text(S.toggle89, style: MalgilType.labelMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  static const InputDecorationTheme _menuDecoration = InputDecorationTheme(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    constraints: BoxConstraints(maxHeight: 40),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(MalgilShape.cornerSmall)),
      borderSide: BorderSide(color: MalgilColors.outline),
    ),
  );
}

/// 급수 분할 버튼(Lv1~2 · Lv3 · Lv4 · Lv5) + TOPIK 라벨
class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.level, required this.onChanged});
  final int level;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<int>(
              key: const Key('level-seg'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final n in const [2, 3, 4, 5]) ButtonSegment(value: n, label: Text(lvLabel[n]!)),
              ],
              selected: {level},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
            Text(S.topikOf[level] ?? '', style: MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant)),
          ],
        ),
      );
}

/// 레벨 카드 (Card.elevated · .level-card)
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.data});
  final LevelCardData data;

  @override
  Widget build(BuildContext context) {
    final muted = MalgilColors.onSurfaceVariant;
    final big = MalgilType.headlineSmall.copyWith(fontSize: 28, height: 36 / 28, color: MalgilColors.onSurface);
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final names = data.nextNames.join(' · ') + (data.nextMore ? ' …' : '');
    return Card(
      key: const Key('level-card'),
      elevation: 1,
      color: MalgilColors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lvLabel[data.level]} · ${S.topikOf[data.level]}', style: MalgilType.labelMedium.copyWith(color: muted)),
            Text.rich(
              key: const Key('open-now'),
              TextSpan(children: [
                const TextSpan(text: S.openNow),
                TextSpan(text: '${data.open}', style: bold),
                TextSpan(text: S.ofRegions(data.total), style: MalgilType.titleMedium.copyWith(color: muted)),
              ]),
              style: big,
            ),
            const SizedBox(height: 4),
            Text.rich(
              key: const Key('open-89'),
              TextSpan(children: [
                const TextSpan(text: S.depopPrefix),
                TextSpan(text: '${data.open89}', style: bold),
                TextSpan(text: S.depopSuffix(data.total89)),
              ]),
              style: MalgilType.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (data.nextLevel == null)
              Text(S.everyRegionOpen, key: const Key('next-level'), style: MalgilType.bodyMedium.copyWith(color: muted))
            else
              Text.rich(
                key: const Key('next-level'),
                TextSpan(children: [
                  TextSpan(text: S.atNextLevel(lvLabel[data.nextLevel!]!)),
                  TextSpan(text: S.plusRegions(data.nextDelta), style: bold),
                  const TextSpan(text: S.regionsDash),
                  TextSpan(text: names),
                ]),
                style: MalgilType.bodyMedium.copyWith(color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// 지도 상자 — viewBox 비율(1000:1300) 유지, 최대 높이 720
class _MapBox extends StatelessWidget {
  const _MapBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = (w * 1.3).clamp(240.0, 720.0);
          return SizedBox(width: w, height: h, child: ClipRect(child: child));
        },
      );
}

/// 우측 패널 (body.desktop .sheet) — surface-container-low · 왼쪽 위 모서리 16
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: const BoxDecoration(
          color: MalgilColors.surfaceContainerLow,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(MalgilShape.cornerLarge)),
        ),
        child: child,
      );
}

/// 범례 — m3.css .legend 문구 그대로
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant, letterSpacing: 0);
    // 긴 항목(Any level …)은 줄바꿈되도록 Text.rich + WidgetSpan (Row 는 Wrap 안에서 넘친다)
    Widget item(LegendSwatchKind kind, String text) => Text.rich(
          TextSpan(children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: CustomPaint(size: const Size(14, 14), painter: LegendSwatchPainter(kind)),
              ),
            ),
            TextSpan(text: text),
          ]),
          style: style,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              item(LegendSwatchKind.lv3, S.chipLv3),
              item(LegendSwatchKind.lv4, S.chipLv4),
              item(LegendSwatchKind.lv5, S.chipLv5),
              item(LegendSwatchKind.lv12, S.legendAnyLevel),
              item(LegendSwatchKind.locked, S.legendLocked),
              item(LegendSwatchKind.is89, S.legend89),
              item(LegendSwatchKind.hold, S.legendHold),
              item(LegendSwatchKind.excluded, S.legendExcluded),
            ],
          ),
          const SizedBox(height: 8),
          Text(S.legendNote, style: style),
        ],
      ),
    );
  }
}

enum LegendSwatchKind { lv3, lv4, lv5, lv12, locked, is89, hold, excluded }

/// 14×14 범례 견본 (m3.css .legend .sw.*)
class LegendSwatchPainter extends CustomPainter {
  const LegendSwatchPainter(this.kind);
  final LegendSwatchKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(3));
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x1F000000);
    switch (kind) {
      case LegendSwatchKind.lv3:
        fill.color = MalgilColors.mapLv3;
      case LegendSwatchKind.lv4:
        fill.color = MalgilColors.mapLv4;
      case LegendSwatchKind.lv5:
        fill.color = MalgilColors.mapLv5;
      case LegendSwatchKind.lv12:
        fill.color = MalgilColors.mapLv12;
      case LegendSwatchKind.locked:
        fill.color = MalgilColors.mapLockedFill;
      case LegendSwatchKind.is89:
        fill.color = Colors.white;
        border
          ..color = MalgilColors.map89Border
          ..strokeWidth = 2;
      case LegendSwatchKind.hold:
        fill.color = MalgilColors.mapHold;
        border.color = MalgilColors.mapLockedInk;
      case LegendSwatchKind.excluded:
        fill.color = MalgilColors.mapExcluded;
        border.color = MalgilColors.mapLockedInk;
    }
    canvas.drawRRect(rr, fill);
    if (kind == LegendSwatchKind.locked) {
      canvas.save();
      canvas.clipRRect(rr);
      final ink = Paint()
        ..color = MalgilColors.mapLockedInk
        ..strokeWidth = 1;
      for (var x = -size.height; x <= size.width; x += 4) {
        canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), ink);
      }
      canvas.restore();
    }
    if (kind == LegendSwatchKind.hold || kind == LegendSwatchKind.excluded) {
      final pattern = kind == LegendSwatchKind.hold ? const [3.0, 2.0] : const [1.0, 2.0];
      canvas.drawPath(ChoroplethPainter.dashPath(Path()..addRRect(rr), pattern), border);
    } else {
      canvas.drawRRect(rr, border);
    }
  }

  @override
  bool shouldRepaint(LegendSwatchPainter old) => old.kind != kind;
}
