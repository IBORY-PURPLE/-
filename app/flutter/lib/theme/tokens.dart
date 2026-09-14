// 말길 디자인 토큰 — Docs/mockup/m3.css 와 1:1 (hex · 반경 · 타입 스케일).
// 이름 = m3.css 변수명(--md-sys-color-*, --map-*)의 camelCase. grep 대조 대상.
import 'package:flutter/material.dart';

/// 색 토큰. m3.css `:root` 값을 그대로 옮겼다.
abstract final class MalgilColors {
  // ── --md-sys-color-* ──
  static const Color primary = Color(0xFF2A5A8C);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFD3E3FD);
  static const Color onPrimaryContainer = Color(0xFF001C3B);
  static const Color secondary = Color(0xFF545F70);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFD8E3F8);
  static const Color onSecondaryContainer = Color(0xFF111C2B);
  static const Color tertiary = Color(0xFF6B5B3E);
  static const Color tertiaryContainer = Color(0xFFF5DEB9);
  static const Color onTertiaryContainer = Color(0xFF241A04);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);
  static const Color surface = Color(0xFFF9F9FC);
  static const Color surfaceDim = Color(0xFFD9DADF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF3F4F9);
  static const Color surfaceContainer = Color(0xFFEDEEF3);
  static const Color surfaceContainerHigh = Color(0xFFE7E8EE);
  static const Color surfaceContainerHighest = Color(0xFFE2E2E8);
  static const Color onSurface = Color(0xFF191C20);
  static const Color onSurfaceVariant = Color(0xFF43474E);
  static const Color outline = Color(0xFF74777F);
  static const Color outlineVariant = Color(0xFFC4C6CF);
  static const Color inverseSurface = Color(0xFF2E3135);
  static const Color inverseOnSurface = Color(0xFFF0F0F4);

  // m3.css 에 없어 M3 기본 규칙으로 보탠 값(추정 · 흰색 텍스트)
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  // ── --map-* (dataviz 순차 램프 + 특수 상태) ──
  static const Color mapLv3 = Color(0xFF86B6EF);
  static const Color mapLv4 = Color(0xFF2A78D6);
  static const Color mapLv5 = Color(0xFF104281);
  static const Color mapLv12 = Color(0xFFE1E0D9); // 급수 무관(외국인이 이미 오는 곳)
  static const Color mapLockedFill = Color(0xFFFFFFFF); // 내 급수 초과 — 빗금
  static const Color mapLockedInk = Color(0xFF898781);
  static const Color mapExcluded = Color(0xFFF0EFEC); // 자료 부족
  static const Color mapHold = Color(0xFFF3F4F9); // 보류 — 점선
  static const Color mapBorder = Color(0xFFFFFFFF);
  static const Color map89Border = Color(0xFF191C20);

  /// Lv1~2 칩·Lv3 칩의 글자색 (m3.css .lv.lv12 / .lv.lv3)
  static const Color chipInkOnLv12 = Color(0xFF43474E);
  static const Color chipInkOnLv3 = Color(0xFF001C3B);

  /// Flutter ColorScheme — 토큰 값으로 명시 생성 (seed 파생 금지: css와 값이 달라짐)
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: onSurface,
    surfaceDim: surfaceDim,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    inverseSurface: inverseSurface,
    onInverseSurface: inverseOnSurface,
  );
}

/// 모서리 반경 (--md-sys-shape-corner-*)
abstract final class MalgilShape {
  static const double cornerSmall = 8;
  static const double cornerMedium = 12;
  static const double cornerLarge = 16;
  static const double cornerExtraLarge = 28;
  static const double cornerFull = 999;
}

/// 타입 스케일 (m3.css .display-small … .label-small). 폰트는 시스템 sans.
abstract final class MalgilType {
  static const TextStyle displaySmall = TextStyle(fontSize: 36, height: 44 / 36, fontWeight: FontWeight.w400);
  static const TextStyle headlineLarge = TextStyle(fontSize: 32, height: 40 / 32, fontWeight: FontWeight.w400);
  static const TextStyle headlineSmall = TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w400);
  static const TextStyle titleLarge = TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w400);
  static const TextStyle titleMedium = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500, letterSpacing: .15);
  static const TextStyle titleSmall = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, letterSpacing: .1);
  static const TextStyle bodyLarge = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, letterSpacing: .5);
  static const TextStyle bodyMedium = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, letterSpacing: .25);
  static const TextStyle bodySmall = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, letterSpacing: .4);
  static const TextStyle labelLarge = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, letterSpacing: .1);
  static const TextStyle labelMedium = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: .5);
  static const TextStyle labelSmall = TextStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w500, letterSpacing: .5);

  static const TextTheme textTheme = TextTheme(
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}

/// 앱 ThemeData — useMaterial3 + 위 토큰.
ThemeData malgilTheme() {
  const scheme = MalgilColors.scheme;
  final rounded12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(MalgilShape.cornerMedium));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: MalgilType.textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: MalgilColors.surface,
      foregroundColor: MalgilColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w400, color: MalgilColors.onSurface),
    ),
    cardTheme: CardThemeData(
      color: MalgilColors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded12,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        textStyle: MalgilType.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: MalgilType.labelLarge, shape: const StadiumBorder()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        textStyle: MalgilType.labelLarge,
        side: const BorderSide(color: MalgilColors.outline),
        shape: const StadiumBorder(),
      ),
    ),
    dividerTheme: const DividerThemeData(color: MalgilColors.outlineVariant, thickness: 1, space: 16),
  );
}
