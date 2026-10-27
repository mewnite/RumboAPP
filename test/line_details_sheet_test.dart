import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/favorites/data/fake_favorites_repository.dart';
import 'package:rumbo/features/favorites/domain/favorite.dart';
import 'package:rumbo/features/favorites/presentation/favorites_controller.dart';
import 'package:rumbo/features/map/data/connectivity_provider.dart';
import 'package:rumbo/features/map/presentation/live_buses_controller.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/line_details_sheet.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

Widget _wrapWithApp({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  const route = Route(
    id: 'route-104',
    shortName: '104',
    longName: 'Costanera / Aduana',
    color: '#1B658D',
  );

  const stop1 = Stop(
    id: 'stop-1',
    code: '1001',
    name: 'Plaza Independencia',
    latitude: -34.906,
    longitude: -56.199,
  );
  const stop2 = Stop(
    id: 'stop-2',
    code: '1002',
    name: 'Intendencia',
    latitude: -34.905,
    longitude: -56.186,
  );
  const stop3 = Stop(
    id: 'stop-3',
    code: '1003',
    name: 'Tres Cruces',
    latitude: -34.894,
    longitude: -56.166,
  );

  const variant1 = RouteVariant(
    id: 'var-104-1',
    routeId: 'route-104',
    directionId: '0',
    destination: 'Costanera',
    externalVariantId: 10401,
  );
  const variant2 = RouteVariant(
    id: 'var-104-2',
    routeId: 'route-104',
    directionId: '1',
    destination: 'Aduana',
    externalVariantId: 10402,
  );

  final today = DateTime.now();
  final calendar = ServiceCalendar(
    serviceId: 'daily',
    startDate: today.subtract(const Duration(days: 30)),
    endDate: today.add(const Duration(days: 30)),
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );

  final trip1 = Trip(
    id: 'trip-1',
    routeId: 'route-104',
    serviceId: 'daily',
    variantId: 'var-104-1',
    startSecs: 36000, // 10:00
  );
  final trip2 = Trip(
    id: 'trip-2',
    routeId: 'route-104',
    serviceId: 'daily',
    variantId: 'var-104-2',
    startSecs: 37800, // 10:30
  );

  final times = [
    const StopTime(
      tripId: 'trip-1',
      stopId: 'stop-1',
      arrivalSeconds: 36000,
      departureSeconds: 36000,
      sequence: 1,
    ),
    const StopTime(
      tripId: 'trip-1',
      stopId: 'stop-2',
      arrivalSeconds: 36600,
      departureSeconds: 36600,
      sequence: 2,
    ),
    const StopTime(
      tripId: 'trip-1',
      stopId: 'stop-3',
      arrivalSeconds: 37200,
      departureSeconds: 37200,
      sequence: 3,
    ),
    const StopTime(
      tripId: 'trip-2',
      stopId: 'stop-3',
      arrivalSeconds: 37800,
      departureSeconds: 37800,
      sequence: 1,
    ),
    const StopTime(
      tripId: 'trip-2',
      stopId: 'stop-1',
      arrivalSeconds: 39000,
      departureSeconds: 39000,
      sequence: 2,
    ),
  ];

  FakeTransitRepository makeRepository() {
    return FakeTransitRepository(
      stops: [stop1, stop2, stop3],
      routes: [route],
      variants: [variant1, variant2],
      trips: [trip1, trip2],
      times: times,
      calendars: [calendar],
    );
  }

  testWidgets(
    'displays route name, variant selector, ordered stops and upcoming departures',
    (tester) async {
      final repository = makeRepository();
      RouteVariant? selectedVariantCallback;
      Stop? selectedStopCallback;

      final container = ProviderContainer(
        overrides: [
          transitRepositoryProvider.overrideWithValue(repository),
          networkAvailableProvider.overrideWith(
            (ref) => Stream<bool>.value(true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithApp(
          container: container,
          child: LineDetailsSheet(
            route: route,
            onVariantSelected: (v) => selectedVariantCallback = v,
            onStopSelected: (s) => selectedStopCallback = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Route header
      expect(find.text('Línea 104'), findsOneWidget);
      expect(find.text('Costanera / Aduana'), findsOneWidget);

      // Variant selector
      expect(find.byKey(const ValueKey('variant-selector')), findsOneWidget);
      expect(find.text('Hacia Costanera'), findsOneWidget);

      // Ordered stops for variant1: stop1, stop2, stop3
      expect(find.text('Plaza Independencia'), findsOneWidget);
      expect(find.text('Intendencia'), findsOneWidget);
      expect(find.text('Tres Cruces'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Tapping a stop triggers callback
      await tester.tap(find.byKey(const ValueKey('line-stop-stop-2')));
      await tester.pumpAndSettle();
      expect(selectedStopCallback?.id, 'stop-2');

      // Change variant using dropdown
      await tester.tap(find.byKey(const ValueKey('variant-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hacia Aduana').last);
      await tester.pumpAndSettle();

      expect(selectedVariantCallback?.id, 'var-104-2');
    },
  );

  testWidgets('toggles favorite line and updates repository', (tester) async {
    final repository = makeRepository();
    final fakeFavorites = FakeFavoritesRepository();

    final container = ProviderContainer(
      overrides: [
        transitRepositoryProvider.overrideWithValue(repository),
        favoritesRepositoryProvider.overrideWithValue(fakeFavorites),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: container,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('favorite-line-route-104'));
    expect(saveButton, findsOneWidget);
    expect(find.text('Guardar línea'), findsOneWidget);

    // Save as favorite
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Quitar línea de favoritos'), findsOneWidget);
    final saved = await fakeFavorites.load();
    expect(saved, hasLength(1));
    expect(saved.first.type, FavoriteType.line);
    expect(saved.first.id, 'route-104');

    // Remove from favorites
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Guardar línea'), findsOneWidget);
    expect(await fakeFavorites.load(), isEmpty);
  });

  testWidgets('shows loading, error, empty and offline states correctly', (
    tester,
  ) async {
    // 1. Loading state
    final loadingContainer = ProviderContainer(
      overrides: [
        lineVariantsProvider(route.id)
            .overrideWith((ref) => Completer<List<RouteVariant>>().future),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
      ],
    );
    addTearDown(loadingContainer.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: loadingContainer,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 2. Error state
    final errorContainer = ProviderContainer(
      overrides: [
        lineVariantsProvider(route.id)
            .overrideWith((ref) => Future.error(Exception('Fallo al cargar'))),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
      ],
    );
    addTearDown(errorContainer.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: errorContainer,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Fallo al cargar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    // 3. Empty state
    final emptyContainer = ProviderContainer(
      overrides: [
        lineVariantsProvider(route.id).overrideWith((ref) async => const []),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
      ],
    );
    addTearDown(emptyContainer.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: emptyContainer,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No se encontraron recorridos para esta línea.'),
      findsOneWidget,
    );

    // 4. Offline state
    final repository = makeRepository();
    final offlineContainer = ProviderContainer(
      overrides: [
        transitRepositoryProvider.overrideWithValue(repository),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(false),
        ),
      ],
    );
    addTearDown(offlineContainer.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: offlineContainer,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Sin conexión. Los horarios y paradas mostrados son los guardados.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('displays live buses count when matching live buses exist', (
    tester,
  ) async {
    final repository = makeRepository();
    final container = ProviderContainer(
      overrides: [
        transitRepositoryProvider.overrideWithValue(repository),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
        liveBusesControllerProvider.overrideWith(
          () => _TestLiveBusesNotifier(
            positions: [
              BusPosition(
                sourceId: 'bus-1',
                companyCode: 1,
                busCode: 101,
                variantId: 10401,
                lineLabel: '104',
                sublineDescription: '',
                destinationCode: '1',
                destinationName: 'Costanera',
                lineTypeCode: 1,
                lineTypeName: '',
                subsystemCode: 1,
                subsystemName: '',
                latitude: -34.905,
                longitude: -56.19,
                speedKmh: 20,
                receivedAt: DateTime.now(),
              ),
              BusPosition(
                sourceId: 'bus-2',
                companyCode: 1,
                busCode: 102,
                variantId: 10401,
                lineLabel: '104',
                sublineDescription: '',
                destinationCode: '1',
                destinationName: 'Costanera',
                lineTypeCode: 1,
                lineTypeName: '',
                subsystemCode: 1,
                subsystemName: '',
                latitude: -34.904,
                longitude: -56.18,
                speedKmh: 15,
                receivedAt: DateTime.now(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrapWithApp(
        container: container,
        child: const LineDetailsSheet(route: route),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 ómnibus en circulación'), findsOneWidget);
  });
}

class _TestLiveBusesNotifier extends LiveBusesController {
  _TestLiveBusesNotifier({required this.positions});

  final List<BusPosition> positions;

  @override
  LiveBusesState build() => LiveBusesState(positions: positions);
}
