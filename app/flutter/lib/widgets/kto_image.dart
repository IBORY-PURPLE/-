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
  });

  final String? url; // firstimage · firstimage2 — 없으면 텍스트 히어로
  final String? cpyrhtDivCd; // Type1 | Type3 | '' (공공누리 유형)
  final String? label; // 텍스트 히어로에 보일 라벨 (예: 'Food · 한식')
  final double? width;
  final double? height;
  final double? aspectRatio; // 지정 시 AspectRatio 로 감쌈 (예: 16/9 히어로)
  final double borderRadius;
  final bool captionSmall; // 썸네일(9px)인지 히어로(11px)인지

  static bool modifiable(String? cpyrhtDivCd) => cpyrhtDivCd == 'Type1';

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
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
          S.sourceCaption,
          style: TextStyle(fontSize: captionSmall ? 9 : 11, height: captionSmall ? 12 / 9 : 16 / 11, fontWeight: FontWeight.w500, color: Colors.white),
        ),
      );

  Widget _greyBox() => const ColoredBox(color: MalgilColors.surfaceContainerHigh, child: SizedBox.expand());

  Widget _textHero() => Container(
        color: MalgilColors.surfaceContainerHigh,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Text(
          label ?? '',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, color: MalgilColors.onSurfaceVariant),
        ),
      );
}
