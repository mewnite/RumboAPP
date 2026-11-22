import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/presentation/trip_plan_details.dart';

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
