// MapScreen 위젯 — compact(500) 에서 레벨 카드 141/225 · 30/89 · 급수 전환 · ldong 실패 시 자산 폴백 (조용히)
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malgil/app.dart';
import 'package:malgil/data/api.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/screens/map_screen.dart';
import 'package:malgil/state/app_state.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/choropleth_map.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());

Widget _app(MalgilAssets a, AppState s, ApiClient api) => AppScope(
      assets: a,
      appState: s,
      child: MaterialApp(theme: malgilTheme(), home: MapScreen(apiClient: api)),
    );

String _plain(WidgetTester t, Key k) => t.widget<Text>(find.byKey(k)).textSpan!.toPlainText();

void main() {
  late MalgilAssets a;
  setUpAll(() => a = _load());

  testWidgets('Lv3 · 폭 500 — Open now 141 of 225 · 30 of 89 · At Lv4: +55', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiClient(client: MockClient((req) async => http.Response('{"ok":false,"kind":"upstream","message":"x"}', 502)));
    final s = AppState(level: 3);
    await t.pumpWidget(_app(a, s, api));
    await t.pumpAndSettle();

    expect(find.text(S.yourMap), findsOneWidget);
    expect(_plain(t, const Key('open-now')), 'Open now 141 of 225 regions');
    expect(_plain(t, const Key('open-89')), 'Depopulation areas: 30 of 89 open');
    expect(_plain(t, const Key('next-level')), startsWith('At Lv4: +55 regions — '));
    expect(find.text(S.legendNote), findsOneWidget);
    expect(find.text(S.toggle89), findsOneWidget);
    // 실패해도 에러 화면 없음 — 시도 드롭다운은 자산 폴백 16개
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.text(S.quotaTitle), findsNothing);

    // 급수 전환 → AppState + 카드 갱신
    await t.tap(find.text('Lv5'));
    await t.pumpAndSettle();
    expect(s.level, 5);
    expect(_plain(t, const Key('open-now')), 'Open now 225 of 225 regions');
    expect(find.text(S.everyRegionOpen), findsOneWidget);
  });

  testWidgets('마우스 휠은 페이지 스크롤에 양보 — 지도 배율 1 유지', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiClient(client: MockClient((req) async => http.Response('{"ok":false,"kind":"upstream","message":"x"}', 502)));
    await t.pumpWidget(_app(a, AppState(level: 3), api));
    await t.pumpAndSettle();

    final scrollable = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, 0);
    double scale() => t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.getMaxScaleOnAxis();
    expect(scale(), 1.0);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(t.getCenter(find.byType(ChoroplethMap)));
    // 휠 내림 → 페이지가 내려간다
    await t.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await t.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(scale(), 1.0);
    // 휠 올림 → 지도가 커지지 않고 페이지가 올라간다 (수정 전에는 exp(120/200)=1.82배로 확대됐다)
    await t.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await t.pumpAndSettle();
    expect(scale(), 1.0);
    expect(scrollable.position.pixels, 0);
  });

  testWidgets('ldong 성공 — 시도 16 을 API 항목으로 채움', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var calls = 0;
    final api = ApiClient(
      client: MockClient((req) async {
        calls++;
        expect(req.url.path, endsWith('/api/ldong'));
        return http.Response(
          '{"ok":true,"totalCount":2,"count":2,"items":[{"rnum":1,"code":"11","name":"서울특별시"},{"rnum":2,"code":"12","name":"전남광주통합특별시"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await t.pumpWidget(_app(a, AppState(level: 3), api));
    await t.pumpAndSettle();
    expect(calls, 1);
    final menu = t.widget<DropdownMenu<RegionOption>>(find.byKey(const Key('sido-menu')));
    expect(menu.dropdownMenuEntries.map((e) => e.label), ['서울특별시', '전남광주통합특별시']);
  });
}
