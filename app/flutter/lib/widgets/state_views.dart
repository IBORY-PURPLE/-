// 상태 뷰 — Docs/mockup/05_states.html 과 1:1. loading · empty · error · quota
import 'package:flutter/material.dart';

import '../i18n/strings_en.dart';
import '../theme/tokens.dart';

abstract final class StateViews {
  /// 스켈레톤 — 칩 3개 + 목록 3장 (shimmer 대신 정적 톤: 첫 페인트 비용 최소)
  static Widget loading({int rows = 3}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: const [_Bone(w: 64, h: 32), SizedBox(width: 8), _Bone(w: 72, h: 32), SizedBox(width: 8), _Bone(w: 80, h: 32)]),
          ),
          for (var i = 0; i < rows; i++) _SkeletonRow(titleFrac: [0.7, 0.6, 0.8][i % 3], subFrac: [0.5, 0.4, 0.45][i % 3]),
        ],
      );

  /// 빈 필터 — 「nothing is broken」
  static Widget empty({
    String title = S.emptyTitle,
    String description = S.emptyDescription,
    String? actionLabel = S.emptyAction,
    VoidCallback? onAction,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
        child: Column(
          children: [
            // 이모지는 변이 선택자(U+FE0F) 없이 — 있으면 CanvasKit 이 Noto Color Emoji 서브셋을 더 받고 「Could not find a set of Noto fonts」 경고를 낸다 (2026-09-14 실측)
            const Text('\u{1F5C2}', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(title, style: MalgilType.titleMedium, textAlign: TextAlign.center),
            Text(description, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant), textAlign: TextAlign.center),
            if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      );

  /// 오류 배너 + Retry. [cachedMinutes] 가 있으면 「Showing listings from N min ago.」
  static Widget error({int? cachedMinutes, VoidCallback? onRetry}) => _Banner(
        icon: '⚠', // ⚠ (U+FE0F 없이)
        isError: true,
        title: S.errorTitle,
        body: cachedMinutes == null ? S.errorNoCache : S.errorCached(cachedMinutes),
        action: TextButton(onPressed: onRetry, child: const Text(S.retry)),
      );

  /// 일일 한도 배너 (회귀 #6) — 「실시간 연결 실패」로 쓰지 않는다 (TSD §8-3)
  static Widget quota({String? asOf}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Banner(icon: '⏳', isError: false, title: S.quotaTitle, body: S.quotaBody),
          if (asOf != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.quotaNote(asOf), style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
            ),
        ],
      );
}

class _Bone extends StatelessWidget {
  const _Bone({this.w, required this.h});
  final double? w;
  final double h;
  @override
  Widget build(BuildContext context) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: MalgilColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.titleFrac, required this.subFrac});
  final double titleFrac;
  final double subFrac;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MalgilColors.outlineVariant))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Bone(w: 96, h: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(widthFactor: titleFrac, child: const _Bone(h: 16)),
                  const SizedBox(height: 8),
                  FractionallySizedBox(widthFactor: subFrac, child: const _Bone(h: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.isError, required this.title, required this.body, this.action});
  final String icon;
  final bool isError;
  final String title;
  final String body;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final bg = isError ? MalgilColors.errorContainer : MalgilColors.tertiaryContainer;
    final ink = isError ? MalgilColors.onErrorContainer : MalgilColors.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: bg, border: const Border(bottom: BorderSide(color: MalgilColors.outlineVariant))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MalgilType.titleSmall.copyWith(color: ink)),
                Text(body, style: MalgilType.bodyMedium.copyWith(color: ink)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
