import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rumbo/features/stops_and_lines/data/sqflite_transit_repository.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';

void main() {
  test('optimized search preserves or improves 10 real route baselines', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final database = await openDatabase(
      '${Directory.current.path}/assets/transit_db/rumbo_transit_seed.db',
      readOnly: true,
    );
    addTearDown(() => database.close());
    final repository = SqfliteTransitRepository(() async => database);
    final fixtureText = await File('test/fixtures/transit_route_baseline.json')
        .readAsString();
    final fixture = (jsonDecode(fixtureText) as List).cast<Map>();
    final transferVariants =
        (Platform.environment['RUMBO_BENCH_MAX_TRANSFERS'] ?? '1,2')
            .split(',')
            .map(int.parse)
            .toList(growable: false);
    final selectedFixture = Platform.environment['RUMBO_BENCH_FIXTURE_ID'];

    for (final entry in fixture) {
      if (selectedFixture != null && entry['id'] != selectedFixture) {
        continue;
      }
      final origin = entry['origin'] as Map;
      final destination = entry['destination'] as Map;
      final originLatitude = (origin['latitude'] as num).toDouble();
      final originLongitude = (origin['longitude'] as num).toDouble();
      final destinationLatitude = (destination['latitude'] as num).toDouble();
      final destinationLongitude = (destination['longitude'] as num).toDouble();
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
      final destinationIds = destinations
          .take(15)
          .map((stop) => stop.id)
          .toSet();
      final data = await repository.scheduleForStops(
        {...originIds, ...destinationIds},
        windowStart: DateTime(2026, 11, 24, 8),
        windowEnd: DateTime(2026, 11, 24, 11, 45),
      );
      final baselineTop = (entry['top'] as List).cast<Map>();
      for (final maximumTransfers in transferVariants) {
        debugPrint(
          '[performance] trip.fixture_start id=${entry['id']} '
          'maximum_transfers=$maximumTransfers',
        );
        final watch = Stopwatch()..start();
        final plans = const TransitRouteSearch().findPlans(
          request: TripRequest(
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude,
            timing: TripTiming.departAt(DateTime(2026, 11, 24, 8)),
            config: PlannerConfig(
              maximumWalkingMeters: 800,
              maximumTransfers: maximumTransfers,
            ),
          ),
          data: data,
          originStopIds: originIds,
          destinationStopIds: destinationIds,
          now: DateTime(2026, 11, 24, 7),
        );
        watch.stop();
        debugPrint(
          '[performance] trip.fixture_result id=${entry['id']} '
          'maximum_transfers=$maximumTransfers '
          'elapsed_ms=${watch.elapsedMilliseconds} '
          'top3=${plans.take(3).map((plan) {
            final routes = plan.legs.where((leg) => leg.kind == TripLegKind.transit).map((leg) => leg.route?.id).join(',');
            return '${plan.arrivalTime.toIso8601String()}/'
                '${plan.transferCount}/${plan.totalWalkingMeters.round()}/'
                '$routes';
          }).join(';')}',
        );

        if (baselineTop.isEmpty) {
          expect(plans, isEmpty, reason: entry['id'] as String);
          continue;
        }
        expect(plans, isNotEmpty, reason: entry['id'] as String);
        final baselineArrival = DateTime.parse(
          baselineTop.first['arrival'] as String,
        );
        expect(
          plans.first.arrivalTime.isBefore(baselineArrival) ||
              plans.first.arrivalTime.isAtSameMomentAs(baselineArrival),
          isTrue,
          reason:
              '${entry['id']}: baseline=$baselineArrival '
              'nuevo=${plans.first.arrivalTime}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
