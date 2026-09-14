// 지역 시트 — Docs/mockup/mockup.js fillSheet · 05_states.html(잠긴 지역) 과 1:1.
//  이름·시도 / 급수 칩 / 89곳 배지 / 근거 한 줄(근거_en) / Computed 산출일·출처 /
//  잠김 배너 · 보류·제외 안내 / Places · live / 동네 말벗 섹션(MalbeotSection — Local companion 카드 자리) / 체류 자기신고 + 한국어 각주(P-T03)
//  compact(<840) 는 showModalBottomSheet, expanded(≥840) 는 우측 패널 — 둘 다 이 위젯을 그린다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/assets.dart';
import '../i18n/strings_en.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'level_chip.dart';
import 'malbeot_section.dart';

class RegionSheet extends StatelessWidget {
  const RegionSheet({
    super.key,
    required this.region,
    required this.userLevel,
    required this.asOf,
    required this.appState,
    this.showHandle = true,
    this.today,
    this.onOpenPlaces,
    this.onOpenKctg,
  });

  final Region region;
  final int userLevel;
  final String asOf; // 메타.산출일 (P-T05)
  final AppState appState;
  final bool showHandle; // 바텀시트일 때만 손잡이
  final String? today; // yyyy-mm-dd. 지정 없으면 오늘 (테스트 주입용)
  final VoidCallback? onOpenPlaces; // 기본 context.go('/region/{code}')
  final VoidCallback? onOpenKctg; // 기본 url_launcher 새 탭

  static const double sheetMaxWidth = 480;

  /// mockup.js whyText — 근거_en 이 있으면 그대로, 없으면 절대값 조각으로 조립
  static String whyText(Region r) {
    if (r.reasonEn.isNotEmpty) return r.reasonEn;
    final parts = <String>[];
    if (r.foreignPer1000 != null) parts.add('Foreign visitors ${r.foreignPer1000} in 1,000');
    if (r.gubun.isNotEmpty) {
      parts.add(const {'자치구': 'Metropolitan district', '시': 'City', '군': 'County'}[r.gubun] ?? r.gubun);
    }
    if (r.e65 != null) parts.add('Residents 65+: ${(r.e65! / 10).round()} in 10');
    if (r.kor != null) parts.add('${r.kor} places listed');
    return parts.join(' · ');
  }

  static String todayString() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final st = stateOf(region, userLevel);
    final muted = MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant);
    final small = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant);
    final day = today ?? todayString();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final stays = appState.visits[region.code] ?? const <String>[];
        final stayedToday = stays.contains(day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle)
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  decoration: BoxDecoration(color: MalgilColors.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(region.nm, style: MalgilType.titleLarge),
                      Text(region.sido, style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LevelChip.ofRegion(region),
                    if (region.is89) const Badge89(),
                  ],
                ),
              ],
            ),
            const Divider(),
            Text(whyText(region), style: MalgilType.bodyMedium),
            const SizedBox(height: 4),
            Text(S.computedSource(asOf), style: small),
            if (st == RegionState.locked) ...[
              const SizedBox(height: 12),
              _LockedBanner(text: S.lockedText(region.lv)),
            ],
            if (st == RegionState.hold) ...[
              const SizedBox(height: 12),
              Text(S.holdText(region.months ?? 1), style: muted),
            ],
            if (st == RegionState.excluded) ...[
              const SizedBox(height: 12),
              Text(S.excludedText, style: muted),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('places-live'),
              onPressed: onOpenPlaces ?? () => context.go('/region/${region.code}'),
              child: const Text(S.placesLive),
            ),
            const SizedBox(height: 12),
            MalbeotSection(region: region, userLevel: userLevel, appState: appState, onOpenKctg: onOpenKctg),
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const Key('stayed-today'),
              value: stayedToday,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(S.stayedToday, style: MalgilType.bodyMedium),
              onChanged: stayedToday ? null : (v) => appState.addVisit(region.code, day),
            ),
            if (stays.isNotEmpty) Text(S.nthStay(stays.length, region.nm), style: MalgilType.bodyMedium),
            const SizedBox(height: 8),
            Text('${S.stayNoteKo1}\n${S.stayNoteKo2}', style: small),
          ],
        );
      },
    );
  }

  /// compact — 모달 바텀시트로 연다 (m3.css .sheet: surface-container-low · 위 모서리 28 · 최대 높이 78%)
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required Region region,
    required int userLevel,
    required String asOf,
    required AppState appState,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MalgilColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MalgilShape.cornerExtraLarge)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: RegionSheet(region: region, userLevel: userLevel, asOf: asOf, appState: appState),
        ),
      ),
    );
  }
}

/// 🔒 배너 — m3.css .banner (tertiary-container). 「you can still visit」 유지
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('locked-banner'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: MalgilColors.tertiaryContainer,
          border: Border(bottom: BorderSide(color: MalgilColors.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔒', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onTertiaryContainer))),
          ],
        ),
      );
}
