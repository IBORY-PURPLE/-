// 급수 지도 — Docs/mockup/mockup.js renderMap · m3.css svg.choropleth 와 1:1.
//  - 자산 경계(viewBox 0 0 1000 1300 정수 좌표)를 ui.Path 로 한 번만 만들어 code 별로 캐시한다 (ChoroplethGeometry)
//  - 색 = stateOf(parent 행) : 일반구 경계는 parent 시의 급수로 칠한다 (mockup.js src)
//  - locked 는 흰 바탕 + 45° 빗금(clip 후 선 그리기 — 셰이더 없이) · excluded 점선 · hold 파선 테두리
//  - 탭 히트테스트 = 화면 좌표를 viewBox 로 역변환한 뒤 Path.contains
//  - 핀치·휠 줌은 InteractiveViewer(1~4배). 배율 1에서는 세로 드래그를 목록 스크롤에 양보한다
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/assets.dart';
import '../theme/tokens.dart';

/// 경계 Path 캐시 + viewBox ↔ 위젯 좌표 변환 + 히트테스트. 자산당 1개 만들어 재사용한다.
class ChoroplethGeometry {
  ChoroplethGeometry(this.assets)
      : viewW = assets.meta.viewW,
        viewH = assets.meta.viewH,
        paths = {
          for (final e in assets.boundaries.entries) e.key: _buildPath(e.value),
        };

  final MalgilAssets assets;
  final double viewW;
  final double viewH;

  /// 경계 code → viewBox 좌표계 Path (일반구 단위 — 색·히트는 parent 로 접는다)
  final Map<String, ui.Path> paths;

  /// code → 그 경계에 칠할 출처 행 (일반구면 parent 시 행)
  late final Map<String, Region?> sources = {for (final code in paths.keys) code: assets.sourceRegionFor(code)};

  static ui.Path _buildPath(List<List<Offset>> rings) {
    final p = ui.Path();
    for (final ring in rings) {
      if (ring.isEmpty) continue;
      p.moveTo(ring.first.dx, ring.first.dy);
      for (var i = 1; i < ring.length; i++) {
        p.lineTo(ring[i].dx, ring[i].dy);
      }
      p.close();
    }
    return p;
  }

  /// viewBox 를 [size] 에 비율 유지로 맞추는 배율 · 좌상단 오프셋(가운데 정렬)
  (double, Offset) fit(Size size) {
    final s = (size.width / viewW < size.height / viewH) ? size.width / viewW : size.height / viewH;
    final off = Offset((size.width - viewW * s) / 2, (size.height - viewH * s) / 2);
    return (s, off);
  }

  /// 위젯 로컬 좌표 → viewBox 좌표
  Offset toView(Offset local, Size size) {
    final (s, off) = fit(size);
    return Offset((local.dx - off.dx) / s, (local.dy - off.dy) / s);
  }

  /// viewBox 좌표가 어느 경계 안인지 → 출처 행의 code(일반구면 parent). 없으면 null.
  String? hitTestView(Offset view) {
    for (final e in paths.entries) {
      if (e.value.contains(view)) return sources[e.key]?.code ?? e.key;
    }
    return null;
  }

  /// 위젯 로컬 좌표 히트테스트 (역변환 후 [hitTestView])
  String? hitTest(Offset local, Size size) => hitTestView(toView(local, size));
}

/// 상태별 칠 규칙 (m3.css svg.choropleth path.*) — 테스트 대조 대상
class RegionPaintStyle {
  const RegionPaintStyle({
    required this.fill,
    required this.hatched,
    required this.border,
    required this.borderWidth,
    this.dash,
  });

  final Color fill;
  final bool hatched; // locked — 흰 바탕 + 45° 빗금
  final Color border;
  final double borderWidth; // viewBox 단위 (SVG stroke-width 와 같음)
  final List<double>? dash; // stroke-dasharray. null = 실선

  static RegionPaintStyle of(RegionState st, {bool is89 = false, bool show89 = true, bool selected = false}) {
    var fill = MalgilColors.mapLockedFill;
    var hatched = false;
    var border = MalgilColors.mapBorder;
    var width = 0.8;
    List<double>? dash;
    switch (st) {
      case RegionState.lv12:
        fill = MalgilColors.mapLv12;
      case RegionState.lv3:
        fill = MalgilColors.mapLv3;
      case RegionState.lv4:
        fill = MalgilColors.mapLv4;
      case RegionState.lv5:
        fill = MalgilColors.mapLv5;
      case RegionState.locked:
        fill = MalgilColors.mapLockedFill;
        hatched = true;
      case RegionState.excluded:
        fill = MalgilColors.mapExcluded;
        border = MalgilColors.mapLockedInk;
        dash = const [1, 2];
      case RegionState.hold:
        fill = MalgilColors.mapHold;
        border = MalgilColors.mapLockedInk;
        dash = const [4, 3];
    }
    if (is89 && show89) {
      border = MalgilColors.map89Border;
      width = st == RegionState.locked ? 1.2 : 1.6;
    }
    if (selected) {
      border = MalgilColors.error;
      width = 2.4;
    }
    return RegionPaintStyle(fill: fill, hatched: hatched, border: border, borderWidth: width, dash: dash);
  }
}

