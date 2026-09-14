// KtoImage — 앱 유일 이미지 위젯 규칙: Type1 만 cover · 그 외 contain · 캡션 자동 · url 없으면 텍스트 히어로 ·
// visitkorea http → https 승격 · CORS 없는 공사 서버를 위해 처음부터 <img> 요소(prefer — fallback 은 실패하는 fetch 를 한 번 더 보낸다)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/i18n/strings_en.dart';
import 'package:malgil/widgets/kto_image.dart';

void main() {
  test('normalizeUrl — visitkorea 만 http→https · 나머지 그대로 · 공백 정리', () {
    expect(KtoImage.normalizeUrl('http://tong.visitkorea.or.kr/cms/resource/39/2842739_image2_1.jpg'),
        'https://tong.visitkorea.or.kr/cms/resource/39/2842739_image2_1.jpg');
    expect(KtoImage.normalizeUrl('https://tong.visitkorea.or.kr/a.jpg'), 'https://tong.visitkorea.or.kr/a.jpg');
    expect(KtoImage.normalizeUrl('http://example.com/a.jpg'), 'http://example.com/a.jpg');
    expect(KtoImage.normalizeUrl('  '), '');
  });

  test('modifiable · heroCaptionSuffix', () {
    expect(KtoImage.modifiable('Type1'), true);
    expect(KtoImage.modifiable('Type3'), false);
    expect(KtoImage.modifiable(''), false);
    expect(KtoImage.modifiable(null), false);
    expect(KtoImage.heroCaptionSuffix('Type3'), S.type3Caption);
    expect(KtoImage.heroCaptionSuffix('Type1'), '');
  });

  testWidgets('Type3 → contain + 검정 바탕 · Type1 → cover · <img> prefer 전략 · https 승격 · 캡션', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Column(children: [
        KtoImage(key: Key('t3'), url: 'http://tong.visitkorea.or.kr/x.jpg', cpyrhtDivCd: 'Type3', width: 96, height: 72),
        KtoImage(key: Key('t1'), url: 'https://tong.visitkorea.or.kr/y.jpg', cpyrhtDivCd: 'Type1', width: 96, height: 72),
        KtoImage(key: Key('none'), url: '', cpyrhtDivCd: '', label: 'Food · 한식', width: 96, height: 72),
      ]),
    ));
    await t.pumpAndSettle();

    Image img(String k) => t.widget<Image>(find.descendant(of: find.byKey(Key(k)), matching: find.byType(Image)));
    expect(img('t3').fit, BoxFit.contain);
    expect(img('t1').fit, BoxFit.cover);
    for (final k in ['t3', 't1']) {
      expect((img(k).image as NetworkImage).webHtmlElementStrategy, WebHtmlElementStrategy.prefer, reason: k);
    }
    expect((img('t3').image as NetworkImage).url, 'https://tong.visitkorea.or.kr/x.jpg');
    expect(find.text(S.sourceCaption), findsNWidgets(2));
    // 이미지 없음 → 텍스트 히어로 · Image 없음 · 캡션 없음
    expect(find.descendant(of: find.byKey(const Key('none')), matching: find.byType(Image)), findsNothing);
    expect(find.text('Food · 한식'), findsOneWidget);
  });
}
