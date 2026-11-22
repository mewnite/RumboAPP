import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';

void main() {
  testWidgets('measure the persistent worker with the generated seed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await File('build/seeds/walk_graph_seed.bin').readAsBytes();
      final graph = WalkGraph.fromSeedBytes(bytes);
      final directTimes = <int>[];
      for (var i = 0; i < 5; i++) {
        final directWatch = Stopwatch()..start();
        final directPath = graph.shortestPath(
          -34.906998,
          -56.180963,
          -34.90774,
          -56.19094,
        );
        directWatch.stop();
        if (directPath == null) {
          throw StateError('Expected OSM route was not found.');
        }
        directTimes.add(directWatch.elapsedMicroseconds);
      }
      final startup = Stopwatch()..start();
      final worker = await createWalkGraphWorker(bytes);
      startup.stop();
      try {
        final pings = <int>[];
        final walks = <int>[];
        for (var i = 0; i < 3; i++) {
          final watch = Stopwatch()..start();
          await worker.ping();
          watch.stop();
          pings.add(watch.elapsedMicroseconds);
        }
        for (var i = 0; i < 5; i++) {
          final watch = Stopwatch()..start();
          final path = await worker.shortestPath(
            -34.906998,
            -56.180963,
            -34.90774,
            -56.19094,
          );
          watch.stop();
          if (path == null) {
            throw StateError('Expected OSM route was not found.');
          }
          walks.add(watch.elapsedMicroseconds);
        }
        stdout.writeln(
          'worker_seed_startup_ms=${startup.elapsedMilliseconds} '
          'seed_bytes=${bytes.length}',
        );
        stdout.writeln('direct_shortest_path_us=${directTimes.join(",")}');
        stdout.writeln('worker_ping_roundtrip_us=${pings.join(",")}');
        stdout.writeln('worker_shortest_path_roundtrip_us=${walks.join(",")}');
      } finally {
        await worker.dispose();
      }
    });
  });
}
