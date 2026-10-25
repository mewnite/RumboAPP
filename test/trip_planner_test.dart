import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
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
    final repo = FakeTransitRepository(
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

    final plans = await TransitTripPlanner(repo).plan(
      TripRequest(
        originLatitude: 0,
        originLongitude: 0,
        destinationLatitude: 0,
        destinationLongitude: .02,
        departureTime: DateTime(2026, 6, 2, 10),
        maximumWalkingMeters: 500,
      ),
    );

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
    expect(plans.first.arrivalTime, DateTime(2026, 6, 2, 10, 41, 33));
    expect(plans.first.transferCount, 1);
    expect(
      plans.first.legs.where((leg) => leg.kind == TripLegKind.transit),
      hasLength(2),
    );
    expect(plans.first.timeAccuracy, TripTimeAccuracy.scheduled);
    expect(plans.last.transferCount, 0);
  });

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
        departureTime: DateTime(2026, 6, 3, 0, 5),
        maximumWalkingMeters: 500,
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
    );

    expect(plans, hasLength(1));
    expect(
      plans.single.legs
          .singleWhere((leg) => leg.kind == TripLegKind.transit)
          .departureTime,
      DateTime(2026, 6, 3, 0, 40),
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
        departureTime: DateTime(2026, 6, 2, 9),
      ),
      data: data,
      originStopIds: {'A'},
      destinationStopIds: {'B'},
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
          departureTime: travelDay,
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
          departureTime: travelDay,
          maximumTransfers: 2,
        ),
        data: const TransitScheduleData(),
        originStopIds: {'A'},
        destinationStopIds: {'B'},
      ),
      throwsArgumentError,
    );
  });
}

int _seconds(int hour, int minute) => hour * 3600 + minute * 60;
