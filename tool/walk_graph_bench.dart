// Measures WalkGraph performance on the real pedestrian fixture
// (test/fixtures/osm_pedestrian.json): build time, graph size, snap and
// search latency. Run with:  dart run tool/walk_graph_bench.dart
import 'dart:convert';
import 'dart:io';

import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'test/fixtures/osm_pedestrian.json';
  stdout.writeln('file: $path');
  final json = await File(path).readAsString();
  stdout.writeln('fileBytes: ${File(path).lengthSync()}');
  final decodeWatch = Stopwatch()..start();
  final data = jsonDecode(json) as Map<String, dynamic>;
  decodeWatch.stop();
  stdout.writeln('jsonDecodeMs: ${decodeWatch.elapsedMilliseconds}');
  final elements = data['elements'] as List;
  final ways = <List<ShapePoint>>[];
  for (final element in elements) {
    if (element['type'] != 'way') continue;
    final geometry = element['geometry'];
    if (geometry is! List) continue;
    final points = <ShapePoint>[];
    for (final point in geometry) {
      if (point is Map<String, dynamic>) {
        final lat = (point['lat'] as num?)?.toDouble();
        final lon = (point['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          points.add(ShapePoint(lat, lon, points.length));
        }
      }
    }
    if (points.length >= 2) ways.add(points);
  }

  final buildWatch = Stopwatch()..start();
  final graph = WalkGraph.fromGeoJson(data)!;
  buildWatch.stop();

  stdout.writeln('fixtureWays: ${ways.length}');
  stdout.writeln('buildTimeMs: ${buildWatch.elapsedMilliseconds}');
  stdout.writeln('vertices: ${graph.vertexCount}');
  stdout.writeln('edges: ${graph.edgeCount}');
  final estimatedBytes = graph.vertexCount * 64 + graph.edgeCount * 160;
  stdout.writeln('estimatedMemoryBytes: $estimatedBytes');

  // Snap real sobre los puntos conectados del fixture (elementos 10 y 11).
  final first = (elements[10]['geometry'] as List)[0] as Map<String, dynamic>;
  final lastGeometry = elements[11]['geometry'] as List;
  final last = lastGeometry.last as Map<String, dynamic>;
  final originLat = (first['lat'] as num).toDouble();
  final originLon = (first['lon'] as num).toDouble();
  final destLat = (last['lat'] as num).toDouble();
  final destLon = (last['lon'] as num).toDouble();

  const snapRepeats = 500;
  final snapWatch = Stopwatch()..start();
  for (var i = 0; i < snapRepeats; i++) {
    graph.snapToGraph(originLat, originLon);
    graph.snapToGraph(destLat, destLon);
  }
  snapWatch.stop();
  stdout.writeln(
    'snapMsPerQueryAvg: ${snapWatch.elapsedMicroseconds / (snapRepeats * 2) / 1000}',
  );

  // Búsqueda promedio Dijkstra sobre el grafo real.
  const searchRepeats = 100;
  final searchWatch = Stopwatch()..start();
  WalkPath? walkPath;
  for (var i = 0; i < searchRepeats; i++) {
    walkPath = graph.shortestPath(originLat, originLon, destLat, destLon);
  }
  searchWatch.stop();
  stdout.writeln(
    'searchMsPerQueryAvg: ${searchWatch.elapsedMicroseconds / searchRepeats / 1000}',
  );
  stdout.writeln('pathExists: ${walkPath != null}');
  stdout.writeln(
    'pathLengthMeters: ${walkPath?.lengthMeters.toStringAsFixed(1)}',
  );

  // La búsqueda de caminata por planificación: caminata inicial, transbordo y
  // final (hasta 3 por plan); sin grafo la planificación no usa Dijkstra.
  const searchesPerPlan = 3;
  stdout.writeln(
    'estimatedMultimodalExtraMs: ${searchWatch.elapsedMicroseconds / searchRepeats / 1000 * searchesPerPlan}',
  );
}
