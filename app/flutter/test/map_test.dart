// B6 · /map — ① 레벨 카드 = 자산 요약 ② 다음 급수 델타 = 누적 차이 ③ 칠 규칙 ④ 히트테스트 ⑤ ldong 옵션·폴백
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/screens/map_screen.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/choropleth_map.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());

void main() {
  late MalgilAssets a;
  late ChoroplethGeometry geo;
  setUpAll(() {
    a = _load();
    geo = ChoroplethGeometry(a);
  });

  group('① 레벨 카드 숫자 = 자산 요약', () {
    test('급수 2~5 전부 — open · open89 · total · total89', () {
      final s = a.summary;
      final countable = s.baseCount - s.byLevel['보류']!.total - s.byLevel['제외']!.total;
      for (final lv in [2, 3, 4, 5]) {
        final c = LevelCardData.of(a, lv);
        final row = s.openFor(lv)!;
        expect(c.open, row.total, reason: 'Lv$lv open');
        expect(c.open89, row.of89, reason: 'Lv$lv open89');
        expect(c.total, countable);
        expect(c.total89, s.count89);
      }
    });
    test('Lv3 (demo) = Open now 141 of 225 · 30 of 89', () {
      final c = LevelCardData.of(a, 3);
      expect(c.open, 141);
      expect(c.total, 225);
      expect(c.open89, 30);
      expect(c.total89, 89);
    });
  });

  group('② 다음 급수 델타 = 누적 차이', () {
    test('Lv2→3 · 3→4 · 4→5 · Lv5 는 없음', () {
      for (final lv in [2, 3, 4]) {
        final c = LevelCardData.of(a, lv);
        expect(c.nextLevel, lv + 1);
        expect(c.nextDelta, a.summary.openFor(lv + 1)!.total - a.summary.openFor(lv)!.total, reason: 'Lv$lv delta');
        expect(c.nextDelta, summaryOf(a, lv).next.length);
        expect(c.nextNames.length, lessThanOrEqualTo(4));
        expect(c.nextMore, summaryOf(a, lv).next.length > 4);
        // 지명은 기초 행에서 lv == 다음 급수인 순서대로
        final expected = a.baseRegions.where((r) => lvNum[r.lv] == lv + 1).map((r) => r.nm).take(4).toList();
        expect(c.nextNames, expected);
      }
      final top = LevelCardData.of(a, 5);
      expect(top.nextLevel, isNull);
      expect(top.nextDelta, 0);
      expect(top.nextNames, isEmpty);
    });
  });

  group('③ ChoroplethPainter 색 매핑', () {
    test('상태별 fill · 빗금 · 테두리', () {
      expect(RegionPaintStyle.of(RegionState.lv3).fill, MalgilColors.mapLv3);
      expect(RegionPaintStyle.of(RegionState.lv4).fill, MalgilColors.mapLv4);
      expect(RegionPaintStyle.of(RegionState.lv5).fill, MalgilColors.mapLv5);
      expect(RegionPaintStyle.of(RegionState.lv12).fill, MalgilColors.mapLv12);
      final locked = RegionPaintStyle.of(RegionState.locked);
      expect(locked.fill, MalgilColors.mapLockedFill);
      expect(locked.hatched, true);
      expect(RegionPaintStyle.of(RegionState.lv3).hatched, false);
      final ex = RegionPaintStyle.of(RegionState.excluded);
      expect(ex.fill, MalgilColors.mapExcluded);
      expect(ex.dash, [1, 2]);
      expect(ex.border, MalgilColors.mapLockedInk);
      final hold = RegionPaintStyle.of(RegionState.hold);
      expect(hold.fill, MalgilColors.mapHold);
      expect(hold.dash, [4, 3]);
    });
    test('테두리 — 기본 흰 0.8 · 89곳 1.6(잠김 1.2) · 토글 끄면 흰 · 선택 error 2.4', () {
      final plain = RegionPaintStyle.of(RegionState.lv4);
      expect(plain.border, MalgilColors.mapBorder);
      expect(plain.borderWidth, 0.8);
      final b89 = RegionPaintStyle.of(RegionState.lv5, is89: true);
      expect(b89.border, MalgilColors.map89Border);
      expect(b89.borderWidth, 1.6);
      expect(RegionPaintStyle.of(RegionState.locked, is89: true).borderWidth, 1.2);
      expect(RegionPaintStyle.of(RegionState.lv5, is89: true, show89: false).border, MalgilColors.mapBorder);
      final sel = RegionPaintStyle.of(RegionState.lv5, is89: true, selected: true);
      expect(sel.border, MalgilColors.error);
      expect(sel.borderWidth, 2.4);
    });
    test('일반구 경계는 parent 시 행으로 칠한다', () {
      expect(geo.sources['41111']!.code, '41110');
      expect(geo.sources['12730']!.code, '12730');
    });
  });

  group('④ 히트테스트', () {
    test('구례군(12730) 경계 안 점 → 12730 · 밖 점 → null', () {
      final ring = a.boundaries['12730']!.first;
      final cx = ring.map((p) => p.dx).reduce((x, y) => x + y) / ring.length;
      final cy = ring.map((p) => p.dy).reduce((x, y) => x + y) / ring.length;
      expect(geo.paths['12730']!.contains(Offset(cx, cy)), true, reason: '중심점이 경계 안');
      // viewBox 크기 그대로면 배율 1 · 오프셋 0
      expect(geo.hitTest(Offset(cx, cy), const Size(1000, 1300)), '12730');
      expect(geo.hitTest(const Offset(5, 5), const Size(1000, 1300)), isNull);
      expect(geo.hitTest(const Offset(995, 1295), const Size(1000, 1300)), isNull);
    });
    test('위젯 크기에 맞춘 배율·오프셋 역변환', () {
      final ring = a.boundaries['12730']!.first;
      final cx = ring.map((p) => p.dx).reduce((x, y) => x + y) / ring.length;
      final cy = ring.map((p) => p.dy).reduce((x, y) => x + y) / ring.length;
      const size = Size(500, 650); // 배율 0.5
      final (s, off) = geo.fit(size);
      expect(s, 0.5);
      expect(off, Offset.zero);
      expect(geo.hitTest(Offset(cx * s + off.dx, cy * s + off.dy), size), '12730');
      const wide = Size(1300, 650); // 높이가 제한 · 가로 가운데 정렬
      final (s2, off2) = geo.fit(wide);
      expect(s2, 0.5);
      expect(off2.dx, 400);
      expect(geo.hitTest(Offset(cx * s2 + off2.dx, cy * s2 + off2.dy), wide), '12730');
      expect(geo.hitTest(const Offset(10, 10), wide), isNull);
    });
    test('일반구를 탭하면 parent 시 code', () {
      final ring = a.boundaries['41111']!.first;
      final cx = ring.map((p) => p.dx).reduce((x, y) => x + y) / ring.length;
      final cy = ring.map((p) => p.dy).reduce((x, y) => x + y) / ring.length;
      final hit = geo.hitTestView(Offset(cx, cy));
      if (hit != null) expect(hit, '41110');
    });
  });

  group('⑤ 드롭다운 옵션', () {
    test('ldongCode2 응답 → 시도 2자리(세종 36110 → 36) · 시군구 regn+3자리', () {
      final sido = optionsFromLdong([
        {'rnum': 1, 'code': '11', 'name': '서울특별시'},
        {'rnum': 2, 'code': '36110', 'name': '세종특별자치시'},
      ]);
      expect(sido.map((o) => o.code), ['11', '36']);
      final sgg = optionsFromLdong([
        {'code': '730', 'name': '구례군'},
        {'code': '36110', 'name': '세종특별자치시'},
      ], regn: '12');
      expect(sgg.first.code, '12730');
      expect(sgg.last.code, '36110');
    });
    test('자산 폴백 — 시도 16 · 구례군은 전남광주통합특별시 아래', () {
      final sidos = sidoFromAssets(a);
      expect(sidos.length, 16);
      expect(sidos.map((o) => o.code).toSet().length, 16);
      final sggs = sggFromAssets(a, '전남광주통합특별시');
      expect(sggs.any((o) => o.code == '12730' && o.name == '구례군'), true);
      // 기초 행만 — 일반구(수원시 장안구)는 없음
      expect(sggFromAssets(a, '경기도').any((o) => o.code == '41111'), false);
    });
  });
}
