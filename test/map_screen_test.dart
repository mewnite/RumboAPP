import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/favorites/data/fake_favorites_repository.dart';
import 'package:rumbo/features/favorites/domain/favorite.dart';
import 'package:rumbo/features/favorites/domain/favorites_repository.dart';
import 'package:rumbo/features/favorites/presentation/favorites_controller.dart';
import 'package:rumbo/features/map/data/connectivity_provider.dart';
import 'package:rumbo/features/map/presentation/map_location_controller.dart';
import 'package:rumbo/features/map/presentation/map_screen.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

import 'fakes/fake_location_repository.dart';

void main() {
  late FakeLocationRepository repository;

  setUp(() => repository = FakeLocationRepository());

  testWidgets('does not request location until user confirms the action', (
    tester,
  ) async {
    await tester.pumpWidget(_mapApp(repository));
    await tester.pumpAndSettle();

    expect(repository.permissionChecks, 0);
    await tester.tap(find.byTooltip('Usar mi ubicación'));
    await tester.pumpAndSettle();
    expect(repository.permissionChecks, 0);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(repository.permissionChecks, 1);
    expect(repository.locationReads, 1);
  });

  testWidgets('shows search, attribution, and live bus configuration state', (
    tester,
  ) async {
    await tester.pumpWidget(_mapApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('¿A dónde vamos?'), findsOneWidget);
    expect(find.text('Paradas y ómnibus'), findsOneWidget);
    expect(
      find.textContaining('No se pudieron cargar los datos oficiales:'),
      findsOneWidget,
    );
    expect(find.text('© OSM'), findsOneWidget);

    await tester.tap(find.text('© OSM'));
    await tester.pumpAndSettle();
    expect(find.text('Datos del mapa'), findsOneWidget);
    expect(find.textContaining('zona aproximada'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('map-search-control')));
    await tester.pumpAndSettle();
    expect(find.text('Planificá tu viaje'), findsOneWidget);
    expect(find.text('Desde'), findsOneWidget);
    expect(find.text('Hasta'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Centro');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El GTFS oficial todavía no está disponible.'),
      findsNothing,
    );
    expect(
      find.textContaining('No encontramos paradas o líneas locales'),
      findsOneWidget,
    );
  });

  testWidgets(
    'pauses live polling in the background and resumes in foreground',
    (tester) async {
      final source = _CountingBusSource();
      await tester.pumpWidget(
        _mapApp(
          repository,
          realtimeBusSource: source,
          realtimePollInterval: const Duration(milliseconds: 30),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5));
      expect(source.calls, greaterThanOrEqualTo(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final callsWhilePaused = source.calls;
      await tester.pump(const Duration(milliseconds: 80));
      expect(source.calls, callsWhilePaused);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(source.calls, greaterThan(callsWhilePaused));
    },
  );

  testWidgets('shows a retry control after map style loading times out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mapApp(repository, mapLoadTimeout: const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.text('No se pudo cargar el mapa'), findsOneWidget);
    expect(find.text('Reintentar'), findsWidgets);
  });

  testWidgets('shows Casa and Trabajo shortcuts only when defined', (
    tester,
  ) async {
    final favorites = FakeFavoritesRepository([
      Favorite.place(
        slot: FavoritePlaceSlot.home,
        name: 'Mi casa',
        latitude: -34.9,
        longitude: -56.1,
      ),
    ]);
    await tester.pumpWidget(
      _mapApp(repository, favoritesRepository: favorites),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-favorite-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-favorite-work')), findsNothing);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Trabajo'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('map-favorite-home')));
    await tester.pumpAndSettle();

    expect(find.text('Planificá tu viaje'), findsOneWidget);
    expect(find.text('Mi casa'), findsWidgets);
  });

  testWidgets('does not show favorite shortcuts without defined places', (
    tester,
  ) async {
    await tester.pumpWidget(_mapApp(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-favorite-home')), findsNothing);
    expect(find.byKey(const ValueKey('map-favorite-work')), findsNothing);
  });

  testWidgets('saves and removes a line as favorite from the map', (
    tester,
  ) async {
    const stop = Stop(
      id: 'stop-1',
      name: 'Plaza',
      latitude: -34.9,
      longitude: -56.1,
    );
    const route = Route(id: 'r1', shortName: 'A', longName: 'Centro');
    final favorites = FakeFavoritesRepository();
    await tester.pumpWidget(
      _mapApp(
        repository,
        favoritesRepository: favorites,
        overrides: [
          nearbyOfficialStopsProvider.overrideWith((ref) async => [stop]),
          nearbyStopRoutesProvider.overrideWith(
            (ref) async => {
              'stop-1': [route],
            },
          ),
          routeVariantsProvider('r1').overrideWith((ref) async => []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final expandRoutes = find.byTooltip('Ver variantes de línea');
    await tester.ensureVisible(expandRoutes);
    await tester.pumpAndSettle();
    await tester.tap(expandRoutes);
    await tester.pumpAndSettle();

    final routeTile = find.byKey(const ValueKey('route-stop-1-r1'));
    await tester.ensureVisible(routeTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    final saveLine = find.text('Guardar línea');
    await tester.ensureVisible(saveLine);
    await tester.pumpAndSettle();
    expect(saveLine, findsOneWidget);

    await tester.tap(find.text('Guardar línea'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar línea de favoritos'), findsOneWidget);
    final saved = await favorites.load();
    expect(saved.single.type, FavoriteType.line);
    expect(saved.single.id, 'r1');
    expect(saved.single.name, 'A');

    await tester.tap(find.text('Quitar línea de favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar línea'), findsOneWidget);
    expect(await favorites.load(), isEmpty);
  });
}

Widget _mapApp(
  FakeLocationRepository repository, {
  Duration? mapLoadTimeout,
  RealtimeBusSource? realtimeBusSource,
  Duration realtimePollInterval = const Duration(seconds: 10),
  FavoritesRepository? favoritesRepository,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      locationRepositoryProvider.overrideWith((ref) => repository),
      networkAvailableProvider.overrideWith((ref) => Stream<bool>.value(true)),
      feedUpdateControllerProvider.overrideWith(_OfflineFeedController.new),
      favoritesRepositoryProvider.overrideWithValue(
        favoritesRepository ?? FakeFavoritesRepository(),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      locale: const Locale('es', 'UY'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: MapScreen(
        mapBuilder: (context) => const ColoredBox(color: Colors.transparent),
        mapLoadTimeout: mapLoadTimeout,
        realtimeBusSource: realtimeBusSource,
        realtimePollInterval: realtimePollInterval,
      ),
    ),
  );
}

class _CountingBusSource implements RealtimeBusSource {
  int calls = 0;

  @override
  Future<RealtimeSnapshot> fetch() async {
    calls++;
    return const RealtimeSnapshot(
      positions: [],
      discardedCount: 0,
      discardReasons: {},
    );
  }
}

class _OfflineFeedController extends FeedUpdateController {
  @override
  Future<FeedUpdateState> build() async => const FeedUpdateState(
    phase: FeedUpdatePhase.offline,
    message: 'Prueba sin conexión',
    status: FeedStatus(),
  );
}