class ChoroplethPainter extends CustomPainter {
  ChoroplethPainter({
    required this.geometry,
    required this.userLevel,
    this.show89 = true,
    this.selectedCode,
  });

  final ChoroplethGeometry geometry;
  final int userLevel;
  final bool show89;
  final String? selectedCode;

  static const double hatchStep = 6; // svg pattern width 6 (userSpaceOnUse)
  static const double hatchWidth = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final (s, off) = geometry.fit(size);
    canvas.save();
    canvas.translate(off.dx, off.dy);
    canvas.scale(s, s);

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final hatchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hatchWidth
      ..color = MalgilColors.mapLockedInk;

    ui.Path? selectedPath;
    RegionPaintStyle? selectedStyle;

    for (final e in geometry.paths.entries) {
      final src = geometry.sources[e.key];
      if (src == null) continue;
      final st = stateOf(src, userLevel);
      final selected = selectedCode != null && selectedCode == src.code;
      final style = RegionPaintStyle.of(st, is89: src.is89, show89: show89, selected: selected);
      final path = e.value;

      fillPaint.color = style.fill;
      canvas.drawPath(path, fillPaint);
      if (style.hatched) _hatch(canvas, path, hatchPaint);

      if (selected) {
        selectedPath = path;
        selectedStyle = style;
        continue; // 선택 테두리는 맨 위에
      }
      _stroke(canvas, path, style, strokePaint);
    }
    if (selectedPath != null && selectedStyle != null) _stroke(canvas, selectedPath, selectedStyle, strokePaint);
    canvas.restore();
  }

  void _stroke(Canvas canvas, ui.Path path, RegionPaintStyle style, Paint paint) {
    paint
      ..color = style.border
      ..strokeWidth = style.borderWidth;
    final dash = style.dash;
    canvas.drawPath(dash == null ? path : dashPath(path, dash), paint);
  }

  /// 45° 빗금: 경계로 clip 한 뒤 bounds 를 덮는 대각선을 [hatchStep] 간격으로 긋는다
  void _hatch(Canvas canvas, ui.Path path, Paint paint) {
    final b = path.getBounds();
    canvas.save();
    canvas.clipPath(path);
    final h = b.height;
    for (var x = b.left - h; x <= b.right; x += hatchStep) {
      canvas.drawLine(Offset(x, b.top), Offset(x + h, b.bottom), paint);
    }
    canvas.restore();
  }

  /// stroke-dasharray 흉내 — PathMetrics 로 잘라 새 Path 를 만든다
  static ui.Path dashPath(ui.Path source, List<double> pattern) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      var dist = 0.0;
      var i = 0;
      while (dist < metric.length) {
        final len = pattern[i % pattern.length];
        if (i.isEven) out.addPath(metric.extractPath(dist, dist + len), Offset.zero);
        dist += len;
        i++;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(ChoroplethPainter old) =>
      old.geometry != geometry || old.userLevel != userLevel || old.show89 != show89 || old.selectedCode != selectedCode;
}

/// 지도 위젯 — CustomPaint + 탭 히트테스트 + InteractiveViewer 줌
class ChoroplethMap extends StatefulWidget {
  const ChoroplethMap({
    super.key,
    required this.geometry,
    required this.userLevel,
    this.show89 = true,
    this.selectedCode,
    this.onSelect,
  });

  final ChoroplethGeometry geometry;
  final int userLevel;
  final bool show89;
  final String? selectedCode;
  final ValueChanged<String>? onSelect; // 출처 행 code (일반구면 parent)

  @override
  State<ChoroplethMap> createState() => _ChoroplethMapState();
}

class _ChoroplethMapState extends State<ChoroplethMap> {
  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
  }

  void _onTransform() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MalgilColors.surfaceContainerLow,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 4,
        panEnabled: _zoomed, // 배율 1이면 세로 드래그 = 페이지 스크롤
        // 마우스 휠은 페이지 스크롤에 양보한다 — InteractiveViewer 는 휠(PointerScrollEvent)을 자체 Listener 로
        // 받아 exp(-dy/scaleFactor) 만큼 확대하므로, 목록 안에서 휠을 올리면 지도가 저절로 4배까지 커진다.
        // scaleFactor 무한대 → 휠 배율 1.0(무변화). 핀치·Ctrl+휠(PointerScaleEvent)은 그대로 1~4배 줌.
        scaleFactor: double.infinity,
        child: LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final code = widget.geometry.hitTest(d.localPosition, c.biggest);
              if (code != null) widget.onSelect?.call(code);
            },
            child: CustomPaint(
              size: c.biggest,
              painter: ChoroplethPainter(
                geometry: widget.geometry,
                userLevel: widget.userLevel,
                show89: widget.show89,
                selectedCode: widget.selectedCode,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
