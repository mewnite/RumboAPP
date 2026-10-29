import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static final ColorScheme lightColorScheme = ColorScheme.light().copyWith(
    primary: AppColors.rumbo,
    onPrimary: AppColors.surface,
    primaryContainer: AppColors.ivory,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.lime,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.ivory,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.rumbo,
    onTertiary: AppColors.surface,
    tertiaryContainer: AppColors.ivory,
    onTertiaryContainer: AppColors.ink,
    error: AppColors.lightError,
    onError: AppColors.surface,
    errorContainer: AppColors.lightError,
    onErrorContainer: AppColors.surface,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.ivory,
    surfaceContainer: AppColors.ivory,
    surfaceContainerHigh: AppColors.ivory,
    surfaceContainerHighest: AppColors.ivory,
    onSurfaceVariant: AppColors.secondaryText,
    outline: AppColors.secondaryText,
    outlineVariant: AppColors.lightBorder,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.ivory,
    inversePrimary: AppColors.darkPrimary,
    surfaceTint: AppColors.rumbo,
    shadow: AppColors.ink,
    scrim: AppColors.ink,
  );

  static final ColorScheme darkColorScheme = ColorScheme.dark().copyWith(
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.darkElevatedSurface,
    onPrimaryContainer: AppColors.ivory,
    secondary: AppColors.lime,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.darkElevatedSurface,
    onSecondaryContainer: AppColors.ivory,
    tertiary: AppColors.darkPrimary,
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
    outlineVariant: AppColors.darkBorder,
    inverseSurface: AppColors.ivory,
    onInverseSurface: AppColors.ink,
    inversePrimary: AppColors.rumbo,
    surfaceTint: AppColors.darkPrimary,
    shadow: AppColors.ink,
    scrim: AppColors.ink,
  );

  static ThemeData light() => _theme(
    lightColorScheme,
    scaffoldBackground: AppColors.ivory,
    border: AppColors.lightBorder,
  );

  static ThemeData dark() => _theme(
    darkColorScheme,
    scaffoldBackground: AppColors.ink,
    border: AppColors.darkBorder,
  );

  static ThemeData _theme(
    ColorScheme colorScheme, {
    required Color scaffoldBackground,
    required Color border,
  }) {
    const tabularFigures = [FontFeature.tabularFigures()];
    const textTheme = TextTheme(
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFeatures: tabularFigures,
      ),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFeatures: tabularFigures,
      ),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    );
    final outline = BorderSide(color: border, width: 1);
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.radius16),
      side: outline,
    );
    final sheetShape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppTokens.radius24),
      ),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radius12),
      borderSide: outline,
    );
    final focusedFieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radius12),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scaffoldBackground,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      textTheme: textTheme.apply(
        fontFamily: 'Inter',
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.primaryButtonRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(48, AppTokens.minimumTapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, AppTokens.minimumTapTarget),
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, AppTokens.minimumTapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius8),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size(
            AppTokens.minimumTapTarget,
            AppTokens.minimumTapTarget,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
          vertical: AppTokens.space12,
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        enabledBorder: fieldBorder,
        focusedBorder: focusedFieldBorder,
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: focusedFieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.secondaryContainer,
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space8,
          vertical: AppTokens.space4,
        ),
        side: outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius8),
        ),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.surfaceContainerHigh;
            }
            return states.contains(WidgetState.selected)
                ? colorScheme.secondaryContainer
                : colorScheme.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: colorScheme.outline)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surface,
        surfaceTintColor: AppColors.transparent,
        textStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius12),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
          surfaceTintColor: WidgetStatePropertyAll(AppColors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radius12),
            ),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: AppColors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 1,
        modalElevation: 1,
        shape: sheetShape,
        clipBehavior: Clip.antiAlias,
        showDragHandle: false,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: AppColors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontFamily: 'Inter',
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius12),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
        tileColor: AppColors.transparent,
        minVerticalPadding: AppTokens.space8,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius12),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStatePropertyAll(border),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHigh,
        circularTrackColor: colorScheme.surfaceContainerHigh,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppTokens.radius8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }
}
