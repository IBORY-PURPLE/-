// 랜딩 / Choose your level — Docs/mockup/01_landing.html 그대로.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../i18n/strings_en.dart';
import '../theme/tokens.dart';
import '../widgets/level_chip.dart';
import '../widgets/source_footer.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const double maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final appState = scope.appState;
    final asOf = scope.assets.meta.asOf;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: ListenableBuilder(
            listenable: appState,
            builder: (context, _) {
              final chosen = appState.level;
              return Column(
                children: [
                  _TopBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(S.landingHeadline, style: MalgilType.headlineSmall),
                        const SizedBox(height: 12),
                        Text(S.landingDescription, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        for (final c in S.levelCards) ...[
                          _LevelCard(text: c, selected: chosen == c.level, onTap: () => appState.setLevel(c.level)),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          key: const Key('show-my-map'),
                          onPressed: chosen == null ? null : () => context.go('/map'),
                          child: const Text(S.showMyMap),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          key: const Key('judge-preview'),
                          onPressed: () => context.go('/map?demo=1'),
                          child: const Text(S.judgePreview),
                        ),
                      ],
                    ),
                  ),
                  SourceFooter(asOf: asOf),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.only(left: 16, right: 8),
        color: MalgilColors.surface,
        child: Row(
          children: [
            const Text(S.appTitleKo, style: MalgilType.titleLarge),
            const SizedBox(width: 6),
            Text(S.appTitleEn, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
          ],
        ),
      );
}

/// Card.outlined + InkWell — 선택 시 primary 2px 테두리 + primary-container 배경 (m3.css .card.selectable.selected)
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.text, required this.selected, required this.onTap});
  final LevelCardText text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(MalgilShape.cornerMedium);
    return Material(
      color: selected ? MalgilColors.primaryContainer : MalgilColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected ? const BorderSide(color: MalgilColors.primary, width: 2) : const BorderSide(color: MalgilColors.outlineVariant),
      ),
      child: InkWell(
        key: Key('level-card-${text.level}'),
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LevelChip.ofLevel(text.level, label: text.label),
                  const SizedBox(width: 8),
                  Text(text.topik, style: MalgilType.labelMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              Text(text.description, style: MalgilType.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
