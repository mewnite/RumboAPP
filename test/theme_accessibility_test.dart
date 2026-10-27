import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_colors.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/core/theme/contrast.dart';
import 'package:rumbo/core/widgets/line_chip.dart';

void main() {
  test('dark theme assigns dark surfaces to shared Material components', () {
    final theme = AppTheme.dark();

    expect(theme.scaffoldBackgroundColor, AppColors.ink);
    expect(theme.cardTheme.color, AppColors.darkSurface);
    expect(theme.dialogTheme.backgroundColor, AppColors.darkElevatedSurface);
    expect(theme.bottomSheetTheme.backgroundColor, AppColors.darkSurface);
    expect(theme.inputDecorationTheme.fillColor, AppColors.darkSurface);
  });

  testWidgets('LineChip selects AA text on light and dark line colors', (
    tester,
  ) async {
    const lightBackground = AppColors.mint;
    const darkBackground = AppColors.ink;
    const lightChip = LineChip(
      key: ValueKey('light-line-chip'),
      label: 'D',
      backgroundColor: lightBackground,
    );
    const darkChip = LineChip(
      key: ValueKey('dark-line-chip'),
      label: '142',
      backgroundColor: darkBackground,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: Wrap(children: [lightChip, darkChip])),
      ),
    );

    expect(find.text('D'), findsOneWidget);
    expect(find.text('142'), findsOneWidget);

    final lightForeground = (tester.widget(
      find.byKey(const ValueKey('light-line-chip')),
    ) as LineChip).foregroundColor;
    final darkForeground = (tester.widget(
      find.byKey(const ValueKey('dark-line-chip')),
    ) as LineChip).foregroundColor;

    expect(
      contrastRatio(lightForeground, lightBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(darkForeground, darkBackground),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('light and dark theme text pairs meet WCAG AA contrast', () {
    final pairs = <(String, Color, Color)>[
      (
        'light primary',
        AppTheme.lightColorScheme.onPrimary,
        AppTheme.lightColorScheme.primary,
      ),
      (
        'light secondary',
        AppTheme.lightColorScheme.onSecondary,
        AppTheme.lightColorScheme.secondary,
      ),
      ('brand lime with ink', AppColors.ink, AppColors.lime),
      (
        'light surface',
        AppTheme.lightColorScheme.onSurface,
        AppTheme.lightColorScheme.surface,
      ),
      (
        'light surface variant',
        AppTheme.lightColorScheme.onSurfaceVariant,
        AppColors.surfaceGray,
      ),
      (
        'light error',
        AppTheme.lightColorScheme.onError,
        AppTheme.lightColorScheme.error,
      ),
      (
        'light primary container',
        AppTheme.lightColorScheme.onPrimaryContainer,
        AppTheme.lightColorScheme.primaryContainer,
      ),
      (
        'light tertiary',
        AppTheme.lightColorScheme.onTertiary,
        AppTheme.lightColorScheme.tertiary,
      ),
      (
        'light tertiary container',
        AppTheme.lightColorScheme.onTertiaryContainer,
        AppTheme.lightColorScheme.tertiaryContainer,
      ),
      (
        'light secondary container',
        AppTheme.lightColorScheme.onSecondaryContainer,
        AppTheme.lightColorScheme.secondaryContainer,
      ),
      (
        'light error container',
        AppTheme.lightColorScheme.onErrorContainer,
        AppTheme.lightColorScheme.errorContainer,
      ),
      (
        'light inverse surface',
        AppTheme.lightColorScheme.onInverseSurface,
        AppTheme.lightColorScheme.inverseSurface,
      ),
      (
        'dark primary',
        AppTheme.darkColorScheme.onPrimary,
        AppTheme.darkColorScheme.primary,
      ),
      (
        'dark secondary',
        AppTheme.darkColorScheme.onSecondary,
        AppTheme.darkColorScheme.secondary,
      ),
      (
        'dark surface',
        AppTheme.darkColorScheme.onSurface,
        AppTheme.darkColorScheme.surface,
      ),
      (
        'dark surface variant',
        AppTheme.darkColorScheme.onSurfaceVariant,
        AppColors.darkElevatedSurface,
      ),
      (
        'dark error',
        AppTheme.darkColorScheme.onError,
        AppTheme.darkColorScheme.error,
      ),
      (
        'dark primary container',
        AppTheme.darkColorScheme.onPrimaryContainer,
        AppTheme.darkColorScheme.primaryContainer,
      ),
      (
        'dark tertiary',
        AppTheme.darkColorScheme.onTertiary,
        AppTheme.darkColorScheme.tertiary,
      ),
      (
        'dark tertiary container',
        AppTheme.darkColorScheme.onTertiaryContainer,
        AppTheme.darkColorScheme.tertiaryContainer,
      ),
      (
        'dark secondary container',
        AppTheme.darkColorScheme.onSecondaryContainer,
        AppTheme.darkColorScheme.secondaryContainer,
      ),
      (
        'dark error container',
        AppTheme.darkColorScheme.onErrorContainer,
        AppTheme.darkColorScheme.errorContainer,
      ),
      (
        'dark inverse surface',
        AppTheme.darkColorScheme.onInverseSurface,
        AppTheme.darkColorScheme.inverseSurface,
      ),
    ];

    for (final (name, foreground, background) in pairs) {
      expect(
        contrastRatio(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: '$name must meet the 4.5:1 AA threshold.',
      );
    }
  });
}
