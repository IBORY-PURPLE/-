// ① PlacesScreen — 픽스처(places_27200 · 2026-09-14 실응답 형태) 주입: 카드 수 = 12·14·15·39 건수 · 유형/대분류 칩 필터 ·
//    급수 배지 없음(PRD F5) · Type3 → contain · Type1 → cover · 이미지 없음 → 텍스트 히어로 · 1콜만
// ② quota → 배너 · error → Retry 배너 · 직전 성공 응답이 있으면 「Showing listings from N min ago」 + 목록 유지
//    quota 도 직전 목록 유지(회귀 #6) · rate_limited(워커 IP 제한 429)는 한도 배너가 아니라 error + Retry · 빈 items(회귀 #2) → 빈 상태
// 카드 탭 → /place/:id (push) · 상세 ← → 목록(필터 유지) · why ▸ → /map
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malgil/app.dart';
import 'package:malgil/data/api.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/screens/place_screen.dart';
import 'package:malgil/screens/places_screen.dart';
import 'package:malgil/state/app_state.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/kto_image.dart';
import 'package:malgil/widgets/level_chip.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());
String _fx(String name) => File('test/fixtures/$name').readAsStringSync();

const _json = {'content-type': 'application/json'};
http.Response _ok(String body) => http.Response(body, 200, headers: {..._json, 'x-malgil-remaining': '900', 'x-malgil-cache': 'miss'});
http.Response _quota() => http.Response(jsonEncode({'ok': false, 'kind': 'quota', 'message': 'limit'}), 429, headers: {..._json, 'x-malgil-remaining': '0'});
http.Response _upstream() => http.Response(jsonEncode({'ok': false, 'kind': 'upstream', 'message': 'x'}), 502, headers: _json);

Widget _app(MalgilAssets a, ApiClient api, {String code = '27200', AppState? state}) => AppScope(
      assets: a,
      appState: state ?? AppState(level: 3),
      child: MaterialApp(theme: malgilTheme(), home: PlacesScreen(code: code, apiClient: api)),
    );

String _allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');
String _footer(WidgetTester t) => t.widget<Text>(find.byKey(const Key('places-footer'))).data!;

/// 가로 스크롤 칩 — 보이게 한 뒤 탭
Future<void> _tapChip(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key(key)));
}

/// 카드 안의 Image.network fit (없으면 null = 텍스트 히어로)
BoxFit? _fitOf(WidgetTester t, String contentId) {
  final img = find.descendant(of: find.byKey(Key('place-$contentId')), matching: find.byType(Image));
  return img.evaluate().isEmpty ? null : t.widget<Image>(img).fit;
}

