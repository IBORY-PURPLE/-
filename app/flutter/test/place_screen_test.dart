// ③ PlaceScreen — 픽스처(place_2842743 노이식탁 · 2026-09-14 실응답 형태): Korean 카드 칩 4개 · Try 문장 · 운영 정보 · 「This region: Lv3」 ·
//    히어로 Type3 → contain + 「· 변경금지(Type3)」 캡션 · 방문 체크 → AppState.addVisit · 푸터 detailCommon2 + detailIntro2
// ④ 관광지(12) → Korean 카드 없음 · intro 미호출 · 푸터 detailCommon2 만
// ⑤ 404 not_found → 「This place is no longer listed」 · quota → 배너 · error → Retry
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malgil/app.dart';
import 'package:malgil/data/api.dart';
import 'package:malgil/data/assets.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/screens/place_screen.dart';
import 'package:malgil/state/app_state.dart';
import 'package:malgil/theme/tokens.dart';
import 'package:malgil/widgets/kto_image.dart';
import 'package:malgil/widgets/level_chip.dart';

MalgilAssets _load() => MalgilAssets.parse(File('assets/data/build_app_assets.json').readAsStringSync());
String _fx(String name) => File('test/fixtures/$name').readAsStringSync();

const _json = {'content-type': 'application/json'};
http.Response _ok(String body) => http.Response(body, 200, headers: {..._json, 'x-malgil-remaining': '900'});
http.Response _err(int status, String kind) => http.Response(jsonEncode({'ok': false, 'kind': kind, 'message': kind}), status, headers: _json);

/// common · intro 픽스처를 경로별로 돌려주는 클라이언트. [commonPatch] 로 common 항목을 바꿔 변형 표본을 만든다.
ApiClient _api({Map<String, dynamic>? commonPatch, List<String>? paths, http.Response Function(http.Request)? override}) {
  var common = _fx('place_2842743_common.json');
  if (commonPatch != null) {
    final j = jsonDecode(common) as Map<String, dynamic>;
    (j['items'] as List).first = {...((j['items'] as List).first as Map), ...commonPatch};
    common = jsonEncode(j);
  }
  return ApiClient(client: MockClient((req) async {
    paths?.add(req.url.path);
    if (override != null) return override(req);
    if (req.url.path.endsWith('/intro')) {
      expect(req.url.queryParameters['type'], '39');
      return _ok(_fx('place_2842743_intro.json'));
    }
    expect(req.url.path, endsWith('/api/place/2842743'));
    return _ok(common);
  }));
}

/// [key] — 같은 테스트 안에서 두 번 pump 할 때 엘리먼트 재사용(late final _api 유지)을 막는다
Widget _app(MalgilAssets a, ApiClient api, {AppState? state, String id = '2842743', Key? key}) => AppScope(
      assets: a,
      appState: state ?? AppState(level: 3),
      child: MaterialApp(theme: malgilTheme(), home: PlaceScreen(key: key, id: id, apiClient: api, today: '2026-09-14', onOpenKctg: () {})),
    );

String _allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');
String _plain(WidgetTester t, Key k) {
  final w = t.widget<Text>(find.byKey(k));
  return w.data ?? w.textSpan!.toPlainText();
}

