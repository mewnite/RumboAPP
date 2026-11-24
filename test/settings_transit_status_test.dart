import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_colors.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/settings/presentation/settings_screen.dart';
import 'package:rumbo/features/search/presentation/search_controller.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';
import 'package:rumbo/features/stops_and_lines/presentation/transit_status_providers.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';
import 'package:rumbo/features/trip_planner/presentation/walking_red_status_provider.dart';
import 'package:rumbo/features/trip_planner/presentation/walk_graph_provider.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_walk_graph_worker.dart';

void main() {
  test('walking status reports workerFallo when there is no worker', () async {
    final container = ProviderContainer(
      overrides: [
        walkGraphProvider.overrideWith(
          (ref) => Future<WalkGraphWorker?>.value(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Espera a que el proveedor termine de cargar para no confundir con
    // el nuevo estado "cargando".
    await container.read(walkGraphProvider.future);
    final status = await container.read(walkingRedStatusProvider.future);

    expect(status.status, WalkingRedStatus.workerFallo);
  });

  test(
    'walking status is cargando while the worker starts and then cargada',
    () async {
      final fixture = jsonDecode(
        await File('test/fixtures/osm_seed_minimal.json').readAsString(),
      ) as Map<String, dynamic>;
      final worker = FakeWalkGraphWorker(WalkGraph.fromGeoJson(fixture)!);
      final startup = Completer<WalkGraphWorker?>();
      final container = ProviderContainer(
        overrides: [walkGraphProvider.overrideWith((ref) => startup.future)],
      );
      addTearDown(container.dispose);

      final loadingStatus = await container.read(
        walkingRedStatusProvider.future,
      );
      expect(loadingStatus.status, WalkingRedStatus.cargando);

      startup.complete(worker);
      await container.read(walkGraphProvider.future);
      final status = await container.read(walkingRedStatusProvider.future);
      expect(status.status, WalkingRedStatus.cargada);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets('settings shows counts loaded from the cached feed metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProviderScope(
          overrides: [
            feedUpdateControllerProvider.overrideWith(
              _CachedFeedUpdateController.new,
            ),
            transitLocalStatusProvider.overrideWith(
              (_) => Future.value(_localStatus()),
            ),
            walkingRedStatusProvider.overrideWith(
              (_) =>
                  Future.value(const WalkingRedState(WalkingRedStatus.cargada)),
            ),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToDiagnostics(tester);

    expect(find.textContaining('Fuente: Datos GTFS guardados'), findsOneWidget);
    expect(find.text('18 paradas · 3 líneas'), findsOneWidget);
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>();
    expect(visibleText, contains('Red peatonal: cargada'));
    expect(find.text('Versión: 1.1'), findsOneWidget);
    expect(find.text('Vigencia: 2026-12-17'), findsOneWidget);
    expect(find.text('Versión del esquema SQLite: 7'), findsOneWidget);
    expect(find.text('tamaño de la base: 60.5 MiB'), findsOneWidget);
    expect(find.text('variantes con ID: 1086/1086'), findsOneWidget);
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
            key: ValueKey(mode),
            overrides: [
              feedUpdateControllerProvider.overrideWith(
                _CachedFeedUpdateController.new,
              ),
              transitLocalStatusProvider.overrideWith(
                (_) => Future.value(_localStatus()),
              ),
              walkingRedStatusProvider.overrideWith(
                (_) => Future.value(
                  const WalkingRedState(WalkingRedStatus.cargada),
                ),
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
      await tester.scrollUntilVisible(
        find.text('Muestra de identidad visual'),
        300,
        scrollable: find.byType(Scrollable).last,
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

  testWidgets('settings explains why the pedestrian network is unavailable', (
    tester,
  ) async {
    const cases = [
      (WalkingRedStatus.seedAusente, 'no disponible (motivo: seed ausente)'),
      (WalkingRedStatus.workerFallo, 'no disponible (motivo: worker falló)'),
      (WalkingRedStatus.snapNulo, 'no disponible (motivo: snap nulo)'),
    ];

    for (final (status, expected) in cases) {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProviderScope(
            key: ValueKey(status),
            overrides: [
              feedUpdateControllerProvider.overrideWith(
                _CachedFeedUpdateController.new,
              ),
              transitLocalStatusProvider.overrideWith(
                (_) => Future.value(_localStatus()),
              ),
              walkingRedStatusProvider.overrideWith(
                (_) => Future.value(WalkingRedState(status)),
              ),
            ],
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDiagnostics(tester);
      expect(find.text('Red peatonal: $expected'), findsOneWidget);
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

Future<void> _scrollToDiagnostics(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Diagnóstico local'),
    300,
    scrollable: find.byType(Scrollable).last,
  );
}

TransitLocalStatus _localStatus() => TransitLocalStatus(
  database: TransitDatabaseDiagnostics(
    fileSizeBytes: 63467520,
    schemaVersion: 7,
    feedVersion: '1.1',
    feedValidUntil: DateTime(2026, 12, 17),
    variantCount: 1086,
    variantsWithExternalId: 1086,
  ),
  lastCheckMilliseconds: 1795473504440,
);

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
