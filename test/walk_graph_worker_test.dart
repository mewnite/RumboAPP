import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/trip_planner/domain/planner_config.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';

void main() {
  testWidgets('persistent worker reports invalid seed initialization', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        createWalkGraphWorker(Uint8List(0)),
        throwsA(isA<RemoteError>()),
      );
    });
  });

  testWidgets(
    'persistent worker fails when ready is not signaled within the timeout',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = jsonDecode(
          await File('test/fixtures/osm_seed_minimal.json').readAsString(),
        ) as Map<String, dynamic>;
        final graph = WalkGraph.fromGeoJson(fixture)!;
        await expectLater(
          createWalkGraphWorker(
            graph.toSeedBytes(),
            startupTimeout: const Duration(milliseconds: 300),
            readyDelay: const Duration(seconds: 60),
          ),
          throwsA(isA<StateError>()),
        );
      });
    },
  );

  testWidgets(
    'persistent worker searches and refreshes walking through messages',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = jsonDecode(
          await File('test/fixtures/osm_seed_minimal.json').readAsString(),
        ) as Map<String, dynamic>;
        final graph = WalkGraph.fromGeoJson(fixture)!;
        final worker = await createWalkGraphWorker(graph.toSeedBytes());
        try {
          final repository = FakeTransitRepository(
            stops: const [],
            routes: const [],
            variants: const [],
            trips: const [],
            times: const [],
            calendars: const [],
          );
          final planner = TransitTripPlanner(
            repository,
            now: () => DateTime(2026, 6, 2, 9),
          );
          final request = TripRequest(
            originLatitude: -34.9,
            originLongitude: -56.2,
            destinationLatitude: -34.9,
            destinationLongitude: -56.199,
            timing: TripTiming.departAt(DateTime(2026, 6, 2, 10)),
            config: const PlannerConfig(maximumWalkingMeters: 800),
          );
          final approximate = await planner.plan(request);
          expect(approximate.single.legs.single.approximate, isTrue);

          planner.walkGraphWorker = worker;
          final refreshed = await planner.refreshWalkingSegments(
            approximate.single,
          );
          expect(refreshed.legs.single.approximate, isFalse);
          expect(refreshed.legs.single.distanceMeters, closeTo(91.2, 1));

          final searched = await planner.plan(request);
          expect(searched, hasLength(1));
          expect(searched.single.legs.single.approximate, isFalse);
          expect(
            searched.single.legs.single.distanceMeters,
            closeTo(refreshed.legs.single.distanceMeters, .1),
          );
        } finally {
          await worker.dispose();
        }
      });
    },
  );
}
