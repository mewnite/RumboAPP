import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';

/// Vía que pasa por los puntos dados (simulación de la red de OSM).
WalkGraph _graphThrough(List<ShapePoint> points) =>
    WalkGraph.fromWays([points]);

int _seconds(int hour, int minute) => hour * 3600 + minute * 60;

ServiceCalendar _dailyCalendar() => ServiceCalendar(
  serviceId: 'daily',
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 12, 31),
  weekdays: {1, 2, 3, 4, 5, 6, 7},
);

void main() {
  test('walking-only itinerary carries the real walk shape', () async {
    final repo = FakeTransitRepository(
      stops: const [],
      routes: const [],
      variants: const [],
      trips: const [],
      times: const [],
      calendars: const [],
    );
    final graph = _graphThrough(const [
      ShapePoint(0, 0, 0),
      ShapePoint(0, .005, 1),
    ]);

    final plans =
        await TransitTripPlanner(
          repo,
          now: () => DateTime(2026, 6, 2, 9),
          walkGraph: graph,
        ).plan(
          TripRequest(
            originLatitude: 0,
            originLongitude: 0,
            destinationLatitude: 0,
            destinationLongitude: .005,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
            config: const PlannerConfig(maximumWalkingMeters: 800),
          ),
        );

    expect(plans, hasLength(1));
    final leg = plans.single.legs.single;
    expect(leg.kind, TripLegKind.walking);
    final expected = graph.shortestPath(0, 0, 0, .005);
    expect(expected, isNotNull);
    expect(leg.shape, isNotNull);
    expect(leg.shape!.points.length, expected!.points.length);
    expect(leg.shape!.points.first.latitude, closeTo(0, .001));
    expect(leg.shape!.points.first.longitude, closeTo(0, .001));
    expect(leg.shape!.points.last.latitude, closeTo(0, .001));
    expect(leg.shape!.points.last.longitude, closeTo(.005, .001));
    expect(leg.distanceMeters, closeTo(expected.lengthMeters, .5));
    expect(leg.approximate, isFalse);
  });

  test('without a graph, the walking leg is approximate with detour factor', () async {
    final repo = FakeTransitRepository(
      stops: const [],
      routes: const [],
      variants: const [],
      trips: const [],
      times: const [],
      calendars: const [],
    );
    final plans = await TransitTripPlanner(
      repo,
      now: () => DateTime(2026, 6, 2, 9),
    ).plan(
      TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .005,
        timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
        config: const PlannerConfig(maximumWalkingMeters: 800),
      ),
    );

    expect(plans, hasLength(1));
    final leg = plans.single.legs.single;
    expect(leg.kind, TripLegKind.walking);
    expect(leg.approximate, isTrue);
    // Distancia estimada: línea recta × factor de desvío (1.3 por defecto).
    expect(leg.distanceMeters, closeTo(555.97 * 1.3, 1));
  });

  test('multimodal plan carries the real shapes: initial walk, transit, final walk', () async {
    final repo = FakeTransitRepository(
      stops: const [
        Stop(id: 'S1', name: 'S1', latitude: 0, longitude: .002),
        Stop(id: 'S2', name: 'S2', latitude: 0, longitude: .010),
      ],
      routes: const [Route(id: 'R1', shortName: '1')],
      variants: const [
        RouteVariant(
          id: 'V1',
          routeId: 'R1',
          directionId: '0',
          destination: 'S2',
        ),
      ],
      trips: const [
        Trip(id: 'T1', routeId: 'R1', serviceId: 'daily', variantId: 'V1'),
      ],
      times: [
        StopTime(
          tripId: 'T1',
          stopId: 'S1',
          arrivalSeconds: _seconds(10, 5),
          departureSeconds: _seconds(10, 5),
          sequence: 1,
        ),
        StopTime(
          tripId: 'T1',
          stopId: 'S2',
          arrivalSeconds: _seconds(10, 40),
          departureSeconds: _seconds(10, 40),
          sequence: 2,
        ),
      ],
      calendars: [_dailyCalendar()],
    );
    final graph = _graphThrough(const [
      ShapePoint(0, 0, 0), // origen del usuario
      ShapePoint(0, .002, 1), // S1: parada de origen
      ShapePoint(0, .010, 2), // S2: parada de destino
      ShapePoint(0, .012, 3), // destino del usuario
    ]);

    final plans =
        await TransitTripPlanner(
          repo,
          now: () => DateTime(2026, 6, 2, 9),
          walkGraph: graph,
        ).plan(
          TripRequest(
            originLatitude: 0,
            originLongitude: 0,
            destinationLatitude: 0,
            destinationLongitude: .012,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
            config: const PlannerConfig(maximumWalkingMeters: 800),
          ),
        );

    expect(plans, isNotEmpty);
    final plan = plans.first;
    expect(plan.legs, hasLength(4)); // camino, espera, transbordo, camino

    final initialWalk = plan.legs[0];
    expect(initialWalk.kind, TripLegKind.walking);
    expect(initialWalk.toStop?.id, 'S1');
    expect(initialWalk.shape, isNotNull);
    expect(initialWalk.shape!.points.first.latitude, closeTo(0, .001));
    expect(initialWalk.shape!.points.first.longitude, closeTo(0, .001));
    expect(initialWalk.shape!.points.last.latitude, closeTo(0, .001));
    expect(initialWalk.shape!.points.last.longitude, closeTo(.002, .001));
    expect(initialWalk.distanceMeters, greaterThan(0));
    expect(initialWalk.approximate, isFalse);

    expect(plan.legs[1].kind, TripLegKind.waiting);
    final transitLeg = plan.legs[2];
    expect(transitLeg.kind, TripLegKind.transit);
    expect(transitLeg.fromStop?.id, 'S1');
    expect(transitLeg.toStop?.id, 'S2');

    final finalWalk = plan.legs[3];
    expect(finalWalk.kind, TripLegKind.walking);
    expect(finalWalk.fromStop?.id, 'S2');
    expect(finalWalk.shape, isNotNull);
    expect(finalWalk.shape!.points.first.latitude, closeTo(0, .001));
    expect(finalWalk.shape!.points.first.longitude, closeTo(.010, .001));
    expect(finalWalk.shape!.points.last.latitude, closeTo(0, .001));
    expect(finalWalk.shape!.points.last.longitude, closeTo(.012, .001));
    expect(finalWalk.distanceMeters, greaterThan(0));
    expect(finalWalk.approximate, isFalse);
  });

  test('multimodal plan carries the real shape on the transfer walk', () {
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
        Stop(id: 'transfer', name: 'Transbordo', latitude: 0, longitude: .01),
        Stop(
          id: 'nearby',
          name: 'Parada cercana',
          latitude: 0,
          longitude: .0109,
        ),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .021),
      ],
      routes: const [
        Route(id: 'first', shortName: '1'),
        Route(id: 'second', shortName: '2'),
      ],
      variants: const [
        RouteVariant(
          id: 'first-variant',
          routeId: 'first',
          directionId: '0',
          destination: 'Transbordo',
        ),
        RouteVariant(
          id: 'second-variant',
          routeId: 'second',
          directionId: '0',
          destination: 'B',
        ),
      ],
      trips: const [
        Trip(
          id: 'first-trip',
          routeId: 'first',
          serviceId: 'daily',
          variantId: 'first-variant',
        ),
        Trip(
          id: 'second-trip',
          routeId: 'second',
          serviceId: 'daily',
          variantId: 'second-variant',
        ),
      ],
      stopTimes: [
        StopTime(
          tripId: 'first-trip',
          stopId: 'A',
          arrivalSeconds: _seconds(10, 5),
          departureSeconds: _seconds(10, 5),
          sequence: 1,
        ),
        StopTime(
          tripId: 'first-trip',
          stopId: 'transfer',
          arrivalSeconds: _seconds(10, 20),
          departureSeconds: _seconds(10, 20),
          sequence: 2,
        ),
        StopTime(
          tripId: 'second-trip',
          stopId: 'nearby',
          arrivalSeconds: _seconds(10, 25),
          departureSeconds: _seconds(10, 25),
          sequence: 1,
        ),
        StopTime(
          tripId: 'second-trip',
          stopId: 'B',
          arrivalSeconds: _seconds(10, 40),
          departureSeconds: _seconds(10, 40),
          sequence: 2,
        ),
      ],
      calendars: [_dailyCalendar()],
    );
    final graph = _graphThrough(const [
      ShapePoint(0, 0, 0),
      ShapePoint(0, .001, 1),
      ShapePoint(0, .01, 2),
      ShapePoint(0, .0109, 3),
      ShapePoint(0, .021, 4),
      ShapePoint(0, .022, 5),
    ]);

    final plans = TransitRouteSearch(walkGraph: graph).findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .022,
        timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );

    expect(plans, hasLength(1));
    final legs = plans.single.legs;
    final walking = legs
        .where((leg) => leg.kind == TripLegKind.walking)
        .toList(growable: false);
    expect(walking, hasLength(3));
    final initialWalk = walking[0];
    final transferWalk = walking[1];
    final finalWalk = walking[2];

    expect(initialWalk.toStop?.id, 'A');
    expect(initialWalk.shape, isNotNull);
    expect(initialWalk.shape!.points.first.longitude, closeTo(0, .001));
    expect(initialWalk.shape!.points.last.longitude, closeTo(.001, .001));

    expect(transferWalk.fromStop?.id, 'transfer');
    expect(transferWalk.toStop?.id, 'nearby');
    expect(transferWalk.shape, isNotNull);
    expect(transferWalk.shape!.points.first.longitude, closeTo(.01, .001));
    expect(transferWalk.shape!.points.last.longitude, closeTo(.0109, .001));
    expect(transferWalk.distanceMeters, closeTo(100, 1));

    expect(finalWalk.fromStop?.id, 'B');
    expect(finalWalk.shape, isNotNull);
    expect(finalWalk.shape!.points.first.longitude, closeTo(.021, .001));
    expect(finalWalk.shape!.points.last.longitude, closeTo(.022, .001));
  });
}
