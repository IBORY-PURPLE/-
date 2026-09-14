// ① 자산 파싱 ② stateOf/isOpen ③ 지역 행 재계산(mockup.js summary 규칙) == 자산 요약 (급수 2~5)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/data/assets.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());

Region _r(String lv, {bool is89 = false, String? parent, String code = '00000'}) => Region(
      code: code,
      sido: '시도',
      nm: '이름',
      gubun: '군',
      lv: lv,
      reasonKo: '',
      reasonEn: '',
      share: 1.0,
      pb: 50,
      kor: 30,
      e65: 30,
      pop: 1000,
      is89: is89,
      months: 12,
      parent: parent,
    );

void main() {
  late MalgilAssets a;
  setUpAll(() => a = _load());

  group('① 자산 파싱', () {
    test('지역 269 · 89곳 89 · 기초 230 · 경계 256', () {
      expect(a.regions.length, 269);
      expect(a.regions.where((r) => r.is89).length, 89);
      expect(a.baseRegions.length, 230);
      expect(a.boundaries.length, 256);
    });
    test('요약 키 존재 · 메타 산출일 · viewBox', () {
      expect(a.summary.baseCount, 230);
      expect(a.summary.count89, 89);
      expect(a.summary.byLevel.keys, containsAll(['Lv1~2', 'Lv3', 'Lv4', 'Lv5', '제외', '보류']));
      expect(a.summary.openByUser.length, 4);
      expect(a.meta.asOf, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(a.meta.viewBox, '0 0 1000 1300');
      expect(a.meta.sourceNotice, contains('ⓒ한국관광공사'));
      expect(a.meta.counts['인구감소지역수'], 89);
    });
    test('지역 행 필드 전부 (종로구 · 제물포구 보류 · 장안구 일반구)', () {
      final j = a.byCode['11110']!;
      expect(j.sido, '서울특별시');
      expect(j.nm, '종로구');
      expect(j.gubun, '자치구');
      expect(j.lv, 'Lv1~2');
      expect(j.reasonEn, isNotEmpty);
      expect(j.share, closeTo(7.602, 1e-6));
      expect(j.pb, 98.2);
      expect(j.kor, 532);
      expect(j.e65, 23.1);
      expect(j.pop, 135935);
      expect(j.is89, false);
      expect(j.months, 12);
      expect(j.parent, isNull);
      expect(j.isBase, true);
      expect(j.foreignPer1000, 76);

      final hold = a.byCode['28125']!;
      expect(hold.lv, '보류');
      expect(hold.pb, isNull);
      expect(hold.months, 1);

      final gu = a.byCode['41111']!;
      expect(gu.parent, '41110');
      expect(gu.isBase, false);
      expect(a.sourceRegionFor('41111')!.code, '41110');
    });
    test('경계 좌표 정수→double · viewBox 안', () {
      for (final rings in a.boundaries.values) {
        for (final ring in rings) {
          expect(ring, isNotEmpty);
          for (final p in ring) {
            expect(p.dx, inInclusiveRange(0, 1000));
            expect(p.dy, inInclusiveRange(0, 1300));
          }
        }
      }
    });
    test('하위호환 — 데이터 키 없이 최상위에 섹션이 있어도 파싱', () {
      final flat = MalgilAssets.fromJson({
        '메타': {'산출일': '2026-09-14', 'viewBox': '0 0 1000 1300'},
        '요약': {'기초지자체': 1, '인구감소지역': 0, '급수별곳수': {}, '사용자급수별누적열린곳': []},
        '지역': [
          {'code': '12730', 'sido': 's', 'nm': 'n', '구분': '군', 'lv': 'Lv5', 'is89': true, 'months': 12, 'parent': null},
        ],
        '경계': {'12730': [[[1, 2], [3, 4], [5, 6]]]},
      });
      expect(flat.regions.single.code, '12730');
      expect(flat.boundaries['12730']!.single.length, 3);
      expect(flat.meta.asOf, '2026-09-14');
    });
  });

  group('② stateOf / isOpen (mockup.js 규칙)', () {
    test('보류·제외·Lv1~2 는 급수 무관', () {
      for (final lv in [2, 3, 4, 5]) {
        expect(stateOf(_r('보류'), lv), RegionState.hold);
        expect(stateOf(_r('제외'), lv), RegionState.excluded);
        expect(stateOf(_r('Lv1~2'), lv), RegionState.lv12);
        expect(isOpen(_r('Lv1~2'), lv), true);
        expect(isOpen(_r('보류'), lv), false);
        expect(isOpen(_r('제외'), lv), false);
      }
    });
    test('내 급수 이하 = lvN · 초과 = locked', () {
      expect(stateOf(_r('Lv3'), 2), RegionState.locked);
      expect(stateOf(_r('Lv3'), 3), RegionState.lv3);
      expect(stateOf(_r('Lv4'), 3), RegionState.locked);
      expect(stateOf(_r('Lv4'), 4), RegionState.lv4);
      expect(stateOf(_r('Lv5'), 4), RegionState.locked);
      expect(stateOf(_r('Lv5'), 5), RegionState.lv5);
      expect(stateOf(_r('Lv3'), 5), RegionState.lv3);
      expect(isOpen(_r('Lv5'), 4), false);
      expect(isOpen(_r('Lv5'), 5), true);
    });
    test('알 수 없는 lv 문자열은 excluded', () {
      expect(stateOf(_r('Lv9'), 5), RegionState.excluded);
    });
  });

  group('③ 지역 행 재계산 == 자산 요약', () {
    test('급수별곳수 (전체 · 89곳) — 기초지자체 기준', () {
      final base = a.baseRegions;
      for (final e in a.summary.byLevel.entries) {
        final rows = base.where((r) => r.lv == e.key);
        expect(rows.length, e.value.total, reason: '${e.key} 전체');
        expect(rows.where((r) => r.is89).length, e.value.of89, reason: '${e.key} 89곳');
      }
    });
    test('사용자급수별누적열린곳 — 급수 2~5 전부', () {
      for (final lv in [2, 3, 4, 5]) {
        final row = a.summary.openFor(lv);
        expect(row, isNotNull, reason: 'Lv$lv 요약 행');
        final c = summaryOf(a, lv);
        expect(c.open, row!.total, reason: 'Lv$lv 전체 열린 곳');
        expect(c.open89, row.of89, reason: 'Lv$lv 89곳 열린 곳');
        expect(c.total89, a.summary.count89);
        expect(c.total, a.summary.baseCount - a.summary.byLevel['보류']!.total - a.summary.byLevel['제외']!.total);
      }
    });
    test('다음 급수에 새로 열리는 곳 = 요약 누적 차이', () {
      for (final lv in [2, 3, 4]) {
        final c = summaryOf(a, lv);
        expect(c.nextLv, lv + 1);
        expect(c.next.length, a.summary.openFor(lv + 1)!.total - a.summary.openFor(lv)!.total);
      }
      expect(summaryOf(a, 5).nextLv, isNull);
      expect(summaryOf(a, 5).next, isEmpty);
    });
  });
}
