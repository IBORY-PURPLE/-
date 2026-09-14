// /map · /region/:code · /place/:id 자리표시 — 다음 브랜치에서 채운다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../i18n/strings_en.dart';
import '../theme/tokens.dart';
import '../widgets/level_chip.dart';
import '../widgets/source_footer.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle; // 예: code · id

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final appState = scope.appState;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/'), tooltip: S.backToLanding),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: appState,
                  builder: (context, _) {
                    final lv = appState.level;
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(S.comingSoon, style: MalgilType.titleMedium),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text('${S.currentLevel}: ', style: MalgilType.bodyMedium),
                            if (lv == null)
                              Text(S.noLevelYet, style: MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant))
                            else ...[
                              LevelChip.ofLevel(lv),
                              const SizedBox(width: 8),
                              Text(S.topikOf[lv] ?? '', style: MalgilType.labelMedium.copyWith(color: MalgilColors.onSurfaceVariant)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: () => context.go('/'), child: const Text(S.backToLanding)),
                      ],
                    );
                  },
                ),
              ),
              SourceFooter(asOf: scope.assets.meta.asOf),
            ],
          ),
        ),
      ),
    );
  }
}
