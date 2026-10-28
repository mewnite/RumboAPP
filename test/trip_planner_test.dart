import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';

void main() {
  final travelDay = DateTime(2026, 6, 2);
  final dailyCalendar = ServiceCalendar(
    serviceId: 'daily',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 12, 31),
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );

  test('ranks a faster one-transfer route ahead of a slower direct route', () async {
    final repo = _CountingTransitRepository(
      stops: const [
        Stop(id: 'origin-stop', name: 'Origen', latitude: 0, longitude: .001),
        Stop(
          id: 'transfer-stop',
          name: 'Transbordo',
          latitude: 0,
          longitude: .01,
        ),
        Stop(
          id: 'destination-stop',
          name: 'Destino',
          latitude: 0,
          longitude: .021,
        ),
      ],
      routes: const [
        Route(id: 'direct-route', shortName: 'D'),
        Route(id: 'first-route', shortName: '1'),
        Route(id: 'second-route', shortName: '2'),
      ],
      variants: const [
        RouteVariant(
          id: 'direct-variant',
          routeId: 'direct-route',
          directionId: '0',
          destination: 'Destino',
        ),
        RouteVariant(
          id: 'first-variant',
          routeId: 'first-route',
          directionId: '0',
          destination: 'Transbordo',
        ),
        RouteVariant(
          id: 'second-variant',
          routeId: 'second-route',
          directionId: '0',
          destination: 'Destino',
        ),
      ],
      trips: const [
        Trip(
          id: 'direct-trip',
          routeId: 'direct-route',
          serviceId: 'daily',
          variantId: 'direct-variant',
          headsign: 'Destino',
        ),
        Trip(
          id: 'first-trip',
          routeId: 'first-route',
          serviceId: 'daily',
          variantId: 'first-variant',
          headsign: 'Transbordo',
        ),
        Trip(
          id: 'second-trip',
          routeId: 'second-route',
          serviceId: 'daily',
          variantId: 'second-variant',
          headsign: 'Destino',
        ),
      ],
      times: [
        StopTime(
          tripId: 'direct-trip',
          stopId: 'origin-stop',
          arrivalSeconds: _seconds(10, 15),
          departureSeconds: _seconds(10, 15),
          sequence: 1,
        ),
        StopTime(
          tripId: 'direct-trip',
          stopId: 'destination-stop',
          arrivalSeconds: _seconds(10, 50),
          departureSeconds: _seconds(10, 50),
          sequence: 2,
        ),
        StopTime(
          tripId: 'first-trip',
          stopId: 'origin-stop',
          arrivalSeconds: _seconds(10, 5),
          departureSeconds: _seconds(10, 5),
          sequence: 1,
        ),
        StopTime(
          tripId: 'first-trip',
          stopId: 'transfer-stop',
          arrivalSeconds: _seconds(10, 20),
          departureSeconds: _seconds(10, 20),
          sequence: 2,
        ),
        StopTime(
          tripId: 'second-trip',
          stopId: 'transfer-stop',
          arrivalSeconds: _seconds(10, 25),
          departureSeconds: _seconds(10, 25),
          sequence: 1,
        ),
        StopTime(
          tripId: 'second-trip',
          stopId: 'destination-stop',
          arrivalSeconds: _seconds(10, 40),
          departureSeconds: _seconds(10, 40),
          sequence: 2,
        ),
      ],
      calendars: [dailyCalendar],
    );

    final plans =
        await TransitTripPlanner(repo, now: () => DateTime(2026, 6, 2, 9)).plan(
          TripRequest(
            originLatitude: 0,
            originLongitude: 0,
            destinationLatitude: 0,
            destinationLongitude: .02,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
            config: const PlannerConfig(maximumWalkingMeters: 500),
          ),
        );

    expect(repo.nearbyStopCalls, 2);
    expect(repo.scheduleStopRequests, hasLength(1));
    expect(repo.scheduleStopRequests.single, {
      'origin-stop',
      'destination-stop',
    });
    expect(repo.scheduleWindows, hasLength(1));
    expect(repo.scheduleWindows.single.windowStart, DateTime(2026, 6, 2, 10));
    expect(repo.scheduleWindows.single.windowEnd, DateTime(2026, 6, 2, 13, 45));
    expect(
      plans,
      hasLength(2),
      reason: plans
          .map(
            (plan) =>
                '${plan.transferCount}:${plan.legs.where((leg) => leg.kind == TripLegKind.transit).map((leg) => '${leg.route?.id}@${leg.departureTime}').join(',')}',
          )
          .join(' | '),
    );
    expect(plans.first.arrivalTime, DateTime(2026, 6, 2, 10, 41, 49));
    expect(plans.first.transferCount, 1);
    expect(
      plans.first.legs.where((leg) => leg.kind == TripLegKind.transit),
      hasLength(2),
    );
    expect(plans.first.timeAccuracy, TripTimeAccuracy.scheduled);
    expect(plans.last.transferCount, 0);
  });

  test(
    'limits schedule loading to the fifteen closest endpoint stops',
    () async {
      final stops = [
        for (var index = 0; index < 9; index++)
          Stop(
            id: 'origin-$index',
            name: 'Origen $index',
            latitude: 0,
            longitude: index * .0001,
          ),
        for (var index = 0; index < 9; index++)
          Stop(
            id: 'destination-$index',
            name: 'Destino $index',
            latitude: 0,
            longitude: .1 + index * .0001,
          ),
      ];
      final repository = _CountingTransitRepository(
        stops: stops,
        routes: const [],
        variants: const [],
        trips: const [],
        times: const [],
        calendars: const [],
      );

      await TransitTripPlanner(
        repository,
        now: () => DateTime(2026, 6, 2, 9),
      ).plan(
        TripRequest(
          originLatitude: 0,
          originLongitude: 0,
          destinationLatitude: 0,
          destinationLongitude: .1,
          timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
        ),
      );

      expect(repository.scheduleStopRequests, hasLength(1));
      expect(repository.scheduleStopRequests.single, hasLength(18));
      expect(repository.scheduleStopRequests.single, contains('origin-8'));
    },
  );

  test('uses the previous service day for post-midnight GTFS times', () {
    final tuesdayOnly = ServiceCalendar(
      serviceId: 'tuesday',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      weekdays: {DateTime.tuesday},
    );
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .009),
      ],
      routes: const [Route(id: 'R', shortName: '10')],
      variants: const [
        RouteVariant(id: 'V', routeId: 'R', directionId: '0', destination: 'B'),
      ],
      trips: const [
        Trip(id: 'T', routeId: 'R', serviceId: 'tuesday', variantId: 'V'),
      ],
      stopTimes: const [
        StopTime(
          tripId: 'T',
          stopId: 'A',
          arrivalSeconds: 24 * 3600 + 40 * 60,
          departureSeconds: 24 * 3600 + 40 * 60,
          sequence: 1,
        ),
        StopTime(
          tripId: 'T',
          stopId: 'B',
          arrivalSeconds: 25 * 3600,
          departureSeconds: 25 * 3600,
          sequence: 2,
        ),
      ],
      calendars: [tuesdayOnly],
    );
    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.departAt(DateTime(2026, 6, 3, 0, 5)),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 23),
    );

    expect(plans, hasLength(1));
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .departureTime,
      DateTime(2026, 6, 3, 0, 40),
    );
  });

  test('uses the requested departure time to pick a later trip', () {
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .009),
      ],
      routes: const [Route(id: 'R', shortName: '10')],
      variants: const [
        RouteVariant(id: 'V', routeId: 'R', directionId: '0', destination: 'B'),
      ],
      trips: const [
        Trip(id: 'morning', routeId: 'R', serviceId: 'daily', variantId: 'V'),
        Trip(id: 'afternoon', routeId: 'R', serviceId: 'daily', variantId: 'V'),
      ],
      stopTimes: const [
        StopTime(
          tripId: 'morning',
          stopId: 'A',
          arrivalSeconds: 8 * 3600,
          departureSeconds: 8 * 3600,
          sequence: 1,
        ),
        StopTime(
          tripId: 'morning',
          stopId: 'B',
          arrivalSeconds: 8 * 3600 + 20 * 60,
          departureSeconds: 8 * 3600 + 20 * 60,
          sequence: 2,
        ),
        StopTime(
          tripId: 'afternoon',
          stopId: 'A',
          arrivalSeconds: 17 * 3600,
          departureSeconds: 17 * 3600,
          sequence: 1,
        ),
        StopTime(
          tripId: 'afternoon',
          stopId: 'B',
          arrivalSeconds: 17 * 3600 + 20 * 60,
          departureSeconds: 17 * 3600 + 20 * 60,
          sequence: 2,
        ),
      ],
      calendars: [dailyCalendar],
    );
    final departureTime = DateTime(2026, 6, 2, 16, 30);

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.departAt(departureTime),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 15),
    );

    expect(plans, hasLength(1));
    expect(plans.single.requestedDeparture, departureTime);
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .departureTime,
      DateTime(2026, 6, 2, 17),
    );
  });

  test('does not return a route when its service calendar is inactive', () {
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: 0),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .01),
      ],
      routes: const [Route(id: 'R', shortName: '10')],
      trips: const [
        Trip(id: 'T', routeId: 'R', serviceId: 'weekday', variantId: 'V'),
      ],
      stopTimes: const [
        StopTime(
          tripId: 'T',
          stopId: 'A',
          arrivalSeconds: 10 * 3600,
          departureSeconds: 10 * 3600,
          sequence: 1,
        ),
        StopTime(
          tripId: 'T',
          stopId: 'B',
          arrivalSeconds: 10 * 3600 + 20 * 60,
          departureSeconds: 10 * 3600 + 20 * 60,
          sequence: 2,
        ),
      ],
      calendars: [
        ServiceCalendar(
          serviceId: 'weekday',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          weekdays: {DateTime.monday},
        ),
      ],
    );

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.departAt(DateTime(2026, 6, 2, 9)),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 8),
    );

    expect(plans, isEmpty);
  });

  test('rejects unsupported transfer count and invalid coordinates', () {
    expect(
      () => const TransitRouteSearch().findPlans(
        request: TripRequest(
          originLatitude: 91,
          originLongitude: 0,
          destinationLatitude: 0,
          destinationLongitude: 0,
          timing: TripTiming.departAt(travelDay),
        ),
        data: const TransitScheduleData(),
        originStopIds: {'A'},
        destinationStopIds: {'B'},
      ),
      throwsArgumentError,
    );
    expect(
      () => const TransitRouteSearch().findPlans(
        request: TripRequest(
          originLatitude: 0,
          originLongitude: 0,
          destinationLatitude: 0,
          destinationLongitude: 0,
          timing: TripTiming.departAt(travelDay),
          config: const PlannerConfig(maximumTransfers: 2),
        ),
        data: const TransitScheduleData(),
        originStopIds: {'A'},
        destinationStopIds: {'B'},
      ),
      throwsArgumentError,
    );
  });
  test('plans a trip leaving now with the injected clock', () async {
    final repo = _singleTripRepository(
      departureHour: 10,
      departureMinute: 15,
      arrivalHour: 10,
      arrivalMinute: 35,
      calendars: [dailyCalendar],
    );
    final now = DateTime(2026, 6, 2, 10);

    final plans = await TransitTripPlanner(repo, now: () => now).plan(
      TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: const TripTiming.departNow(),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
    );

    expect(plans, hasLength(1));
    expect(plans.single.requestedDeparture, now);
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .departureTime,
      DateTime(2026, 6, 2, 10, 15),
    );
  });

  test('finds the latest departure that arrives by the requested time', () {
    final data = _singleTripData(
      departureHour: 9,
      departureMinute: 10,
      arrivalHour: 9,
      arrivalMinute: 41,
      calendars: [dailyCalendar],
    );

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.arriveBy(DateTime(2026, 6, 2, 10)),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 8),
    );

    expect(plans, hasLength(1));
    expect(plans.single.requestedDeparture, DateTime(2026, 6, 2, 9));
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .departureTime,
      DateTime(2026, 6, 2, 9, 10),
    );
    expect(plans.single.arrivalTime.isAfter(DateTime(2026, 6, 2, 10)), isFalse);
  });

  test('returns no plans when no trip arrives by the requested time', () {
    final data = _singleTripData(
      departureHour: 12,
      departureMinute: 0,
      arrivalHour: 12,
      arrivalMinute: 30,
      calendars: [dailyCalendar],
    );

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.arriveBy(DateTime(2026, 6, 2, 8)),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 6),
    );

    expect(plans, isEmpty);
  });

  test('does not calculate when the requested time is in the past', () {
    final data = _singleTripData(
      departureHour: 12,
      departureMinute: 0,
      arrivalHour: 12,
      arrivalMinute: 30,
      calendars: [dailyCalendar],
    );
    final now = DateTime(2026, 6, 2, 13);

    final departurePlans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.departAt(DateTime(2026, 6, 2, 11)),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: now,
    );
    final arrivalPlans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.arriveBy(DateTime(2026, 6, 2, 11)),
        config: const PlannerConfig(maximumWalkingMeters: 500),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: now,
    );

    expect(departurePlans, isEmpty);
    expect(arrivalPlans, isEmpty);
  });

  test('discards an itinerary dominated by an earlier one', () {
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .009),
      ],
      routes: const [
        Route(id: 'fast', shortName: 'F'),
        Route(id: 'slow', shortName: 'S'),
      ],
      variants: const [
        RouteVariant(
          id: 'fast-variant',
          routeId: 'fast',
          directionId: '0',
          destination: 'B',
        ),
        RouteVariant(
          id: 'slow-variant',
          routeId: 'slow',
          directionId: '0',
          destination: 'B',
        ),
      ],
      trips: const [
        Trip(
          id: 'fast-trip',
          routeId: 'fast',
          serviceId: 'daily',
          variantId: 'fast-variant',
        ),
        Trip(
          id: 'slow-trip',
          routeId: 'slow',
          serviceId: 'daily',
          variantId: 'slow-variant',
        ),
      ],
      stopTimes: [
        StopTime(
          tripId: 'fast-trip',
          stopId: 'A',
          arrivalSeconds: _seconds(10, 15),
          departureSeconds: _seconds(10, 15),
          sequence: 1,
        ),
        StopTime(
          tripId: 'fast-trip',
          stopId: 'B',
          arrivalSeconds: _seconds(10, 30),
          departureSeconds: _seconds(10, 30),
          sequence: 2,
        ),
        StopTime(
          tripId: 'slow-trip',
          stopId: 'A',
          arrivalSeconds: _seconds(10, 20),
          departureSeconds: _seconds(10, 20),
          sequence: 1,
        ),
        StopTime(
          tripId: 'slow-trip',
          stopId: 'B',
          arrivalSeconds: _seconds(10, 55),
          departureSeconds: _seconds(10, 55),
          sequence: 2,
        ),
      ],
      calendars: [dailyCalendar],
    );

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .01,
        timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );

    expect(plans, hasLength(1));
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .route
          ?.id,
      'fast',
    );
  });

  test('sorts plans by fastest, least walking and fewest transfers', () {
    final fastest = _planAt(
      arrivalMinute: 20,
      walkingMeters: 100,
      transfers: 1,
    );
    final tiedWalking = _planAt(
      arrivalMinute: 25,
      walkingMeters: 100,
      transfers: 1,
    );
    final directAndLong = _planAt(
      arrivalMinute: 30,
      walkingMeters: 600,
      transfers: 0,
    );
    final shortWalk = _planAt(
      arrivalMinute: 40,
      walkingMeters: 300,
      transfers: 1,
    );
    final plans = [directAndLong, shortWalk, tiedWalking, fastest];

    expect(
      sortTripPlans(
        plans,
        TripPlanSort.fastest,
      ).map((plan) => plan.arrivalTime.minute),
      [20, 25, 30, 40],
    );
    expect(
      sortTripPlans(
        plans,
        TripPlanSort.leastWalking,
      ).map((plan) => plan.arrivalTime.minute),
      [20, 25, 40, 30],
    );
    expect(
      sortTripPlans(
        plans,
        TripPlanSort.fewestTransfers,
      ).map((plan) => plan.arrivalTime.minute),
      [30, 20, 25, 40],
    );
  });

  test('includes a walking-only itinerary for a short trip', () async {
    final repo = FakeTransitRepository(
      stops: const [],
      routes: const [],
      variants: const [],
      trips: const [],
      times: const [],
      calendars: const [],
    );

    final plans =
        await TransitTripPlanner(repo, now: () => DateTime(2026, 6, 2, 9)).plan(
          TripRequest(
            originLatitude: 0,
            originLongitude: 0,
            destinationLatitude: 0,
            destinationLongitude: .005,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
          ),
        );
    final farPlans =
        await TransitTripPlanner(repo, now: () => DateTime(2026, 6, 2, 9)).plan(
          TripRequest(
            originLatitude: 0,
            originLongitude: 0,
            destinationLatitude: 0,
            destinationLongitude: .009,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
          ),
        );

    expect(plans, hasLength(1));
    expect(plans.single.legs, hasLength(1));
    expect(plans.single.legs.single.kind, TripLegKind.walking);
    expect(plans.single.legs.single.toLatitude, 0);
    expect(plans.single.legs.single.toLongitude, .005);
    expect(plans.single.totalWalkingMeters, closeTo(722.8, 1));
    expect(plans.single.transferCount, 0);
    expect(plans.single.arrivalTime, DateTime(2026, 6, 2, 10, 9, 3));
    expect(farPlans, isEmpty);
  });

  test('allows a 100 m walking transfer between different stops', () {
    final data = _walkingTransferData(
      secondStopLongitude: .0109,
      calendars: [dailyCalendar],
    );

    final plans = const TransitRouteSearch().findPlans(
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
    final transitLegs = plans.single.legs
        .where((leg) => leg.kind == TripLegKind.transit)
        .toList();
    expect(transitLegs.map((leg) => leg.route?.id), ['first', 'second']);
    final walkingLegs = plans.single.legs
        .where((leg) => leg.kind == TripLegKind.walking)
        .toList();
    expect(walkingLegs, hasLength(3));
    final transferWalk = walkingLegs[1];
    expect(transferWalk.fromStop?.id, 'transfer');
    expect(transferWalk.toStop?.id, 'nearby');
    expect(transferWalk.distanceMeters, closeTo(130, 1));
    expect(plans.single.totalWalkingMeters, closeTo(419.2, 2));
  });

  test('rejects a 200 m walking transfer between different stops', () {
    final data = _walkingTransferData(
      secondStopLongitude: .0118,
      calendars: [dailyCalendar],
    );

    final plans = const TransitRouteSearch().findPlans(
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

    expect(plans, isEmpty);
  });

  test('respects the maximum total walking distance', () {
    final data = TransitScheduleData(
      stops: const [
        Stop(id: 'A', name: 'A', latitude: 0, longitude: .004),
        Stop(id: 'B', name: 'B', latitude: 0, longitude: .008),
      ],
      routes: const [Route(id: 'R', shortName: '10')],
      variants: const [
        RouteVariant(id: 'V', routeId: 'R', directionId: '0', destination: 'B'),
      ],
      trips: const [
        Trip(id: 'T', routeId: 'R', serviceId: 'daily', variantId: 'V'),
      ],
      stopTimes: [
        StopTime(
          tripId: 'T',
          stopId: 'A',
          arrivalSeconds: _seconds(10, 15),
          departureSeconds: _seconds(10, 15),
          sequence: 1,
        ),
        StopTime(
          tripId: 'T',
          stopId: 'B',
          arrivalSeconds: _seconds(10, 30),
          departureSeconds: _seconds(10, 30),
          sequence: 2,
        ),
      ],
      calendars: [dailyCalendar],
    );
    TripRequest request(PlannerConfig config) => TripRequest(
      originLatitude: 0,
      originLongitude: 0,
      destinationLatitude: 0,
      destinationLongitude: .012,
      timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
      config: config,
    );

    final limited = const TransitRouteSearch().findPlans(
      request: request(const PlannerConfig()),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );
    final extended = const TransitRouteSearch().findPlans(
      request: request(const PlannerConfig(maximumWalkingMeters: 1200)),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );

    expect(limited, isEmpty);
    expect(extended, hasLength(1));
    expect(extended.single.totalWalkingMeters, closeTo(1156.4, 2));
  });

  test('rejects a transfer shorter than the minimum transfer time', () {
    final data = _sameStopTransferData(calendars: [dailyCalendar]);
    TripRequest request(PlannerConfig config) => TripRequest(
      originLatitude: 0,
      originLongitude: 0,
      destinationLatitude: 0,
      destinationLongitude: .022,
      timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
      config: config,
    );

    final limited = const TransitRouteSearch().findPlans(
      request: request(const PlannerConfig()),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );
    final extended = const TransitRouteSearch().findPlans(
      request: request(
        const PlannerConfig(minimumTransferTime: Duration(minutes: 1)),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
      now: DateTime(2026, 6, 2, 9),
    );

    expect(limited, isEmpty);
    expect(extended, hasLength(1));
  });
}

TransitScheduleData _singleTripData({
  required int departureHour,
  required int departureMinute,
  required int arrivalHour,
  required int arrivalMinute,
  required List<ServiceCalendar> calendars,
}) => TransitScheduleData(
  stops: const [
    Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
    Stop(id: 'B', name: 'B', latitude: 0, longitude: .009),
  ],
  routes: const [Route(id: 'R', shortName: '10')],
  variants: const [
    RouteVariant(id: 'V', routeId: 'R', directionId: '0', destination: 'B'),
  ],
  trips: const [
    Trip(id: 'T', routeId: 'R', serviceId: 'daily', variantId: 'V'),
  ],
  stopTimes: [
    StopTime(
      tripId: 'T',
      stopId: 'A',
      arrivalSeconds: _seconds(departureHour, departureMinute),
      departureSeconds: _seconds(departureHour, departureMinute),
      sequence: 1,
    ),
    StopTime(
      tripId: 'T',
      stopId: 'B',
      arrivalSeconds: _seconds(arrivalHour, arrivalMinute),
      departureSeconds: _seconds(arrivalHour, arrivalMinute),
      sequence: 2,
    ),
  ],
  calendars: calendars,
);

FakeTransitRepository _singleTripRepository({
  required int departureHour,
  required int departureMinute,
  required int arrivalHour,
  required int arrivalMinute,
  required List<ServiceCalendar> calendars,
}) {
  final data = _singleTripData(
    departureHour: departureHour,
    departureMinute: departureMinute,
    arrivalHour: arrivalHour,
    arrivalMinute: arrivalMinute,
    calendars: calendars,
  );
  return FakeTransitRepository(
    stops: data.stops,
    routes: data.routes,
    variants: data.variants,
    trips: data.trips,
    times: data.stopTimes,
    calendars: data.calendars,
  );
}

int _seconds(int hour, int minute) => hour * 3600 + minute * 60;

class _CountingTransitRepository extends FakeTransitRepository {
  _CountingTransitRepository({
    required super.stops,
    required super.routes,
    required super.variants,
    required super.trips,
    required super.times,
    required super.calendars,
  });

  int nearbyStopCalls = 0;
  final scheduleStopRequests = <Set<String>>[];
  final scheduleWindows = <({DateTime? windowStart, DateTime? windowEnd})>[];

  @override
  Future<List<Stop>> nearbyStops(double lat, double lon, double radiusMeters) {
    nearbyStopCalls++;
    return super.nearbyStops(lat, lon, radiusMeters);
  }

  @override
  Future<TransitScheduleData> scheduleForStops(
    Set<String> stopIds, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) {
    scheduleStopRequests.add(Set.of(stopIds));
    scheduleWindows.add((windowStart: windowStart, windowEnd: windowEnd));
    return super.scheduleForStops(
      stopIds,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
  }
}

TripPlan _planAt({
  required int arrivalMinute,
  required double walkingMeters,
  required int transfers,
}) => TripPlan(
  requestedDeparture: DateTime(2026, 6, 2, 10),
  arrivalTime: DateTime(2026, 6, 2, 10, arrivalMinute),
  legs: const [],
  totalWalkingMeters: walkingMeters,
  transferCount: transfers,
);

TransitScheduleData _walkingTransferData({
  required double secondStopLongitude,
  required List<ServiceCalendar> calendars,
}) => TransitScheduleData(
  stops: [
    const Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
    const Stop(id: 'transfer', name: 'Transbordo', latitude: 0, longitude: .01),
    Stop(
      id: 'nearby',
      name: 'Parada cercana',
      latitude: 0,
      longitude: secondStopLongitude,
    ),
    const Stop(id: 'B', name: 'B', latitude: 0, longitude: .021),
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
  calendars: calendars,
);

TransitScheduleData _sameStopTransferData({
  required List<ServiceCalendar> calendars,
}) => TransitScheduleData(
  stops: const [
    Stop(id: 'A', name: 'A', latitude: 0, longitude: .001),
    Stop(id: 'transfer', name: 'Transbordo', latitude: 0, longitude: .01),
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
      stopId: 'transfer',
      arrivalSeconds: _seconds(10, 22),
      departureSeconds: _seconds(10, 22),
      sequence: 1,
    ),
    StopTime(
      tripId: 'second-trip',
      stopId: 'B',
      arrivalSeconds: _seconds(10, 35),
      departureSeconds: _seconds(10, 35),
      sequence: 2,
    ),
  ],
  calendars: calendars,
);
