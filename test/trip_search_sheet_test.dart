import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
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
    DateTime? plannedDeparture;

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
            findPlans: (origin, selectedDestination, departureTime) async {
              plannedOrigin = origin;
              plannedDestination = selectedDestination;
              plannedDeparture = departureTime;
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
    expect(plannedDeparture, isNotNull);
    expect(
      DateTime.now().difference(plannedDeparture!).inSeconds.abs(),
      lessThan(60),
    );
    expect(find.textContaining('35 min'), findsOneWidget);
    expect(find.text('522'), findsOneWidget);
    expect(find.textContaining('horarios programados'), findsOneWidget);
  });

  testWidgets('plans with the selected departure date and time', (
    tester,
  ) async {
    const destination = Stop(
      id: 'destination',
      name: 'Nuevo Centro',
      latitude: -34.85,
      longitude: -56.17,
    );
    DateTime? plannedDeparture;
    DateTime? pickedInitialDate;
    TimeOfDay? pickedInitialTime;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            departureDatePicker:
                (context, initialDate, firstDate, lastDate) async {
                  pickedInitialDate = initialDate;
                  return DateTime(2026, 10, 28);
                },
            departureTimePicker: (context, initialTime) async {
              pickedInitialTime = initialTime;
              return const TimeOfDay(hour: 18, minute: 30);
            },
            searchStops: (_) async => [destination],
            searchPlaces: (_) async => const [],
            findPlans: (origin, selectedDestination, departureTime) async {
              plannedDeparture = departureTime;
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
      find.byKey(const ValueKey('trip-departure-date')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-date')));
    await tester.pumpAndSettle();
    expect(pickedInitialDate, isNotNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-time')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-time')));
    await tester.pumpAndSettle();
    expect(pickedInitialTime, isNotNull);
    expect(find.text('18:30'), findsOneWidget);

    await tester.ensureVisible(find.text('Buscar ómnibus'));
    await tester.tap(find.text('Buscar ómnibus'));
    await tester.pumpAndSettle();

    expect(plannedDeparture, DateTime(2026, 10, 28, 18, 30));
  });

  testWidgets('opens the material departure date and time pickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            searchStops: (_) async => const [],
            searchPlaces: (_) async => const [],
            findPlans: (origin, destination, departureTime) async => const [],
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-date')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('trip-departure-time')),
    );
    await tester.tap(find.byKey(const ValueKey('trip-departure-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
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
            findPlans: (origin, selectedDestination, departureTime) async {
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

    expect(find.text('Salida · Mi ubicación · 12:00'), findsOneWidget);
    expect(find.text('Caminá 200 m · 3 min'), findsOneWidget);
    expect(find.text('Mi ubicación → Tres Cruces'), findsOneWidget);
    expect(find.text('Esperá en Tres Cruces · 5 min'), findsOneWidget);
    expect(find.text('Ómnibus 522 hacia Ciudad Vieja'), findsOneWidget);
    expect(find.text('Transbordo en Centro · 5 min'), findsOneWidget);
    expect(find.text('Ómnibus 103'), findsOneWidget);
    expect(find.text('Llegada · Plaza Independencia · 12:45'), findsOneWidget);
    expect(find.text('Plaza → Plaza Independencia'), findsOneWidget);
    expect(find.textContaining('no es navegación guiada'), findsOneWidget);

    await tester.ensureVisible(find.text('Cambiar viaje'));
    await tester.tap(find.text('Cambiar viaje'));
    await tester.ensureVisible(find.byTooltip('Cerrar recorrido'));
    await tester.tap(find.byTooltip('Cerrar recorrido'));
    expect(changedTrip, isTrue);
    expect(closedTrip, isTrue);
  });

  testWidgets('sends an address to place search only after explicit action', (
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
            findPlans: (origin, destination, departureTime) async => const [],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Av. 18 de Julio 1234');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(placeSearchCount, 0);

    await tester.tap(find.text('Buscar lugares o direcciones'));
    await tester.pumpAndSettle();
    expect(placeSearchCount, 1);
    expect(find.text('Av. 18 de Julio 1234, Montevideo'), findsOneWidget);
    expect(
      find.textContaining('se envía el texto escrito al servicio remoto'),
      findsOneWidget,
    );
  });

  testWidgets('hides remote search when it is disabled', (tester) async {
    var localSearchCount = 0;
    var remoteSearchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripSearchSheet(
            hasCurrentLocation: true,
            searchStops: (_) async {
              localSearchCount++;
              return const [];
            },
            searchPlaces: (_) async {
              remoteSearchCount++;
              return const [];
            },
            findPlans: (origin, destination, departureTime) async => const [],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'Centro');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(localSearchCount, 1);
    expect(remoteSearchCount, 0);
    expect(find.text('Buscar lugares o direcciones'), findsNothing);
  });
}
