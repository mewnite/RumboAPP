import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/presentation/trip_plan_details.dart';
import 'package:rumbo/features/trip_planner/presentation/trip_search_sheet.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('searches a destination and displays scheduled trip options', (
    tester,
  ) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    final departure = DateTime(2026, 10, 24, 12);
    var searchQuery = '';
    TripEndpoint? plannedOrigin;
    TripEndpoint? plannedDestination;
    TripTiming? plannedTiming;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            searchStops: (query) async {
              searchQuery = query;
              return [destination];
            },
            searchPlaces: (query) async => [
              TripEndpoint(name: query, latitude: -34.9, longitude: -56.2),
            ],
            findPlans: (origin, selectedDestination, timing, config) async {
              plannedOrigin = origin;
              plannedDestination = selectedDestination;
              plannedTiming = timing;
              return [
                TripPlan(
                  requestedDeparture: departure,
                  arrivalTime: departure.add(const Duration(minutes: 35)),
                  legs: [
                    TripLeg(
                      kind: TripLegKind.transit,
                      departureTime: departure,
                      arrivalTime: departure.add(const Duration(minutes: 30)),
                      route: const Route(id: 'r1', shortName: '522'),
                      fromStop: const Stop(
                        id: 'origin',
                        name: 'Tres Cruces',
                        latitude: -34.89,
                        longitude: -56.16,
                      ),
                      toStop: destination,
                    ),
                  ],
                  totalWalkingMeters: 0,
                  transferCount: 0,
                ),
              ];
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(searchQuery, 'Nuevo');
    expect(find.text('Nuevo Centro'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(plannedOrigin, isNull);
    expect(plannedDestination?.stop, destination);
    expect(plannedTiming?.mode, TripTimingMode.departNow);
    expect(plannedTiming?.dateTime, isNull);
    expect(find.textContaining('35 min'), findsOneWidget);
    expect(find.text('522'), findsOneWidget);
    expect(find.textContaining('horarios programados'), findsOneWidget);
  });

  testWidgets('plans with a future departure day and time', (tester) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    final fixedNow = DateTime(2026, 10, 24, 12);
    TripTiming? plannedTiming;
    TimeOfDay? pickedInitialTime;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            now: () => fixedNow,
            departureTimePicker: (context, initialTime) async {
              pickedInitialTime = initialTime;
              return const TimeOfDay(hour: 18, minute: 30);
            },
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            findPlans: (origin, selectedDestination, timing, config) async {
              plannedTiming = timing;
              return const [];
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-timing-depart-at')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-timing-depart-at')));
    await tester.pumpAndSettle();
    expect(find.text('Salida: Hoy · 12:10'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-time')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-time')));
    await tester.pumpAndSettle();
    expect(pickedInitialTime, const TimeOfDay(hour: 12, minute: 10));
    expect(find.text('18:30'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trip-day-tomorrow')));
    await tester.pumpAndSettle();
    expect(find.text('Salida: Mañana · 18:30'), findsOneWidget);

    await tester.ensureVisible(find.text('Buscar ómnibus'));
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(plannedTiming?.mode, TripTimingMode.departAt);
    expect(plannedTiming?.dateTime, DateTime(2026, 10, 25, 18, 30));
  });

  testWidgets('opens a 24-hour time picker and builds an arrival timing', (
    tester,
  ) async {
    final fixedNow = DateTime(2026, 10, 24, 12);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            now: () => fixedNow,
            searchStops: (_) async => const [],
            searchPlaces: (_) async => const [],
            findPlans: (origin, destination, timing, config) async => const [],
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-timing-arrive-by')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-timing-arrive-by')));
    await tester.pumpAndSettle();
    expect(find.text('Llegada: Hoy · 12:10'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-time')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('shows the arrival-by empty state when no trip arrives in time', (
    tester,
  ) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    final fixedNow = DateTime(2026, 10, 24, 8);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            now: () => fixedNow,
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            findPlans: (origin, selectedDestination, timing, config) async =>
                const [],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-timing-arrive-by')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-timing-arrive-by')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Buscar ómnibus'));
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(find.text('No hay viajes que lleguen a esa hora'), findsOneWidget);
    expect(
      find.text('Probá ampliar la caminata máxima o cambiar la hora.'),
      findsOneWidget,
    );
    expect(find.text('Ampliar caminata'), findsOneWidget);
    expect(find.text('Cambiar hora'), findsOneWidget);
  });

  testWidgets('warns and skips the search when the time is in the past', (
    tester,
  ) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    final fixedNow = DateTime(2026, 10, 24, 12);
    var planSearches = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            now: () => fixedNow,
            departureTimePicker: (context, initialTime) async =>
                const TimeOfDay(hour: 8, minute: 0),
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            findPlans: (origin, selectedDestination, timing, config) async {
              planSearches++;
              return const [];
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-timing-depart-at')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-timing-depart-at')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-time')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-time')));
    await tester.pumpAndSettle();

    expect(find.text('Salida: Hoy · 08:00'), findsOneWidget);
    expect(
      find.text('Esa hora ya pasó. Elegí una hora futura.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Buscar ómnibus'));
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(planSearches, 0);
    expect(
      find.text('Esa hora ya pasó. Elegí una hora futura.'),
      findsOneWidget,
    );
  });

  testWidgets('notifies when the user selects a trip option', (tester) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    final selectedPlans = <TripPlan>[];
    final departure = DateTime(2026, 10, 24, 12);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            onPlanSelected: (plan, origin, selectedDestination) {
              selectedPlans.add(plan);
            },
            findPlans: (origin, selectedDestination, timing, config) async {
              return [
                TripPlan(
                  requestedDeparture: departure,
                  arrivalTime: departure.add(const Duration(minutes: 35)),
                  legs: [
                    TripLeg(
                      kind: TripLegKind.transit,
                      departureTime: departure,
                      arrivalTime: departure.add(const Duration(minutes: 30)),
                      route: const Route(id: 'r1', shortName: '522'),
                      fromStop: const Stop(
                        id: 'origin',
                        name: 'Tres Cruces',
                        latitude: -34.89,
                        longitude: -56.16,
                      ),
                      toStop: destination,
                    ),
                  ],
                  totalWalkingMeters: 0,
                  transferCount: 0,
                ),
              ];
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('35 min'));
    await tester.tap(find.textContaining('35 min'));
    await tester.pumpAndSettle();

    expect(selectedPlans, hasLength(1));
    expect(selectedPlans.single.legs.single.route?.shortName, '522');
  });

  testWidgets('shows the selected trip as ordered itinerary steps', (
    tester,
  ) async {
    final departure = DateTime(2026, 10, 24, 12);
    const firstStop = Stop(
      id: 'first',
      name: 'Tres Cruces',
      latitude: -34.89,
      longitude: -56.16,
    );
    const transferStop = Stop(
      id: 'transfer',
      name: 'Centro',
      latitude: -34.9,
      longitude: -56.19,
    );
    const finalStop = Stop(
      id: 'final',
      name: 'Plaza',
      latitude: -34.91,
      longitude: -56.2,
    );
    var changedTrip = false;
    var closedTrip = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripPlanDetails(
              plan: TripPlan(
                requestedDeparture: departure,
                arrivalTime: departure.add(const Duration(minutes: 45)),
                legs: [
                  TripLeg(
                    kind: TripLegKind.walking,
                    departureTime: departure,
                    arrivalTime: departure.add(const Duration(minutes: 3)),
                    distanceMeters: 200,
                    fromLatitude: -34.891,
                    fromLongitude: -56.161,
                    toStop: firstStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.waiting,
                    departureTime: departure.add(const Duration(minutes: 3)),
                    arrivalTime: departure.add(const Duration(minutes: 8)),
                    toStop: firstStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.transit,
                    departureTime: departure.add(const Duration(minutes: 8)),
                    arrivalTime: departure.add(const Duration(minutes: 25)),
                    route: const Route(id: 'r1', shortName: '522'),
                    headsign: 'Ciudad Vieja',
                    fromStop: firstStop,
                    toStop: transferStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.waiting,
                    departureTime: departure.add(const Duration(minutes: 25)),
                    arrivalTime: departure.add(const Duration(minutes: 30)),
                    fromStop: transferStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.transit,
                    departureTime: departure.add(const Duration(minutes: 30)),
                    arrivalTime: departure.add(const Duration(minutes: 40)),
                    route: const Route(id: 'r2', shortName: '103'),
                    fromStop: transferStop,
                    toStop: finalStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.walking,
                    departureTime: departure.add(const Duration(minutes: 40)),
                    arrivalTime: departure.add(const Duration(minutes: 45)),
                    distanceMeters: 350,
                    fromStop: finalStop,
                    toLatitude: -34.912,
                    toLongitude: -56.201,
                  ),
                ],
                totalWalkingMeters: 550,
                transferCount: 1,
              ),
              originName: 'Mi ubicación',
              destinationName: 'Plaza Independencia',
              onChangeTrip: () => changedTrip = true,
              onCloseTrip: () => closedTrip = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tu recorrido'), findsOneWidget);
    expect(find.text('12:00–12:45'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('8 min de caminata'), findsOneWidget);
    expect(find.text('1 transbordo'), findsOneWidget);

    expect(find.text('Salida'), findsOneWidget);
    expect(find.text('Mi ubicación'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);

    expect(find.text('Caminar 200 m'), findsOneWidget);
    expect(find.text('Mi ubicación → Tres Cruces'), findsOneWidget);
    expect(find.text('12:03 · estimado'), findsOneWidget);

    expect(find.text('Tomar línea 522 en Tres Cruces'), findsOneWidget);
    expect(find.text('Hacia Ciudad Vieja'), findsOneWidget);
    expect(find.text('12:08 · estimado'), findsOneWidget);

    expect(find.text('Bajar en Centro'), findsOneWidget);
    expect(find.text('12:25 · estimado'), findsOneWidget);

    expect(find.text('Tomar línea 103 en Centro'), findsOneWidget);
    expect(find.text('12:30 · estimado'), findsOneWidget);

    expect(find.text('Bajar en Plaza'), findsOneWidget);
    expect(find.text('12:40 · estimado'), findsOneWidget);

    expect(find.text('Caminar 350 m'), findsOneWidget);
    expect(find.text('Plaza → Plaza Independencia'), findsOneWidget);
    expect(find.text('12:45 · estimado'), findsNWidgets(2));

    expect(find.text('Llegada'), findsOneWidget);
    expect(find.text('Plaza Independencia'), findsOneWidget);
    expect(find.text('Caminata total: 550 m'), findsOneWidget);
    expect(find.text('Caminata aproximada, en línea recta.'), findsOneWidget);
    expect(find.textContaining('sin ETA en vivo'), findsOneWidget);
    expect(find.textContaining('no es navegación guiada'), findsOneWidget);

    expect(
      tester.getTopLeft(find.text('Salida')).dy,
      lessThan(tester.getTopLeft(find.text('Caminar 200 m')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Caminar 200 m')).dy,
      lessThan(
        tester.getTopLeft(find.text('Tomar línea 522 en Tres Cruces')).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Tomar línea 522 en Tres Cruces')).dy,
      lessThan(tester.getTopLeft(find.text('Bajar en Centro')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Bajar en Centro')).dy,
      lessThan(tester.getTopLeft(find.text('Tomar línea 103 en Centro')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Tomar línea 103 en Centro')).dy,
      lessThan(tester.getTopLeft(find.text('Llegada')).dy),
    );

    await tester.ensureVisible(find.text('Cambiar viaje'));
    await tester.tap(find.text('Cambiar viaje'));
    await tester.ensureVisible(find.byTooltip('Cerrar recorrido'));
    await tester.tap(find.byTooltip('Cerrar recorrido'));
    expect(changedTrip, isTrue);
    expect(closedTrip, isTrue);
  });

  testWidgets('shows all scheduled data on the result card', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    const transferStop = Stop(
      id: 'transfer',
      name: 'Centro',
      latitude: -34.9,
      longitude: -56.19,
    );
    final departure = DateTime(2026, 10, 24, 12);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            now: () => DateTime(2026, 10, 24, 12),
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            findPlans: (origin, selectedDestination, timing, config) async => [
              TripPlan(
                requestedDeparture: departure,
                arrivalTime: departure.add(const Duration(minutes: 45)),
                legs: [
                  TripLeg(
                    kind: TripLegKind.walking,
                    departureTime: departure,
                    arrivalTime: departure.add(const Duration(minutes: 3)),
                    distanceMeters: 200,
                    fromLatitude: -34.891,
                    fromLongitude: -56.161,
                    toStop: const Stop(
                      id: 'first',
                      name: 'Tres Cruces',
                      latitude: -34.89,
                      longitude: -56.16,
                    ),
                  ),
                  TripLeg(
                    kind: TripLegKind.transit,
                    departureTime: departure.add(const Duration(minutes: 5)),
                    arrivalTime: departure.add(const Duration(minutes: 25)),
                    route: const Route(id: 'r1', shortName: '522'),
                    fromStop: const Stop(
                      id: 'first',
                      name: 'Tres Cruces',
                      latitude: -34.89,
                      longitude: -56.16,
                    ),
                    toStop: transferStop,
                  ),
                  TripLeg(
                    kind: TripLegKind.transit,
                    departureTime: departure.add(const Duration(minutes: 30)),
                    arrivalTime: departure.add(const Duration(minutes: 45)),
                    route: const Route(id: 'r2', shortName: '103'),
                    fromStop: transferStop,
                    toStop: destination,
                  ),
                ],
                totalWalkingMeters: 200,
                transferCount: 1,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Nuevo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(find.text('12:00–12:45'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('522'), findsOneWidget);
    expect(find.text('103'), findsOneWidget);
    expect(find.text('3 min de caminata'), findsOneWidget);
    expect(find.text('1 transbordo'), findsOneWidget);
    expect(find.text('Horarios programados'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Salida 12:00, llegada 12:45. 45 min de viaje, 3 min de caminata, '
        '1 transbordo. Líneas: 522, 103. Horarios programados.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'sorts results locally and re-searches with a new walking limit',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const destination = Stop(
        id: 'destination',
        name: 'Nuevo Centro',
        latitude: -34.85,
        longitude: -56.17,
      );
      final departure = DateTime(2026, 10, 24, 12);
      PlannerConfig? plannedConfig;

      TripPlan plan({
        required String route,
        required int durationMinutes,
        required double walking,
      }) => TripPlan(
        requestedDeparture: departure,
        arrivalTime: departure.add(Duration(minutes: durationMinutes)),
        legs: [
          TripLeg(
            kind: TripLegKind.transit,
            departureTime: departure,
            arrivalTime: departure.add(Duration(minutes: durationMinutes)),
            route: Route(id: route, shortName: route),
            fromStop: const Stop(
              id: 'origin',
              name: 'Tres Cruces',
              latitude: -34.89,
              longitude: -56.16,
            ),
            toStop: destination,
          ),
        ],
        totalWalkingMeters: walking,
        transferCount: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TripSearchSheet(
              hasCurrentLocation: true,
              now: () => DateTime(2026, 10, 24, 12),
              searchStops: (_) async => [destination],
              searchPlaces: (_) async => const [],
              findPlans: (origin, selectedDestination, timing, config) async {
                plannedConfig = config;
                return [
                  plan(route: 'RÁPIDA', durationMinutes: 30, walking: 500),
                  plan(route: 'CORTA', durationMinutes: 45, walking: 100),
                ];
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).last, 'Nuevo');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('trip-endpoint--34.85:-56.17')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('trip-walking-1200')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buscar ómnibus'));
      await tester.pumpAndSettle();

      expect(plannedConfig?.maximumWalkingMeters, 1200);
      expect(find.byKey(const ValueKey('trip-sort-fastest')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('RÁPIDA')).dy,
        lessThan(tester.getTopLeft(find.text('CORTA')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('trip-sort-least-walking')));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('CORTA')).dy,
        lessThan(tester.getTopLeft(find.text('RÁPIDA')).dy),
      );
    },
  );

  testWidgets('searches places only after the user requests it', (
    tester,
  ) async {
    var placeSearchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            remotePlaceSearchEnabled: true,
            searchStops: (_) async => const [],
            searchPlaces: (query) async {
              placeSearchCount++;
              expect(query, 'Av. 18 de Julio 1234');
              return const [
                TripEndpoint(
                  name: 'Av. 18 de Julio 1234, Montevideo',
                  latitude: -34.906,
                  longitude: -56.191,
                ),
              ];
            },
            findPlans: (origin, destination, timing, config) async => const [],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Av. 18 de Julio 1234');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(placeSearchCount, 0);
    await tester.tap(find.text('Buscar lugares en línea'));
    await tester.pumpAndSettle();
    expect(placeSearchCount, 1);
    expect(find.text('Buscar lugares o direcciones'), findsNothing);
    expect(find.text('Av. 18 de Julio 1234, Montevideo'), findsOneWidget);
    expect(
      find.textContaining('El texto se envía al servicio en línea'),
      findsOneWidget,
    );
  });

  testWidgets('does not ask consent or search online while typing', (
    tester,
  ) async {
    var localSearchCount = 0;
    var remoteSearchCount = 0;
    var consentRequestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            onRemotePlaceSearchConsentRequested: () async {
              consentRequestCount++;
              return false;
            },
            searchStops: (_) async {
              localSearchCount++;
              return const [];
            },
            searchPlaces: (_) async {
              remoteSearchCount++;
              return const [];
            },
            findPlans: (origin, destination, timing, config) async => const [],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Centro');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(localSearchCount, 1);
    expect(remoteSearchCount, 0);
    expect(consentRequestCount, 0);
    await tester.tap(find.text('Buscar lugares en línea'));
    await tester.pumpAndSettle();
    expect(consentRequestCount, 1);
    expect(find.text('Buscar lugares o direcciones'), findsNothing);
    expect(remoteSearchCount, 0);
  });

  testWidgets('runs the combined search after explicit request and consent', (
    tester,
  ) async {
    var remoteSearchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            onRemotePlaceSearchConsentRequested: () async => true,
            searchStops: (_) async => const [],
            searchPlaces: (query) async {
              remoteSearchCount++;
              return [
                TripEndpoint(name: query, latitude: -34.9, longitude: -56.2),
              ];
            },
            findPlans: (origin, destination, timing, config) async => const [],
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      'Shopping Nuevo Centro',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(remoteSearchCount, 0);
    await tester.tap(find.text('Buscar lugares en línea'));
    await tester.pumpAndSettle();
    expect(remoteSearchCount, 1);
    expect(find.text('Shopping Nuevo Centro'), findsWidgets);
    expect(find.text('Buscar lugares o direcciones'), findsNothing);
  });
}
