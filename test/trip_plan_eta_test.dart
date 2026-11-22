import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rumbo/core/widgets/rumbo_components.dart';
import 'package:rumbo/features/map/presentation/map_screen.dart'
    show tripPlanSheetMinimumExtent;
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/presentation/transit_repository_provider.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/presentation/trip_plan_details.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

const stop = Stop(
  id: 's1',
  name: 'Parada de subida',
  latitude: -34.89,
  longitude: -56.1,
);
const route = Route(id: 'r1', shortName: '522');
const variant = RouteVariant(
  id: 'v1',
  routeId: 'r1',
  directionId: '0',
  destination: 'Centro',
  externalVariantId: 5221,
);
const shape = Shape(
  id: 's1',
  points: [ShapePoint(-34.9, -56.1, 0), ShapePoint(-34.88, -56.1, 1)],
);

void main() {
  testWidgets('compact first ETA fits at minimum height on a 360x640 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    expect(tripPlanSheetMinimumExtent, inInclusiveRange(0.4, 0.45));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = _plan(DateTime.now(), walkingApproximate: false);
    final source = _FakeOfficialSource([
      const OfficialBusArrival(
        busId: 55,
        lineVariantId: 5221,
        line: '522',
        etaSeconds: 600,
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialUpcomingBusArrivalsSourceFactoryProvider.overrideWithValue(
            () => source,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DraggableScrollableSheet(
              initialChildSize: tripPlanSheetMinimumExtent,
              minChildSize: tripPlanSheetMinimumExtent,
              maxChildSize: 0.68,
              builder: (context, scrollController) => Material(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    const RumboSheetHandle(label: 'Tu recorrido'),
                    const SizedBox(height: 8),
                    TripPlanDetails(
                      plan: plan,
                      originName: 'Origen',
                      destinationName: 'Destino',
                      onChangeTrip: () {},
                      onCloseTrip: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final eta = find.text('Llega en 10 min · Oficial');
    expect(eta, findsOneWidget);
    expect(
      tester.getRect(eta).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ListView)).bottom),
    );
    expect(source.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.closed, isTrue);
  });

  testWidgets('compact first ETA remains visible on a taller screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _FakeOfficialSource([
      const OfficialBusArrival(
        busId: 55,
        lineVariantId: 5221,
        line: '522',
        etaSeconds: 600,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialUpcomingBusArrivalsSourceFactoryProvider.overrideWithValue(
            () => source,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DraggableScrollableSheet(
              initialChildSize: tripPlanSheetMinimumExtent,
              minChildSize: tripPlanSheetMinimumExtent,
              maxChildSize: 0.68,
              builder: (context, scrollController) => Material(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    const RumboSheetHandle(label: 'Tu recorrido'),
                    const SizedBox(height: 8),
                    TripPlanDetails(
                      plan: _plan(DateTime.now(), walkingApproximate: false),
                      originName: 'Origen',
                      destinationName: 'Destino',
                      onChangeTrip: () {},
                      onCloseTrip: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Llega en 10 min · Oficial'), findsOneWidget);
    final etaCard = tester.getRect(
      find.byKey(const ValueKey('trip-first-bus-eta')),
    );
    final viewport = tester.getRect(find.byType(ListView));
    expect(etaCard.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.closed, isTrue);
  });

  testWidgets('warns when the first official bus beats the real walk', (
    tester,
  ) async {
    final now = DateTime.now();
    final source = _FakeOfficialSource([
      const OfficialBusArrival(
        busId: 55,
        lineVariantId: 5221,
        line: '522',
        etaSeconds: 240,
      ),
      const OfficialBusArrival(
        busId: 56,
        lineVariantId: 5221,
        line: '522',
        etaSeconds: 720,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialUpcomingBusArrivalsSourceFactoryProvider.overrideWithValue(
            () => source,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TripPlanDetails(
                plan: _plan(now, walkingApproximate: false),
                originName: 'Origen',
                destinationName: 'Destino',
                onChangeTrip: () {},
                onCloseTrip: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Llega en 4 min · Oficial'), findsOneWidget);
    expect(find.textContaining('No llegás a tiempo'), findsOneWidget);
    expect(
      find.text('Siguiente ómnibus según STM: llega en 12 min · Oficial'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.closed, isTrue);
  });

  test(
    'alerts when GPS arrival leaves less than the real walk plus one minute',
    () {
      final now = DateTime(2026, 11, 22, 12);
      final plan = _plan(now, walkingApproximate: false);
      final estimate = estimateTripLegEta(
        plan: plan,
        legIndex: 1,
        livePositions: [_bus(now)],
        shapes: const {'v1': shape},
        now: now,
      );

      expect(estimate.fromGps, isTrue);
      expect(
        estimate.minMinutes,
        lessThanOrEqualTo(estimate.walkingMinutes + 1),
      );
      expect(estimate.walkingMinutes, 5);
      expect(estimate.missedBoarding, isTrue);
    },
  );

  test('does not make a late-arrival claim when the walk is approximate', () {
    final now = DateTime(2026, 11, 22, 12);
    final plan = _plan(now, walkingApproximate: true);
    final estimate = estimateTripLegEta(
      plan: plan,
      legIndex: 1,
      livePositions: [_bus(now)],
      shapes: const {'v1': shape},
      now: now,
    );

    expect(estimate.fromGps, isTrue);
    expect(estimate.missedBoarding, isFalse);
  });

  test('uses the scheduled time when no matched GPS bus is available', () {
    final now = DateTime(2026, 11, 22, 12);
    final estimate = estimateTripLegEta(
      plan: _plan(now, walkingApproximate: false),
      legIndex: 1,
      livePositions: const [],
      shapes: const {'v1': shape},
      now: now,
    );

    expect(estimate.fromGps, isFalse);
    expect(estimate.minMinutes, 8);
    expect(estimate.maxMinutes, 8);
    expect(estimate.missedBoarding, isFalse);
  });

  test('official ETA takes priority over GPS and schedule', () {
    final now = DateTime(2026, 11, 22, 12);
    final estimate = estimateTripLegEta(
      plan: _plan(now, walkingApproximate: false),
      legIndex: 1,
      livePositions: [_bus(now)],
      shapes: const {'v1': shape},
      now: now,
      officialEtaSeconds: 180,
      nextOfficialEtaSeconds: 540,
    );

    expect(estimate.source, TripEtaSource.official);
    expect(estimate.fromGps, isFalse);
    expect(estimate.minMinutes, 3);
    expect(estimate.nextOfficialMinutes, 9);
    expect(estimate.missedBoarding, isTrue);
  });
}

class _FakeOfficialSource implements OfficialUpcomingBusArrivalsSource {
  _FakeOfficialSource(this.arrivals);

  final List<OfficialBusArrival> arrivals;
  final List<(String, Set<String>, int)> requests = [];
  bool closed = false;

  @override
  Future<List<OfficialBusArrival>> upcomingForStop({
    required String stopId,
    required Set<String> lines,
    int amountPerLine = 1,
  }) async {
    requests.add((stopId, lines, amountPerLine));
    return arrivals;
  }

  @override
  void close() => closed = true;
}

TripPlan _plan(DateTime now, {required bool walkingApproximate}) {
  final walkArrival = now.add(const Duration(minutes: 5));
  return TripPlan(
    requestedDeparture: now,
    arrivalTime: now.add(const Duration(minutes: 40)),
    legs: [
      TripLeg(
        kind: TripLegKind.walking,
        departureTime: now,
        arrivalTime: walkArrival,
        distanceMeters: 400,
        toStop: stop,
        approximate: walkingApproximate,
      ),
      TripLeg(
        kind: TripLegKind.transit,
        departureTime: now.add(const Duration(minutes: 8)),
        arrivalTime: now.add(const Duration(minutes: 40)),
        fromStop: stop,
        toStop: stop,
        route: route,
        variant: variant,
      ),
    ],
    totalWalkingMeters: 400,
    transferCount: 0,
  );
}

BusPosition _bus(DateTime now) => BusPosition(
  sourceId: 'bus1',
  companyCode: 1,
  busCode: 1,
  variantId: 5221,
  lineLabel: '522',
  sublineDescription: '',
  destinationCode: '',
  destinationName: 'Centro',
  lineTypeCode: 1,
  lineTypeName: '',
  subsystemCode: 1,
  subsystemName: '',
  latitude: -34.895,
  longitude: -56.1,
  speedKmh: 36,
  receivedAt: now,
);
