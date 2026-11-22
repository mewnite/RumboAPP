import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_colors.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/settings/presentation/settings_screen.dart';
import 'package:rumbo/features/search/presentation/search_controller.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('settings shows counts loaded from the cached feed metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      buildRumboTestApp(
        wrapApp: (child) => ProviderScope(
          overrides: [
            feedUpdateControllerProvider.overrideWith(
              _CachedFeedUpdateController.new,
            ),
          ],
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fuente: Datos GTFS guardados'), findsOneWidget);
    expect(find.text('18 paradas · 3 líneas'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('settings body text follows both light and dark themes', (
    tester,
  ) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      SharedPreferences.setMockInitialValues({'theme_mode': mode.name});
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProviderScope(
            overrides: [
              feedUpdateControllerProvider.overrideWith(
                _CachedFeedUpdateController.new,
              ),
            ],
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceLabel = find.text('Fuente: Datos GTFS guardados');
      expect(sourceLabel, findsOneWidget);
      final element = tester.element(sourceLabel);
      final activeTheme = Theme.of(element);
      expect(
        activeTheme.brightness,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(
        activeTheme.colorScheme.onSurface,
        mode == ThemeMode.dark ? AppColors.ivory : AppColors.ink,
      );
      final inheritedColor = DefaultTextStyle.of(element).style.color;
      expect(
        inheritedColor,
        mode == ThemeMode.dark ? AppColors.ivory : AppColors.ink,
      );
      expect(
        tester.widget<Text>(sourceLabel).style?.color,
        mode == ThemeMode.dark ? AppColors.ivory : AppColors.ink,
      );
      expect(
        tester.widget<Text>(find.text('18 paradas · 3 líneas')).style?.color,
        mode == ThemeMode.dark ? AppColors.ivory : AppColors.ink,
      );
      expect(
        tester
            .widget<Text>(find.text('Muestra de identidad visual'))
            .style
            ?.color,
        mode == ThemeMode.dark ? AppColors.ivory : AppColors.ink,
      );
    }
  });

  test('remote address search is disabled by default and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(remotePlaceSearchEnabledProvider.future),
      isFalse,
    );
    await container
        .read(remotePlaceSearchEnabledProvider.notifier)
        .setEnabled(true);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('remote_place_search_enabled'), isTrue);
  });
}

class _CachedFeedUpdateController extends FeedUpdateController {
  @override
  Future<FeedUpdateState> build() async => FeedUpdateState(
    phase: FeedUpdatePhase.updated,
    status: FeedStatus(
      source: 'Datos GTFS guardados',
      version: 'demo-1',
      downloadedAt: DateTime(2026, 1, 1),
      stopCount: 18,
      routeCount: 3,
    ),
  );
}
