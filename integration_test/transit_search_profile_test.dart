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

  testWidgets('fixed Montevideo routes run five profile searches', (_) async {
    final databaseStore = TransitDatabase();
    var database = await databaseStore.open();
    var repository = SqfliteTransitRepository(() async => database);
    var feed = await repository.feedStatus();
    if (!await databaseStore.hasUsableFeed(database) ||
        feed.synthetic ||
        feed.source.isEmpty) {
      await database.close();
      final seed = await rootBundle.load(TransitDatabase.seedAssetPath);
      expect(
        await databaseStore.installSeed(
          seed.buffer.asUint8List(seed.offsetInBytes, seed.lengthInBytes),
        ),
        isTrue,
      );
      database = await databaseStore.open();
      repository = SqfliteTransitRepository(() async => database);
      feed = await repository.feedStatus();
    }
    addTearDown(database.close);
    expect(feed.synthetic, isFalse);
    expect(feed.source, isNotEmpty);
    debugPrint(
      '[performance] device.feed source="${feed.source}" '
      'synthetic=${feed.synthetic} stops=${feed.stopCount} '
      'trips=${feed.tripCount} stop_times=${feed.stopTimeCount}',
    );

    final worker = await createWalkGraphWorker(
      await WalkGraphSeedSource().loadSeedBytes(),
    );
    addTearDown(worker.dispose);
    expect(await worker.graphLoaded(), isTrue);

    final planner = TransitTripPlanner(
      repository,
      now: () => DateTime(2026, 11, 24, 7),
      walkGraphWorker: worker,
    );

    final scenarios =
        <
          ({
            String id,
            double originLatitude,
            double originLongitude,
            double destinationLatitude,
            double destinationLongitude,
          })
        >[
          (
            id: 'pocitos_portones',
            originLatitude: -34.919799,
            originLongitude: -56.151802,
            destinationLatitude: -34.902,
            destinationLongitude: -56.168,
          ),
          (
            id: 'cerro_centro',
            originLatitude: -34.884,
            originLongitude: -56.251,
            destinationLatitude: -34.906,
            destinationLongitude: -56.193,
          ),
          (
            id: 'tres_cruces_buceo',
            originLatitude: -34.8942,
            originLongitude: -56.1646,
            destinationLatitude: -34.899849,
            destinationLongitude: -56.129917,
          ),
          (
            id: 'parque_rodo_carrasco',
            originLatitude: -34.913,
            originLongitude: -56.166,
            destinationLatitude: -34.882983,
            destinationLongitude: -56.049367,
          ),
        ];

    for (final scenario in scenarios) {
      for (var run = 1; run <= 5; run++) {
        final request = TripRequest(
          originLatitude: scenario.originLatitude,
          originLongitude: scenario.originLongitude,
          destinationLatitude: scenario.destinationLatitude,
          destinationLongitude: scenario.destinationLongitude,
          timing: TripTiming.departAt(DateTime(2026, 11, 24, 8)),
          config: PlannerConfig(maximumWalkingMeters: 800, maximumTransfers: 2),
        );
        final watch = Stopwatch()..start();
        final plans = await planner.plan(request);
        watch.stop();
        expect(plans, isNotEmpty, reason: scenario.id);
        debugPrint(
          '[performance] device.fixed_search pair=${scenario.id} '
          'run=$run/5 elapsed_ms=${watch.elapsedMilliseconds} '
          'plans=${plans.length} top3=${plans.take(3).map((plan) {
            final routes = plan.legs.where((leg) => leg.kind == TripLegKind.transit).map((leg) => leg.route?.id).join(',');
            return '${plan.arrivalTime.toIso8601String()}/'
                '${plan.transferCount}/'
                '${plan.totalWalkingMeters.round()}/$routes';
          }).join(';')}',
        );
      }
    }
  });
}
