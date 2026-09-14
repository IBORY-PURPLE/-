// B8 ⑥ MalbeotSection — 세션 노출은 지역 급수(Lv1~2·Lv3 → S2 · Lv4·Lv5 → S2+S1 · 보류·미상 → 기본 카드) ·
//   급수 게이트(사용자 급수 < 세션 급수 → onPressed null + 「Opens at LvN」) · 관심 토글 → AppState.interests 저장·해제 ·
//   고지문 한국어 원문 · 금지어·백분율·가격·더미 날짜 없음(P-O01)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/state/app_state.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/level_chip.dart';
import 'package:malgil/widgets/malbeot_section.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());

Widget _wrap(Widget child) => MaterialApp(
      theme: malgilTheme(),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    );

Widget _section(Region? r, int userLevel, AppState s, {bool compact = false}) =>
    _wrap(MalbeotSection(region: r, userLevel: userLevel, appState: s, compact: compact, onOpenKctg: () {}));

String _allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');
FilledButton _btn(WidgetTester t, String id) => t.widget<FilledButton>(find.byKey(Key('interest-$id')));

void _expectClean(String all) {
  for (final banned in ['갈 수 없', "can't go", 'cannot go', 'Lv0', 'Lv6', 'legal criteria', '₩', 'KRW']) {
    expect(all.contains(banned), false, reason: '금지어 「$banned」');
  }
  expect(all.contains(RegExp(r'\d+(\.\d+)?\s*%')), false, reason: '백분율 표기 금지');
  expect(all.contains(RegExp(r'\b(won|fees?|seats?)\b', caseSensitive: false)), false, reason: '가격·참가비·좌석 표기 금지');
  expect(all.contains(RegExp(r'\d+\s*원')), false, reason: '원화 금액 금지');
  expect(all.contains(RegExp(r'\d{4}-\d{2}-\d{2}')), false, reason: '더미 날짜·슬롯 금지 (P-O01)');
}