void main() {
  late MalgilAssets a;
  setUpAll(() => a = _load());

  group('순수 함수', () {
    test('menuPhrases — 「/」「,」「·」 분리 · 「등」 제거 · 20자 미만 · <br> 은 구분자', () {
      expect(menuPhrases('노이스테이크', '새우 크림 리조또 / 해산물 칠리 오일 파스타 / 포크 프라이 라이스 등'),
          ['노이스테이크', '새우 크림 리조또', '해산물 칠리 오일 파스타', '포크 프라이 라이스']);
      expect(menuPhrases('두부두루치기', '오징어두루치기, 김치찌개 · 된장찌개 등<br>공기밥'), ['두부두루치기', '오징어두루치기', '김치찌개', '된장찌개', '공기밥']);
      expect(menuPhrases('', null), isEmpty);
      expect(menuPhrases('아주아주아주아주아주아주아주아주긴메뉴이름입니다', '짧은'), ['짧은']); // 20자 이상 제외
    });
    test('regionCodeOf — 2+3 · 세종 5자리 · 결손', () {
      expect(regionCodeOf({'lDongRegnCd': '27', 'lDongSignguCd': '200'}), '27200');
      expect(regionCodeOf({'lDongRegnCd': '36110', 'lDongSignguCd': '36110'}), '36110');
      expect(regionCodeOf({'lDongRegnCd': '', 'lDongSignguCd': ''}), isNull);
      expect(regionCodeOf({}), isNull);
    });
    test('operatingInfo — 있는 것만 · 순서 · <br> → 줄바꿈', () {
      final intro = ((jsonDecode(_fx('place_2842743_intro.json')) as Map)['items'] as List).first as Map<String, dynamic>;
      expect(operatingInfo(intro), [
        (S.hours, '- 11:30~22:00\n- 마지막 주문 21:00'),
        (S.closed, '연중무휴'),
        (S.parking, '가능'),
        (S.phone, '0507-1486-5252'),
      ]);
      expect(operatingInfo(null), isEmpty);
      expect(operatingInfo({'reservationfood': '전화 예약'}), [(S.reservation, '전화 예약')]);
    });
  });

  testWidgets('③ 노이식탁(39) — Korean 칩 4 · Try · 운영 정보 · This region: Lv3 · 히어로 contain + Type3 캡션 · 2콜', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final paths = <String>[];
    final s = AppState(level: 3);
    await t.pumpWidget(_app(a, _api(paths: paths), state: s));
    await t.pumpAndSettle();

    expect(paths, ['/api/place/2842743', '/api/place/2842743/intro']);
    expect(find.text('노이식탁'), findsOneWidget);
    expect(find.text('대구광역시 남구 대명남로 188 (대명동)'), findsOneWidget);

    // 지역 급수 — 자산(27200 남구 Lv3)
    expect(find.text(S.thisRegion('Lv3')), findsOneWidget);
    expect(t.widget<LevelChip>(find.descendant(of: find.byKey(const Key('region-chip')), matching: find.byType(LevelChip))).kind, LevelChipKind.lv3);
    expect(find.byKey(const Key('why')), findsOneWidget);

    // Korean you'll use here — 4칩 · Try 문장
    expect(find.byKey(const Key('korean-card')), findsOneWidget);
    expect(find.text(S.koreanHereTitle), findsOneWidget);
    for (final m in ['노이스테이크', '새우 크림 리조또', '해산물 칠리 오일 파스타', '포크 프라이 라이스']) {
      expect(find.text(m), findsOneWidget, reason: m);
    }
    expect(find.text('등'), findsNothing);
    expect(_plain(t, const Key('try-line')), 'Try: 「노이스테이크 하나 주세요」 · 「이거 얼마예요?」');

    // About — overview 한국어 · Read more 토글
    expect(_plain(t, const Key('overview')), startsWith('노이식탁은 대구광역시 남구 대명동'));
    expect(t.widget<Text>(find.byKey(const Key('overview'))).maxLines, 4);
    await t.tap(find.byKey(const Key('read-more')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('overview'))).maxLines, isNull);
    expect(find.text(S.showLess), findsOneWidget);

    // 운영 정보 — Hours · Closed · Parking · Phone (Reservation 은 빈값이라 없음)
    expect(find.byKey(const Key('info-card')), findsOneWidget);
    expect(find.text(S.hours), findsOneWidget);
    expect(find.text('- 11:30~22:00\n- 마지막 주문 21:00'), findsOneWidget);
    expect(find.text('연중무휴'), findsOneWidget);
    expect(find.text('0507-1486-5252'), findsOneWidget);
    expect(find.text(S.reservation), findsNothing);
    expect(find.textContaining('<br>'), findsNothing);

    // 히어로 — Type3 → contain · 캡션 「ⓒ한국관광공사 · 변경금지(Type3)」
    final hero = find.byKey(const Key('hero'));
    expect(hero, findsOneWidget);
    expect(t.widget<KtoImage>(hero).cpyrhtDivCd, 'Type3');
    expect(t.widget<Image>(find.descendant(of: hero, matching: find.byType(Image))).fit, BoxFit.contain);
    expect(find.text('${S.sourceCaption}${S.type3Caption}'), findsOneWidget);

    // Local companion(말벗 섹션 compact — 남구 Lv3 → S2 만 · 사용자 Lv3 → 활성 · 고지문) · 푸터
    expect(find.text(S.localCompanion), findsOneWidget);
    expect(find.text(S.licensedInterpreter), findsOneWidget);
    expect(find.byKey(const Key('session-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-s1')), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('interest-s2'))).onPressed, isNotNull);
    expect(find.textContaining(S.malbeotNoticeKo), findsOneWidget);
    final footer = _plain(t, const Key('place-footer'));
    expect(footer, startsWith('Fetched 2026-09-14 '));
    expect(footer, contains('detailCommon2 + detailIntro2 · 출처: ⓒ한국관광공사 · nothing stored on our server'));

    // 방문 자기신고 → AppState.addVisit(지역 code)
    expect(s.visits['27200'], isNull);
    await t.ensureVisible(find.byKey(const Key('visited-here')));
    await t.tap(find.byKey(const Key('visited-here')));
    await t.pumpAndSettle();
    expect(s.visits['27200'], ['2026-09-14']);
    expect(t.widget<CheckboxListTile>(find.byKey(const Key('visited-here'))).value, true);

    final all = _allText(t);
    for (final banned in ['갈 수 없', "can't go", 'cannot go', 'Lv0', 'Lv6', 'legal criteria']) {
      expect(all.contains(banned), false, reason: '금지어 「$banned」');
    }
    expect(all.contains(RegExp(r'\d+(\.\d+)?\s*%')), false, reason: '백분율 표기 금지');
  });

  testWidgets('④ 관광지(12) — Korean 카드 없음 · 운영 정보 없음 · intro 미호출 · 푸터 detailCommon2 만', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final paths = <String>[];
    await t.pumpWidget(_app(a, _api(paths: paths, commonPatch: {'contenttypeid': '12', 'title': '고산골', 'lclsSystm1': 'VE'})));
    await t.pumpAndSettle();
    expect(paths, ['/api/place/2842743']);
    expect(find.text('고산골'), findsOneWidget);
    expect(find.byKey(const Key('korean-card')), findsNothing);
    expect(find.byKey(const Key('info-card')), findsNothing);
    expect(find.byKey(const Key('about-card')), findsOneWidget);
    expect(find.text(S.thisRegion('Lv3')), findsOneWidget);
    final footer = _plain(t, const Key('place-footer'));
    expect(footer, contains('detailCommon2 · 출처'));
    expect(footer, isNot(contains('detailIntro2')));
  });

  testWidgets('이미지 없음 → 히어로 없음 · 급수 미상 코드 → 지역 칩 없음 · 세종 5자리 코드', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(a, _api(commonPatch: {'firstimage': '', 'firstimage2': '', 'lDongRegnCd': '99', 'lDongSignguCd': '999'})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hero')), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const Key('region-chip')), findsNothing);
    expect(find.byKey(const Key('visited-here')), findsOneWidget); // 코드는 있으니 자기신고는 가능

    await t.pumpWidget(_app(a, _api(commonPatch: {'lDongRegnCd': '36110', 'lDongSignguCd': '36110'}), key: const Key('sejong')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('region-chip')), findsOneWidget);
    expect(find.text(S.thisRegion(a.byCode['36110']!.lv)), findsOneWidget);
  });

  testWidgets('⑤ 404 not_found → 「This place is no longer listed」 · 상세 호출 1 · intro 없음', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final paths = <String>[];
    await t.pumpWidget(_app(a, _api(paths: paths, override: (_) => _err(404, 'not_found')), id: '1'));
    await t.pumpAndSettle();
    expect(paths, ['/api/place/1']);
    expect(find.text(S.placeNotListed), findsOneWidget);
    expect(find.text(S.placeNotListedBody), findsOneWidget);
    expect(find.text(S.back), findsOneWidget);
    expect(find.byKey(const Key('place-title')), findsNothing);
  });

  testWidgets('quota → 배너 · error → Retry 후 성공', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(a, _api(override: (_) => _err(429, 'quota'))));
    await t.pumpAndSettle();
    expect(find.text(S.quotaTitle), findsOneWidget);
    expect(find.text(S.errorTitle), findsNothing);

    // 실패 → 성공 전환 클라이언트
    var fail = true;
    final api = _api(override: (req) => fail ? _err(502, 'upstream') : (req.url.path.endsWith('/intro') ? _ok(_fx('place_2842743_intro.json')) : _ok(_fx('place_2842743_common.json'))));
    await t.pumpWidget(_app(a, api, key: const Key('retry')));
    await t.pumpAndSettle();
    expect(find.text(S.errorTitle), findsOneWidget);
    expect(find.text(S.retry), findsOneWidget);
    fail = false;
    await t.tap(find.text(S.retry));
    await t.pumpAndSettle();
    expect(find.text(S.errorTitle), findsNothing);
    expect(find.text('노이식탁'), findsOneWidget);
    expect(find.byKey(const Key('korean-card')), findsOneWidget);
  });
}
