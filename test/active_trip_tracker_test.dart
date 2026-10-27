import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_detail/domain/active_trip_tracker.dart';

void main() {
  final stops = [
    const Stop(
      id: 's1',
      name: 'Primera',
      latitude: -34.900,
      longitude: -56.200,
    ),
    const Stop(
      id: 's2',
      name: 'Segunda',
      latitude: -34.900,
      longitude: -56.190,
    ),
    const Stop(
      id: 's3',
      name: 'Tercera',
      latitude: -34.900,
      longitude: -56.180,
    ),
    const Stop(id: 's4', name: 'Cuarta', latitude: -34.900, longitude: -56.170),
  ];

  test('alerts once two stops before the selected alighting stop', () {
    final tracker = ActiveTripTracker(stops: stops, destinationStopId: 's4');

    final before = tracker.update(-34.900, -56.200);
    expect(before.stopsRemaining, 3);
    expect(before.shouldAlert, isFalse);

    final approaching = tracker.update(-34.900, -56.180);
    expect(approaching.stopsRemaining, 1);
    expect(approaching.shouldAlert, isTrue);

    final repeated = tracker.update(-34.900, -56.170);
    expect(repeated.shouldAlert, isFalse);
  });

  test(
    'alerts within 300m even when the route stop sequence is unavailable',
    () {
      final shortRoute = [stops[0], stops[1]];
      final tracker = ActiveTripTracker(
        stops: shortRoute,
        destinationStopId: 's2',
      );

      final progress = tracker.update(-34.900, -56.188);

      expect(progress.distanceToDestinationMeters, lessThan(300));
      expect(progress.shouldAlert, isTrue);
    },
  );
}
