// 급수 칩 — m3.css .lv.lv12/.lv3/.lv4/.lv5/.hold/.excluded (색 = tokens)
import 'package:flutter/material.dart';

import '../data/assets.dart';
import '../i18n/strings_en.dart';
import '../theme/tokens.dart';

enum LevelChipKind { lv12, lv3, lv4, lv5, hold, excluded }

class LevelChip extends StatelessWidget {
  const LevelChip({super.key, required this.kind, this.label});

  final LevelChipKind kind;
  final String? label; // 지정하지 않으면 종류별 기본 라벨

  /// 급수 숫자(2..5)로
  factory LevelChip.ofLevel(int level, {Key? key, String? label}) => LevelChip(
        key: key,
        kind: switch (level) { 2 => LevelChipKind.lv12, 3 => LevelChipKind.lv3, 4 => LevelChipKind.lv4, _ => LevelChipKind.lv5 },
        label: label,
      );

  /// 지역 행의 lv 문자열로 (보류·제외 포함). [anyLevel] 이면 Lv1~2 를 「Any level」로.
  factory LevelChip.ofRegion(Region r, {Key? key, bool anyLevel = true}) {
    if (r.lv == lvHold) return LevelChip(key: key, kind: LevelChipKind.hold);
    if (r.lv == lvExcluded) return LevelChip(key: key, kind: LevelChipKind.excluded);
    final n = lvNum[r.lv] ?? 5;
    return LevelChip.ofLevel(n, key: key, label: n == 2 && anyLevel ? S.chipAnyLevel : r.lv);
  }

  @override
  Widget build(BuildContext context) {
    final (bg, ink, dashed) = switch (kind) {
      LevelChipKind.lv12 => (MalgilColors.mapLv12, MalgilColors.chipInkOnLv12, false),
      LevelChipKind.lv3 => (MalgilColors.mapLv3, MalgilColors.chipInkOnLv3, false),
      LevelChipKind.lv4 => (MalgilColors.mapLv4, Colors.white, false),
      LevelChipKind.lv5 => (MalgilColors.mapLv5, Colors.white, false),
      LevelChipKind.hold => (MalgilColors.surfaceContainerHighest, MalgilColors.chipInkOnLv12, true),
      LevelChipKind.excluded => (MalgilColors.surfaceContainerHighest, MalgilColors.chipInkOnLv12, true),
    };
    final text = label ??
        switch (kind) {
          LevelChipKind.lv12 => S.chipLv12,
          LevelChipKind.lv3 => S.chipLv3,
          LevelChipKind.lv4 => S.chipLv4,
          LevelChipKind.lv5 => S.chipLv5,
          LevelChipKind.hold => S.chipHold,
          LevelChipKind.excluded => S.chipExcluded,
        };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MalgilShape.cornerSmall),
        // CSS 는 dashed 테두리 — Flutter 기본 Border 는 점선 미지원이라 실선 outline 으로 대체(추정 · 시각 차 미미)
        border: dashed ? Border.all(color: MalgilColors.outline) : null,
      ),
      child: Text(text, style: MalgilType.labelMedium.copyWith(color: ink, letterSpacing: 0)),
    );
  }
}

/// 인구감소지역 배지 (m3.css .badge-89)
class Badge89 extends StatelessWidget {
  const Badge89({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MalgilColors.map89Border, width: 1.5),
        ),
        child: Text(S.badge89, style: MalgilType.labelSmall.copyWith(color: MalgilColors.onSurface)),
      );
}
