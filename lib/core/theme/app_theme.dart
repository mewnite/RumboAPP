import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static final ColorScheme lightColorScheme = ColorScheme.light().copyWith(
    primary: AppColors.deepBlue,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.ivory,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.mint,
    onSecondary: AppColors.deepBlue,
    secondaryContainer: AppColors.mint,
    onSecondaryContainer: AppColors.deepBlue,
    tertiary: AppColors.deepBlue,
    onTertiary: AppColors.white,
    tertiaryContainer: AppColors.mint,
    onTertiaryContainer: AppColors.ink,
    error: AppColors.lightError,
    onError: AppColors.white,
    errorContainer: AppColors.lightError,
    onErrorContainer: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    surfaceContainerLowest: AppColors.white,
    surfaceContainerLow: AppColors.ivory,
    surfaceContainer: AppColors.surfaceGray,
    surfaceContainerHigh: AppColors.surfaceGray,
    surfaceContainerHighest: AppColors.ivory,
    onSurfaceVariant: AppColors.secondaryText,
    outline: AppColors.secondaryText,
    outlineVariant: AppColors.surfaceGray,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.ivory,
    inversePrimary: AppColors.darkPrimary,
    surfaceTint: AppColors.deepBlue,
  );

  static final ColorScheme darkColorScheme = ColorScheme.dark().copyWith(
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.darkElevatedSurface,
    onPrimaryContainer: AppColors.ivory,
    secondary: AppColors.mint,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.darkElevatedSurface,
    onSecondaryContainer: AppColors.mint,
    tertiary: AppColors.mint,
    onTertiary: AppColors.ink,
    tertiaryContainer: AppColors.darkElevatedSurface,
    onTertiaryContainer: AppColors.ivory,
    error: AppColors.darkError,
    onError: AppColors.ink,
    errorContainer: AppColors.darkError,
    onErrorContainer: AppColors.ink,
    surface: AppColors.darkSurface,
    onSurface: AppColors.ivory,
    surfaceContainerLowest: AppColors.ink,
    surfaceContainerLow: AppColors.darkSurface,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkElevatedSurface,
    surfaceContainerHighest: AppColors.darkElevatedSurface,
    onSurfaceVariant: AppColors.darkSecondaryText,
    outline: AppColors.darkSecondaryText,
    outlineVariant: AppColors.darkElevatedSurface,
    inverseSurface: AppColors.ivory,
    onInverseSurface: AppColors.ink,
    inversePrimary: AppColors.deepBlue,
    surfaceTint: AppColors.darkPrimary,
  );

  static ThemeData light() => _theme(lightColorScheme, AppColors.surfaceGray);

  static ThemeData dark() => _theme(darkColorScheme, AppColors.ink);

  static ThemeData _theme(ColorScheme colorScheme, Color scaffoldBackground) {
    const textTheme = TextTheme(
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme.apply(
        fontFamily: 'Inter',
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontFamily: 'Inter',
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
        ),
      ),
    );
  }
}
