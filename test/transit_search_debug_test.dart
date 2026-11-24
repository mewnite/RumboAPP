import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rumbo/features/stops_and_lines/data/sqflite_transit_repository.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';

void main() {
  test('debug fixed Montevideo route emits performance counters', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final database = await openDatabase(
      '${Directory.current.path}/assets/transit_db/rumbo_transit_seed.db',
      readOnly: true,
    );
    addTearDown(() => database.close());
    final repository = SqfliteTransitRepository(() async => database);
    const originLatitude = -34.903;
    const originLongitude = -56.190;
    const destinationLatitude = -34.915;
    const destinationLongitude = -56.149;

    final origins = await repository.nearbyStops(
      originLatitude,
      originLongitude,
      800,
    );
    final destinations = await repository.nearbyStops(
      destinationLatitude,
      destinationLongitude,
      800,
    );
    final originIds = origins.take(15).map((stop) => stop.id).toSet();
    final destinationIds = destinations.take(15).map((stop) => stop.id).toSet();
    final data = await repository.scheduleForStops(
      {...originIds, ...destinationIds},
      windowStart: DateTime(2026, 11, 24, 8),
      windowEnd: DateTime(2026, 11, 24, 11, 45),
    );

    final plans = const TransitRouteSearch().findPlans(
      request: TripRequest(
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        timing: TripTiming.departAt(DateTime(2026, 11, 24, 8)),
        config: const PlannerConfig(maximumWalkingMeters: 800),
      ),
      data: data,
      originStopIds: originIds,
      destinationStopIds: destinationIds,
      now: DateTime(2026, 11, 24, 7),
    );

    expect(plans, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