void main() {
  late MalgilAssets a;
  late String placesBody;
  setUpAll(() {
    a = _load();
    placesBody = _fx('places_27200.json');
  });

  group('filterRows · catsOf (픽스처 집계)', () {
    late List<PlaceRow> rows;
    setUpAll(() {
      final ok = ApiClient.parseResponse(200, _json, placesBody) as ApiOk;
      rows = ok.items.map(PlaceRow.fromJson).toList();
    });
    test('48행 = 12:18 · 14:4 · 15:2 · 39:24 — 38(쇼핑) 없음', () {
      expect(rows.length, 48);
      expect(filterRows(rows, type: '12').length, 18);
      expect(filterRows(rows, type: '14').length, 4);
      expect(filterRows(rows, type: '15').length, 2);
      expect(filterRows(rows, type: '39').length, 24);
      expect(rows.where((r) => r.typeId == '38'), isEmpty);
      expect(filterRows(rows, type: '39', cat: 'FD').length, 24);
      expect(filterRows(rows, type: '12', cat: 'FD'), isEmpty);
    });
    test('대분류는 등장 순 · 중복 제거', () {
      expect(catsOf(rows).toSet(), {'VE', 'NA', 'HS', 'FD', 'EV', 'EX'});
      expect(catsOf(rows).first, 'VE');
    });
    test('이미지: firstimage → firstimage2 → null · 히어로 라벨 = 대분류', () {
      final noImg = rows.firstWhere((r) => r.contentId == '133894'); // 대덕식당
      expect(noImg.image, isNull);
      expect(noImg.heroLabel, 'Food');
      expect(noImg.kindLine, 'Food · FD01');
      final r = PlaceRow.fromJson({'contentid': '1', 'contenttypeid': '12', 'firstimage': '', 'firstimage2': 'http://x/2.jpg'});
      expect(r.image, 'http://x/2.jpg');
      expect(r.heroLabel, 'Sights');
    });
  });

  testWidgets('① 픽스처 주입 — 카드 48 · 헤더 Lv3 · 급수 배지 없음 · Type3 contain · Type1 cover · 이미지 없음 텍스트 히어로 · 1콜', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 6000)); // 48장이 모두 빌드되도록
    addTearDown(() => t.binding.setSurfaceSize(null));
    var calls = 0;
    final api = ApiClient(client: MockClient((req) async {
      calls++;
      expect(req.url.path, endsWith('/api/places'));
      expect(req.url.queryParameters, {'code': '27200'}); // type 미지정 1콜
      return _ok(placesBody);
    }));
    await t.pumpWidget(_app(a, api));
    expect(find.byKey(const Key('places-list')), findsOneWidget);
    await t.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('남구'), findsOneWidget);
    expect(find.text('대구광역시'), findsOneWidget);
    expect(find.text(a.byCode['27200']!.reasonEn), findsOneWidget);
    expect(find.byType(LevelChip), findsOneWidget); // 헤더 1개뿐 — 카드에는 없다
    expect(t.widget<LevelChip>(find.byType(LevelChip)).kind, LevelChipKind.lv3);
    // Wrap 안에서도 내용 폭 — 전폭 막대 회귀(2026-09-14 브라우저 실측: 「Lv3」 칩이 x=16→484)
    expect(t.getSize(find.byType(LevelChip)).width, lessThan(100));
    expect(t.getSize(find.byType(LevelChip)).height, 24);
    expect(find.textContaining('Live · fetched '), findsOneWidget);
    expect(find.textContaining('출처: ⓒ한국관광공사'), findsOneWidget);

    expect(find.byType(PlaceCard), findsNWidgets(48));
    expect(_footer(t), startsWith('48 shown · 70 in the public list (shopping and other types not shown) · areaBasedList2 · fetched 2026-09-14 '));
    expect(find.text('노이식탁'), findsOneWidget);

    // 이미지 규칙 (회귀 #4 · #5)
    expect(_fitOf(t, '2366500'), BoxFit.contain); // 고산골 Type3
    expect(_fitOf(t, '130806'), BoxFit.cover); // 남부도서관 Type1
    expect(_fitOf(t, '133894'), isNull); // 대덕식당 — 이미지 없음
    expect(find.descendant(of: find.byKey(const Key('place-133894')), matching: find.text('Food')), findsOneWidget);
    expect(find.byType(KtoImage), findsNWidgets(48));
    expect(find.text(S.sourceCaption), findsNWidgets(38)); // 이미지 있는 38장 모두 캡션

    // 유형 칩 — 클라이언트 필터, 추가 호출 없음
    await _tapChip(t, 'type-39');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(24));
    expect(_footer(t), startsWith('24 shown · 70 in the public list'));
    await _tapChip(t, 'type-15');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(2));
    // 대분류 칩
    await _tapChip(t, 'type-all');
    await t.pumpAndSettle();
    await _tapChip(t, 'cat-HS');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(4));
    // 빈 필터 → Show all
    await _tapChip(t, 'type-39');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNothing);
    expect(find.text(S.emptyTitle), findsOneWidget);
    await t.tap(find.text(S.emptyAction));
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(48));
    expect(calls, 1);

    final all = _allText(t);
    for (final banned in ['갈 수 없', "can't go", 'cannot go', 'Lv0', 'Lv6', 'legal criteria']) {
      expect(all.contains(banned), false, reason: '금지어 「$banned」');
    }
    expect(all.contains(RegExp(r'\d+(\.\d+)?\s*%')), false, reason: '백분율 표기 금지');
  });

  testWidgets('② quota 429 → 배너 · 목록 없음 · 오류 배너 아님', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiClient(client: MockClient((_) async => _quota()));
    await t.pumpWidget(_app(a, api));
    await t.pumpAndSettle();
    expect(find.text(S.quotaTitle), findsOneWidget);
    expect(find.textContaining('1,000 calls per operation per day'), findsOneWidget);
    expect(find.textContaining('computed ${a.meta.asOf}'), findsOneWidget);
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.byType(PlaceCard), findsNothing);
    expect(find.byKey(const Key('type-all')), findsNothing);
  });

  testWidgets('② 성공 뒤 quota 429 → 한도 배너 + 직전 목록 유지 · Retry 없음 · 칩 전환은 추가 호출 없음 (회귀 #6)', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 6000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var calls = 0;
    final api = ApiClient(client: MockClient((_) async {
      calls++;
      return calls == 1 ? _ok(placesBody) : _quota();
    }));
    await t.pumpWidget(_app(a, api));
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(48));

    await t.state<PlacesScreenState>(find.byType(PlacesScreen)).reload();
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(S.quotaTitle), findsOneWidget);
    expect(find.textContaining('computed ${a.meta.asOf}'), findsOneWidget); // P-T05
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.text(S.retry), findsNothing); // 한도는 Retry 없음 — 워커 60s 부정 캐시와 정합
    expect(find.byType(PlaceCard), findsNWidgets(48));
    expect(_footer(t), startsWith('48 shown · 70'));
    expect(find.byKey(const Key('live-line')), findsOneWidget);
    await _tapChip(t, 'type-39');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(24));
    expect(calls, 2);
  });

  testWidgets('② rate_limited 429(워커 IP 제한) → 한도 배너 아님 · error + Retry (TSD §8-3)', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiClient(client: MockClient((_) async => http.Response(jsonEncode({'ok': false, 'kind': 'rate_limited', 'message': 'slow down'}), 429, headers: _json)));
    await t.pumpWidget(_app(a, api));
    await t.pumpAndSettle();
    expect(find.text(S.quotaTitle), findsNothing);
    expect(find.textContaining('1,000 calls'), findsNothing);
    expect(find.text(S.errorTitle), findsOneWidget);
    expect(find.text(S.retry), findsOneWidget);
    expect(find.byType(PlaceCard), findsNothing);
  });

  testWidgets('② 빈 items(회귀 #2) → 「No places listed」 빈 상태 · 오류·한도 배너 아님 · Show all 은 추가 호출 없음', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var calls = 0;
    final api = ApiClient(client: MockClient((_) async {
      calls++;
      return _ok('{"ok":true,"fetchedAt":"2026-09-14T09:33:00.000Z","remaining":"900","totalCount":0,"count":0,"code":"28155","type":null,"items":[]}');
    }));
    await t.pumpWidget(_app(a, api, code: '28155'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text(S.emptyTitle), findsOneWidget);
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.text(S.quotaTitle), findsNothing);
    expect(find.byType(PlaceCard), findsNothing);
    expect(find.byKey(const Key('type-all')), findsOneWidget);
    expect(find.byKey(const Key('live-line')), findsOneWidget);
    expect(find.byKey(const Key('places-footer')), findsNothing);
    await t.tap(find.text(S.emptyAction));
    await t.pumpAndSettle();
    expect(calls, 1);
    final all = _allText(t);
    for (final banned in ['갈 수 없', "can't go", 'cannot go', 'Lv0', 'Lv6', 'legal criteria']) {
      expect(all.contains(banned), false, reason: '금지어 「$banned」');
    }
    expect(all.contains(RegExp(r'\d+(\.\d+)?\s*%')), false, reason: '백분율 표기 금지');
  });

  testWidgets('② error 502 → Retry 배너 → 재시도 성공 → 목록 · 이후 실패면 「N min ago」 + 목록 유지', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 6000)); // 푸터까지 빌드되도록
    addTearDown(() => t.binding.setSurfaceSize(null));
    var fail = true;
    var calls = 0;
    final api = ApiClient(client: MockClient((_) async {
      calls++;
      return fail ? _upstream() : _ok(placesBody);
    }));
    await t.pumpWidget(_app(a, api));
    await t.pumpAndSettle();
    expect(find.text(S.errorTitle), findsOneWidget);
    expect(find.text(S.errorNoCache), findsOneWidget);
    expect(find.text(S.retry), findsOneWidget);
    expect(find.byType(PlaceCard), findsNothing);

    fail = false;
    await t.tap(find.text(S.retry));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.byType(PlaceCard), findsWidgets);
    expect(_footer(t), startsWith('48 shown · 70'));

    // 직전 성공 응답 보존 — 다시 실패해도 목록은 남고 「Showing listings from 0 min ago.」
    fail = true;
    await t.state<PlacesScreenState>(find.byType(PlacesScreen)).reload();
    await t.pumpAndSettle();
    expect(calls, 3);
    expect(find.text(S.errorTitle), findsOneWidget);
    expect(find.text(S.errorCached(0)), findsOneWidget);
    expect(find.byType(PlaceCard), findsWidgets);
    expect(_footer(t), startsWith('48 shown · 70'));
  });

  testWidgets('자산에 없는 코드 — 「Region not in the level table」 · 목록은 그대로', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiClient(client: MockClient((_) async => _ok(placesBody)));
    await t.pumpWidget(_app(a, api, code: '99999'));
    await t.pumpAndSettle();
    expect(find.text(S.unknownRegion), findsOneWidget);
    expect(find.byType(LevelChip), findsNothing);
    expect(find.byType(PlaceCard), findsWidgets);
  });

  testWidgets('카드 탭 → /place/:id (push) · 상세 ← → 목록(필터 유지) · why ▸ → /map', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 6000)); // Food 24장이 모두 빌드되도록
    addTearDown(() => t.binding.setSurfaceSize(null));
    final paths = <String>[];
    final api = ApiClient(client: MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path.endsWith('/api/places')) return _ok(placesBody);
      if (req.url.path.endsWith('/intro')) return _ok(_fx('place_2842743_intro.json'));
      return _ok(_fx('place_2842743_common.json'));
    }));
    final router = GoRouter(initialLocation: '/region/27200', routes: [
      GoRoute(path: '/map', builder: (_, _) => const Scaffold(body: Text('MAP-STUB'))),
      GoRoute(path: '/region/:code', builder: (_, s) => PlacesScreen(code: s.pathParameters['code']!, apiClient: api)),
      GoRoute(path: '/place/:id', builder: (_, s) => PlaceScreen(id: s.pathParameters['id']!, apiClient: api, today: '2026-09-14', onOpenKctg: () {})),
    ]);
    await t.pumpWidget(AppScope(
      assets: a,
      appState: AppState(level: 3),
      child: MaterialApp.router(theme: malgilTheme(), routerConfig: router),
    ));
    await t.pumpAndSettle();
    await _tapChip(t, 'type-39');
    await t.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNWidgets(24));

    await t.tap(find.byKey(const Key('place-2842743')));
    await t.pumpAndSettle();
    expect(router.state.uri.path, '/place/2842743');
    expect(find.byKey(const Key('place-title')), findsOneWidget);
    expect(find.text('노이식탁'), findsOneWidget);
    expect(find.byKey(const Key('korean-card')), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/api/place/2842743')).length, 1);
    expect(paths.where((p) => p.endsWith('/intro')).length, 1);

    // ← → 목록으로 pop (Food 필터 유지) · places 재호출 없음
    await t.tap(find.byTooltip(S.back));
    await t.pumpAndSettle();
    expect(router.state.uri.path, '/region/27200');
    expect(find.byType(PlaceCard), findsNWidgets(24));
    expect(paths.where((p) => p.endsWith('/api/places')).length, 1);

    // why ▸ → /map
    await t.tap(find.byKey(const Key('place-2842743')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('why')));
    await t.pumpAndSettle();
    expect(router.state.uri.path, '/map');
    expect(find.text('MAP-STUB'), findsOneWidget);
  });
}