void main() {
  late MalgilAssets a;
  late Region lv12, lv3, lv4, lv5, hold;
  setUpAll(() {
    a = _load();
    lv12 = a.byCode['11110']!; // 종로구
    lv3 = a.byCode['27200']!; // 대구 남구
    lv5 = a.byCode['12730']!; // 구례군
    hold = a.byCode['28125']!; // 제물포구 (보류)
    lv4 = a.baseRegions.firstWhere((r) => r.lv == 'Lv4');
  });

  test('forRegion — 지역 급수별 세션 목록', () {
    expect(lv12.lv, 'Lv1~2');
    expect(lv3.lv, 'Lv3');
    expect(lv4.lv, 'Lv4');
    expect(lv5.lv, 'Lv5');
    expect(hold.lv, lvHold);
    expect(MalbeotSession.forRegion(lv12).map((s) => s.id), ['s2']);
    expect(MalbeotSession.forRegion(lv3).map((s) => s.id), ['s2']);
    expect(MalbeotSession.forRegion(lv4).map((s) => s.id), ['s2', 's1']);
    expect(MalbeotSession.forRegion(lv5).map((s) => s.id), ['s2', 's1']);
    expect(MalbeotSession.forRegion(hold), isEmpty);
    expect(MalbeotSession.forRegion(null), isEmpty);
    expect(MalbeotSession.s2.level, 3);
    expect(MalbeotSession.s1.level, 4);
  });

  testWidgets('사용자 Lv2 · 지역 Lv5 → S2·S1 둘 다 보이고 버튼은 실제 비활성(onPressed null) + Opens at Lv3 / Lv4', (t) async {
    await t.pumpWidget(_section(lv5, 2, AppState()));
    await t.pumpAndSettle();
    expect(find.text(S.localCompanion), findsOneWidget);
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsOneWidget);
    expect(find.text(S.sessionS2Title), findsOneWidget);
    expect(find.text(S.sessionS1Title), findsOneWidget);
    expect(_btn(t, 's2').onPressed, isNull);
    expect(_btn(t, 's1').onPressed, isNull);
    expect(find.text(S.sessionOpensAt('Lv3')), findsOneWidget);
    expect(find.text(S.sessionOpensAt('Lv4')), findsOneWidget);
    expect(find.text(S.interestCta), findsNWidgets(2));
    expect(find.text(S.sessionRecruiting), findsNWidgets(2));
    expect(find.text(S.sessionMax5), findsNWidgets(2));
    // 세션 급수 칩 — S2 Lv3 · S1 Lv4
    expect(t.widgetList<LevelChip>(find.byType(LevelChip)).map((c) => c.kind), [LevelChipKind.lv3, LevelChipKind.lv4]);
    // 탭해도 아무 일 없음 (실제 비활성)
    await t.tap(find.byKey(const Key('interest-s2')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text(S.interestNoted), findsNothing);
  });

  testWidgets('사용자 Lv3 → S2 활성 · S1 비활성(Opens at Lv4 만)', (t) async {
    await t.pumpWidget(_section(lv5, 3, AppState()));
    await t.pumpAndSettle();
    expect(_btn(t, 's2').onPressed, isNotNull);
    expect(_btn(t, 's1').onPressed, isNull);
    expect(find.byKey(const Key('gate-s2')), findsNothing);
    expect(find.text(S.sessionOpensAt('Lv4')), findsOneWidget);
  });

  testWidgets('사용자 Lv4 → 둘 다 활성 · 토글 → interests 저장 · 문구 전환 · 다시 누르면 해제', (t) async {
    final s = AppState();
    await t.pumpWidget(_section(lv4, 4, s));
    await t.pumpAndSettle();
    expect(_btn(t, 's2').onPressed, isNotNull);
    expect(_btn(t, 's1').onPressed, isNotNull);
    expect(find.textContaining('Opens at'), findsNothing);
    expect(s.interests, isEmpty);

    await t.tap(find.byKey(const Key('interest-s2')));
    await t.pumpAndSettle();
    expect(s.interests, {lv4.code: ['s2']});
    expect(find.text(S.interestNoted), findsOneWidget);
    expect(find.text(S.interestCta), findsOneWidget); // S1 은 아직

    await t.tap(find.byKey(const Key('interest-s1')));
    await t.pumpAndSettle();
    expect(s.interests, {lv4.code: ['s2', 's1']});
    expect(find.text(S.interestNoted), findsNWidgets(2));

    await t.tap(find.byKey(const Key('interest-s2'))); // 해제
    await t.pumpAndSettle();
    expect(s.interests, {lv4.code: ['s1']});
    expect(find.text(S.interestNoted), findsOneWidget);
    expect(find.text(S.interestCta), findsOneWidget);

    await t.tap(find.byKey(const Key('interest-s1')));
    await t.pumpAndSettle();
    expect(s.interests, isEmpty); // 빈 지역은 키 제거
    expect(find.text(S.interestNoted), findsNothing);
  });

  testWidgets('지역 Lv3 · Lv1~2 → S2 만 (S1 카드 없음)', (t) async {
    await t.pumpWidget(_section(lv3, 5, AppState()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsNothing);
    expect(find.text(S.sessionS1Title), findsNothing);

    await t.pumpWidget(_section(lv12, 2, AppState()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsNothing);
    expect(_btn(t, 's2').onPressed, isNull); // 사용자 Lv2 < S2 Lv3
  });

  testWidgets('보류 지역 · 급수 미상(null) → 기본 카드만 (세션·고지문 없음 · kctg 링크 유지)', (t) async {
    await t.pumpWidget(_section(hold, 5, AppState()));
    await t.pumpAndSettle();
    expect(find.text(S.localCompanion), findsOneWidget);
    expect(find.text(S.localCompanionBody), findsOneWidget);
    expect(find.byKey(const Key('open-kctg')), findsOneWidget);
    expect(find.text(S.openKctg), findsOneWidget);
    expect(find.byKey(const Key('session-s2')), findsNothing);
    expect(find.byKey(const Key('session-s1')), findsNothing);
    expect(find.byKey(const Key('malbeot-notice')), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    await t.pumpWidget(_section(null, 5, AppState(), compact: true));
    await t.pumpAndSettle();
    expect(find.text(S.localCompanionBodyLong), findsOneWidget);
    expect(find.text(S.licensedInterpreter), findsOneWidget);
    expect(find.byKey(const Key('session-s2')), findsNothing);
  });

  testWidgets('고지문(한국어 원문 + Free pilot) · compact 는 설명 줄만 생략(정원 「Max 5」는 유지) · 금지어·백분율·가격·더미 날짜 없음', (t) async {
    await t.pumpWidget(_section(lv5, 5, AppState()));
    await t.pumpAndSettle();
    expect(find.textContaining(S.malbeotNoticeKo), findsOneWidget);
    expect(find.textContaining(S.malbeotNoticeEn), findsOneWidget);
    expect(find.text(S.sessionS2Body), findsOneWidget);
    expect(find.text(S.sessionMax5), findsNWidgets(2));
    _expectClean(_allText(t));

    await t.pumpWidget(_section(lv5, 5, AppState(), compact: true));
    await t.pumpAndSettle();
    expect(find.textContaining(S.malbeotNoticeKo), findsOneWidget);
    expect(find.text(S.licensedInterpreter), findsOneWidget);
    expect(find.text(S.sessionS2Body), findsNothing);
    expect(find.text(S.sessionMax5), findsNWidgets(2)); // PRD F7 정원 표기는 장소 상세(compact)에서도 필수
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsOneWidget);
    expect(find.text(S.sessionRecruiting), findsNWidgets(2));
    _expectClean(_allText(t));
  });
}
