// ⑤ RegionSheet 위젯 — 잠긴 지역(사용자 Lv3 · 구례 Lv5) 문구 · 금지 표현 없음 · 체류 자기신고
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/state/app_state.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/region_sheet.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());

Widget _wrap(Widget child) => MaterialApp(
      theme: malgilTheme(),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    );

String _allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');

void main() {
  late MalgilAssets a;
  setUpAll(() => a = _load());

  testWidgets('잠긴 지역 — 구례군(Lv5) · 사용자 Lv3 → 「Opens at Lv5」 배너 · 89곳 배지', (t) async {
    final gurye = a.byCode['12730']!;
    final s = AppState();
    await t.pumpWidget(_wrap(RegionSheet(region: gurye, userLevel: 3, asOf: a.meta.asOf, appState: s, today: '2026-09-14', onOpenPlaces: () {}, onOpenKctg: () {})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('locked-banner')), findsOneWidget);
    expect(find.textContaining('Opens at Lv5'), findsOneWidget);
    expect(find.textContaining('you can still visit'), findsOneWidget);
    expect(find.text('구례군'), findsOneWidget);
    expect(find.text('전남광주통합특별시'), findsOneWidget);
    expect(find.text(S.badge89), findsOneWidget);
    expect(find.text('Lv5'), findsOneWidget);
    expect(find.text(gurye.reasonEn), findsOneWidget);
    expect(find.textContaining('Computed ${a.meta.asOf}'), findsOneWidget);
    expect(find.text(S.placesLive), findsOneWidget);
    expect(find.text(S.localCompanion), findsOneWidget);
    // 말벗 섹션 — 구례 Lv5 → S2 + S1 · 사용자 Lv3 → S2 활성 · S1 은 실제 비활성 + Opens at Lv4
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('interest-s1'))).onPressed, isNull);
    expect(find.text(S.sessionOpensAt('Lv4')), findsOneWidget);
    expect(find.text('${S.stayNoteKo1}\n${S.stayNoteKo2}'), findsOneWidget);

    final all = _allText(t);
    for (final banned in ['갈 수 없', "can't go", 'cannot go', 'Lv0', 'Lv6', 'legal criteria']) {
      expect(all.contains(banned), false, reason: '금지어 「$banned」');
    }
    expect(all.contains(RegExp(r'\d+(\.\d+)?\s*%')), false, reason: '백분율 표기 금지');
  });

  testWidgets('열린 지역 — 사용자 Lv5 면 배너 없음 · Lv1~2 는 「Any level」', (t) async {
    final gurye = a.byCode['12730']!;
    await t.pumpWidget(_wrap(RegionSheet(region: gurye, userLevel: 5, asOf: a.meta.asOf, appState: AppState(), onOpenPlaces: () {}, onOpenKctg: () {})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('locked-banner')), findsNothing);

    final jongno = a.byCode['11110']!;
    await t.pumpWidget(_wrap(RegionSheet(region: jongno, userLevel: 2, asOf: a.meta.asOf, appState: AppState(), onOpenPlaces: () {}, onOpenKctg: () {})));
    await t.pumpAndSettle();
    expect(find.text(S.chipAnyLevel), findsOneWidget);
    expect(find.byKey(const Key('locked-banner')), findsNothing);
    expect(find.text(S.badge89), findsNothing);
  });

  testWidgets('보류 — 제물포구 안내 문장', (t) async {
    final hold = a.byCode['28125']!;
    await t.pumpWidget(_wrap(RegionSheet(region: hold, userLevel: 3, asOf: a.meta.asOf, appState: AppState(), onOpenPlaces: () {}, onOpenKctg: () {})));
    await t.pumpAndSettle();
    expect(find.text(S.chipHold), findsOneWidget);
    expect(find.textContaining('Reorganized on 2026-07-01'), findsOneWidget);
  });

  testWidgets('체류 자기신고 — 체크하면 addVisit · 「This is your 1st stay in 구례군」', (t) async {
    final gurye = a.byCode['12730']!;
    final s = AppState();
    await t.pumpWidget(_wrap(RegionSheet(region: gurye, userLevel: 3, asOf: a.meta.asOf, appState: s, today: '2026-09-14', onOpenPlaces: () {}, onOpenKctg: () {})));
    await t.pumpAndSettle();
    expect(find.textContaining('stay in 구례군'), findsNothing);
    await t.ensureVisible(find.byKey(const Key('stayed-today')));
    await t.tap(find.byKey(const Key('stayed-today')));
    await t.pumpAndSettle();
    expect(s.visits['12730'], ['2026-09-14']);
    expect(find.text('This is your 1st stay in 구례군'), findsOneWidget);
    // 다시 탭해도 같은 날은 한 번만
    await t.tap(find.byKey(const Key('stayed-today')));
    await t.pumpAndSettle();
    expect(s.visits['12730'], ['2026-09-14']);
  });

  test('ordinal · whyText 폴백', () {
    expect(S.ordinal(1), '1st');
    expect(S.ordinal(2), '2nd');
    expect(S.ordinal(3), '3rd');
    expect(S.ordinal(4), '4th');
    expect(S.ordinal(11), '11th');
    expect(S.ordinal(12), '12th');
    expect(S.ordinal(13), '13th');
    expect(S.ordinal(21), '21st');
    expect(S.ordinal(112), '112th');
    const r = Region(code: '00000', sido: 's', nm: 'n', gubun: '군', lv: 'Lv5', reasonKo: '', reasonEn: '', share: 0.402, pb: 1, kor: 106, e65: 41.6, pop: 1, is89: true, months: 12, parent: null);
    // 폴백 표기 = 자산 근거_en 과 동일 (구례군 근거_en 원문과 같은 형태)
    expect(RegionSheet.whyText(r), '4 foreign visitors per 1,000 · county · 4 in 10 residents aged 65+ · 106 Korean-language listings');
  });
}
