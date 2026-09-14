// 앱 유일 이미지 위젯 (TSD §9). 공사 이미지는 반드시 이 위젯으로만 그린다.
//  - cpyrhtDivCd == 'Type1' 만 변형(cover) 허용. 그 외(Type3 · 빈값)는 contain + 검정 레터박스 — 크롭 금지 (회귀 #5)
//  - 우하단 「ⓒ한국관광공사」 캡션을 위젯 레벨에서 자동 부착 — 누락이 구조적으로 불가능
//  - url 없으면 텍스트 히어로(라벨) — 깨진 이미지 금지 (회귀 #4)
//  - 로딩·오류 시 회색 박스
import 'package:flutter/material.dart';

import '../i18n/strings_en.dart';
import '../theme/tokens.dart';

class KtoImage extends StatelessWidget {
  const KtoImage({
    super.key,
    required this.url,
    required this.cpyrhtDivCd,
    this.label,
    this.width,
    this.height,
    this.aspectRatio,
    this.borderRadius = MalgilShape.cornerSmall,
    this.captionSmall = true,
    this.captionSuffix,
  });

  final String? url; // firstimage · firstimage2 — 없으면 텍스트 히어로
  final String? cpyrhtDivCd; // Type1 | Type3 | '' (공공누리 유형)
  final String? label; // 텍스트 히어로에 보일 라벨 (예: 'Food · 한식')
  final double? width;
  final double? height;
  final double? aspectRatio; // 지정 시 AspectRatio 로 감쌈 (예: 16/9 히어로)
  final double borderRadius;
  final bool captionSmall; // 썸네일(9px)인지 히어로(11px)인지
  final String? captionSuffix; // 캡션 뒤에 덧붙일 문구 (예: 「 · 변경금지(Type3)」) — 출처 문구 자체는 바꿀 수 없다

  static bool modifiable(String? cpyrhtDivCd) => cpyrhtDivCd == 'Type1';

  /// 공사 이미지 URL 정규화 — `http://…visitkorea.or.kr` 는 https 로 (2026-09-14 실측: https 200 · 응답은 같은 ETag).
  /// firstimage 가 http 로 오는 건이 섞여 있어(places_27200 표본 24/38) https 배포에서 혼합 콘텐츠로 막히는 것을 막는다.
  static String normalizeUrl(String u) {
    final t = u.trim();
    if (!t.startsWith('http://')) return t;
    final host = Uri.tryParse(t)?.host ?? '';
    return host.endsWith('visitkorea.or.kr') ? 'https://${t.substring(7)}' : t;
  }

  /// 히어로 캡션 문구 — Type3(변경금지)면 「 · 변경금지(Type3)」 를 덧붙인다 (04_place.html)
  static String heroCaptionSuffix(String? cpyrhtDivCd) => cpyrhtDivCd == 'Type3' ? S.type3Caption : '';

  @override
  Widget build(BuildContext context) {
    final u = normalizeUrl(url ?? '');
    Widget body;
    if (u.isEmpty) {
      body = _textHero();
    } else {
      final cover = modifiable(cpyrhtDivCd);
      body = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cover ? MalgilColors.surfaceContainerHigh : const Color(0xFF111111)),
          Image.network(
            u,
            // 공사 이미지 서버는 CORS 헤더(Access-Control-Allow-Origin)가 없다(2026-09-14 실측) → CanvasKit 의 fetch 는 항상 실패한다.
            // fallback 은 매번 실패하는 fetch 를 한 번 더 보내고(이미지당 콘솔 오류 2줄 · 2026-09-14 브라우저 실측) <img> 로 넘어가므로
            // 처음부터 <img> 요소로 그린다(prefer). never 면 웹에서 모든 공사 이미지가 회색 박스가 된다.
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            fit: cover ? BoxFit.cover : BoxFit.contain,
            alignment: Alignment.center,
            loadingBuilder: (context, child, progress) => progress == null ? child : _greyBox(),
            errorBuilder: (context, error, stack) => _greyBox(),
            semanticLabel: label,
          ),
          Positioned(right: captionSmall ? 2 : 8, bottom: captionSmall ? 2 : 8, child: _caption()),
        ],
      );
    }
    Widget boxed = ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: body);
    if (aspectRatio != null) boxed = AspectRatio(aspectRatio: aspectRatio!, child: boxed);
    return SizedBox(width: width, height: height, child: boxed);
  }

  Widget _caption() => Container(
        padding: EdgeInsets.symmetric(horizontal: captionSmall ? 4 : 8, vertical: captionSmall ? 0 : 2),
        decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(captionSmall ? 3 : 4)),
        child: Text(
          '${S.sourceCaption}${captionSuffix ?? ''}',
          style: TextStyle(fontSize: captionSmall ? 9 : 11, height: captionSmall ? 12 / 9 : 16 / 11, fontWeight: FontWeight.w500, color: Colors.white),
        ),
      );

  Widget _greyBox() => const ColoredBox(color: MalgilColors.surfaceContainerHigh, child: SizedBox.expand());

  /// 텍스트 히어로 — 썸네일(captionSmall)은 11px, 16:9 히어로는 titleMedium (메뉴 텍스트가 읽히는 크기)
  Widget _textHero() => Container(
        color: MalgilColors.surfaceContainerHigh,
        alignment: Alignment.center,
        padding: EdgeInsets.all(captionSmall ? 6 : 16),
        child: Text(
          label ?? '',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: captionSmall
              ? const TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, color: MalgilColors.onSurfaceVariant)
              : MalgilType.titleMedium.copyWith(color: MalgilColors.onSurfaceVariant),
        ),
      );
}
