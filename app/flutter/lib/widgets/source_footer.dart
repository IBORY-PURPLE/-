// 출처 푸터 — 01_landing.html .footer-source 문구 그대로. 산출일은 메타.산출일 (P-T05).
import 'package:flutter/material.dart';

import '../i18n/strings_en.dart';
import '../theme/tokens.dart';

class SourceFooter extends StatelessWidget {
  const SourceFooter({super.key, required this.asOf});
  final String asOf;

  @override
  Widget build(BuildContext context) {
    final style = MalgilType.labelSmall.copyWith(fontWeight: FontWeight.w400, color: MalgilColors.onSurfaceVariant);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MalgilColors.outlineVariant))),
      child: Text('${S.footerSource(asOf)}\n${S.footerBoundaries}', style: style),
    );
  }
}
