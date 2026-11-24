import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rumbo/features/stops_and_lines/data/sqflite_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/trip_planner/data/walk_graph_seed_source.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fixed Montevideo route runs five profile searches', (_) async {
    final databaseStore = TransitDatabase();
    var database = await databaseStore.open();
    if (!await databaseStore.hasUsableFeed(database)) {
      await database.close();
      final seed = await rootBundle.load(TransitDatabase.seedAssetPath);
      expect(
        await databaseStore.installSeed(
          seed.buffer.asUint8List(seed.offsetInBytes, seed.lengthInBytes),
        ),
        isTrue,
      );
      database = await databaseStore.open();
    }
    addTearDown(database.close);
    final worker = await createWalkGraphWorker(
      await WalkGraphSeedSource().loadSeedBytes(),
    );
    addTearDown(worker.dispose);
    expect(await worker.graphLoaded(), isTrue);

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
      config: PlannerConfig(maximumWalkingMeters: 800, maximumTransfers: 2),
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
        '[performance] device.fixed_search run=$run/5 '
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
  });
}
