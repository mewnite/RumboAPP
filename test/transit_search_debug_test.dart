import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rumbo/features/stops_and_lines/data/sqflite_transit_repository.dart';
import 'package:rumbo/features/trip_planner/data/walk_graph_seed_source.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';

void main() {
  test('debug slowest fixture route emits performance counters', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final database = await openDatabase(
      '${Directory.current.path}/assets/transit_db/rumbo_transit_seed.db',
      readOnly: true,
    );
    addTearDown(() => database.close());
    final repository = SqfliteTransitRepository(() async => database);
    const originLatitude = -34.919799;
    const originLongitude = -56.151802;
    const destinationLatitude = -34.902;
    const destinationLongitude = -56.168;

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
    expect(plans.length, greaterThanOrEqualTo(3));
    final worker = await createWalkGraphWorker(
      await File(WalkGraphSeedSource.assetPath).readAsBytes(),
    );
    addTearDown(worker.dispose);
    final refinedCandidates = <TripPlan>[];
    for (var index = 0; index < plans.length && index < 3; index++) {
      final refined = await worker.refreshWalkingSegments(plans[index]);
      refinedCandidates.add(refined);
      debugPrint(
        '[performance] desktop.baseline_candidate rank=${index + 1} '
        'arrival=${refined.arrivalTime.toIso8601String()} '
        'walking_m=${refined.totalWalkingMeters.round()} '
        'transfers=${refined.transferCount}',
      );
    }
    expect(refinedCandidates.first.totalWalkingMeters, greaterThan(800));
    expect(refinedCandidates[1].totalWalkingMeters, lessThanOrEqualTo(800));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('desktop fixed route runs five comparable searches', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final database = await openDatabase(
      '${Directory.current.path}/assets/transit_db/rumbo_transit_seed.db',
      readOnly: true,
    );
    addTearDown(database.close);
    final worker = await createWalkGraphWorker(
      await File(WalkGraphSeedSource.assetPath).readAsBytes(),
    );
    addTearDown(worker.dispose);
    final planner = TransitTripPlanner(
      SqfliteTransitRepository(() async => database),
      now: () => DateTime(2026, 11, 24, 7),
      walkGraphWorker: worker,
    );
    final request = TripRequest(
      originLatitude: -34.919799,
      originLongitude: -56.151802,
      destinationLatitude: -34.902,
      destinationLongitude: -56.168,
      timing: TripTiming.departAt(DateTime(2026, 11, 24, 8)),
      config: const PlannerConfig(
        maximumWalkingMeters: 800,
        maximumTransfers: 2,
      ),
    );

    for (var run = 1; run <= 5; run++) {
      final watch = Stopwatch()..start();
      final plans = await planner.plan(request);
      watch.stop();
      expect(plans, hasLength(3));
      final validBaselineArrival = DateTime(2026, 11, 24, 8, 24, 51);
      expect(
        plans.first.arrivalTime.isBefore(validBaselineArrival) ||
            plans.first.arrivalTime.isAtSameMomentAs(validBaselineArrival),
        isTrue,
      );
      debugPrint(
        '[performance] desktop.fixed_search run=$run/5 '
        'elapsed_ms=${watch.elapsedMilliseconds} plans=${plans.length} '
        'top3=${plans.take(3).map((plan) {
          final routes = plan.legs.where((leg) => leg.kind == TripLegKind.transit).map((leg) => leg.route?.id).join(',');
          return '${plan.arrivalTime.toIso8601String()}/'
              '${plan.transferCount}/'
              '${plan.totalWalkingMeters.round()}/$routes';
        }).join(';')}',
      );
      expect(plans, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
