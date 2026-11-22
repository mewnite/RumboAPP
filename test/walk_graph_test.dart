import "dart:convert";
import "dart:io";
import "dart:isolate";
import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";
import "package:rumbo/features/stops_and_lines/domain/transit_models.dart";
import "package:rumbo/features/trip_planner/domain/walk_graph.dart";

const double x0 = -34.9200, x1 = -34.9100;
const double y0 = -56.2100, y1 = -56.2000;

bool isInsideBlock(ShapePoint p) =>
    p.latitude > x0 && p.latitude < x1 && p.longitude > y0 && p.longitude < y1;

double distanceMeters(ShapePoint a, ShapePoint b) {
  final p1 = a.latitude * math.pi / 180;
  final p2 = b.latitude * math.pi / 180;
  final dp = (b.latitude - a.latitude) * math.pi / 180;
  final dl = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.pow(math.sin(dp / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * 6371000 * math.asin(math.sqrt(h));
}

/// Manazana cuadrada entre [x0, x1] x [y0, y1].
///
/// El grafo tiene una vía única que pasa sobre el bloque, desde el origen
/// hasta el destino: la manzana queda entre los lados superior e inferior
/// de la vía. Todos los puntos de la vía están fuera del bloque.
WalkGraph blockAroundGraph() => WalkGraph.fromWays([
  [
    ShapePoint(x0 - .006, y0, 0), // origen (fuera del bloque)
    ShapePoint(x0, y1 + .0005, 1), // sobre el lado izquierdo del bloque
    ShapePoint(x1, y1 + .0005, 2), // sobre el lado derecho del bloque
    ShapePoint(x1 + .006, y0, 3), // destino (fuera del bloque)
  ],
]);

void main() {
  testWidgets("decode and graph build isolates advance through runAsync", (
    tester,
  ) async {
    WalkGraph? graph;
    await tester.runAsync(() async {
      final text = await File("test/fixtures/osm_pedestrian.json")
          .readAsString();
      final decoded = await Isolate.run<Object?>(() => jsonDecode(text));
      final network = decoded as Map<String, dynamic>;
      graph = await Isolate.run<WalkGraph?>(
        () => WalkGraph.fromGeoJson(network),
      );
    });
    expect(graph, isNotNull);
    expect(graph!.vertexCount, greaterThan(0));
  });

  test(
    'seed parser excludes restricted roads and accepts foot=yes exceptions',
    () async {
      final data = jsonDecode(
        await File('test/fixtures/osm_seed_minimal.json').readAsString(),
      ) as Map<String, dynamic>;
      final graph = WalkGraph.fromGeoJson(data);
      expect(graph, isNotNull);
      expect(graph!.wayCount, 5);
      expect(graph.edgeCount, 5);
    },
  );

  test(
    'excludes motorways without foot=yes and all construction/proposed ways',
    () {
      final excludedHighways = [
        'motorway',
        'motorway_link',
        'trunk',
        'trunk_link',
        'construction',
        'proposed',
      ];
      final elements = <Map<String, dynamic>>[];
      var id = 1;
      for (final highway in excludedHighways) {
        elements.add({
          'type': 'way',
          'id': id++,
          'tags': {'highway': highway},
          'geometry': [
            {'lat': -34.9, 'lon': -56.2},
            {'lat': -34.9, 'lon': -56.199},
          ],
        });
      }
      for (final highway in [
        'motorway',
        'motorway_link',
        'trunk',
        'trunk_link',
      ]) {
        elements.add({
          'type': 'way',
          'id': id++,
          'tags': {'highway': highway, 'foot': 'yes'},
          'geometry': [
            {'lat': -34.91, 'lon': -56.2},
            {'lat': -34.91, 'lon': -56.199},
          ],
        });
      }
      for (final highway in ['construction', 'proposed']) {
        elements.add({
          'type': 'way',
          'id': id++,
          'tags': {'highway': highway, 'foot': 'yes'},
          'geometry': [
            {'lat': -34.92, 'lon': -56.2},
            {'lat': -34.92, 'lon': -56.199},
          ],
        });
      }

      final graph = WalkGraph.fromGeoJson({'elements': elements});

      expect(graph!.wayCount, 4);
    },
  );

  test('binary seed round-trips typed arrays and detects corruption', () async {
    final data = jsonDecode(
      await File('test/fixtures/osm_seed_minimal.json').readAsString(),
    ) as Map<String, dynamic>;
    final graph = WalkGraph.fromGeoJson(
      data,
      sourceDate: '261121',
      sourceSha256: List.filled(64, 'a').join(),
    )!;
    final bytes = graph.toSeedBytes();
    final restored = WalkGraph.fromSeedBytes(bytes);
    final before = graph.shortestPath(-34.9, -56.2, -34.9, -56.199);
    final after = restored.shortestPath(-34.9, -56.2, -34.9, -56.199);

    expect(restored.sourceDate, '261121');
    expect(restored.sourceSha256, List.filled(64, 'a').join());
    expect(restored.vertexCount, graph.vertexCount);
    expect(restored.edgeCount, graph.edgeCount);
    expect(after!.lengthMeters, closeTo(before!.lengthMeters, .1));

    bytes[bytes.length - 1] ^= 1;
    expect(() => WalkGraph.fromSeedBytes(bytes), throwsFormatException);
  });

  test('Montevideo snap search stays within the 75 m spatial window', () {
    final graph = WalkGraph.fromWays([
      [ShapePoint(-34.9, -56.2, 0), ShapePoint(-34.9, -56.195, 1)],
    ]);
    final watch = Stopwatch()..start();
    final path = graph.shortestPath(-34.9001, -56.2, -34.9001, -56.195);
    watch.stop();

    expect(path, isNotNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('per-query snap overlay does not mutate the immutable base graph', () {
    final graph = blockAroundGraph();
    final before = graph.toSeedBytes();
    for (var i = 0; i < 3; i++) {
      expect(
        graph.shortestPath(x0 - .006, y0 + i * .00001, x1 + .006, y0),
        isNotNull,
      );
    }
    expect(graph.toSeedBytes(), orderedEquals(before));
  });

  test(
    "caminata entre dos puntos separados por una manzana - desvia el camino",
    () {
      final graph = blockAroundGraph();
      final origin = (x0 - .006, y0);
      final dest = (x1 + .006, y0);

      final path = graph.shortestPath(origin.$1, origin.$2, dest.$1, dest.$2);
      expect(path, isNotNull);
      expect(path!.points.first.latitude, closeTo(origin.$1, .001));
      expect(path.points.last.latitude, closeTo(dest.$1, .001));

      expect(
        path.points.every((p) => !isInsideBlock(p)),
        isTrue,
        reason: "el camino no atraviesa la manzana",
      );
      expect(
        path.lengthMeters,
        greaterThan(
          distanceMeters(
                ShapePoint(origin.$1, origin.$2, 0),
                ShapePoint(dest.$1, dest.$2, 0),
              ) +
              50,
        ),
        reason: "el camino rodea la manzana, no es la línea recta",
      );
    },
  );

  test("la línea recta entre los puntos de dos lados de la manzana cruza el edificio", () {
    // Vía de prueba que pasa por encima del edificio (manzana): el camino
    // debe desviarse hacia el lado este y volver al destino.
    final graph = WalkGraph.fromWays([
      [
        ShapePoint(-34.921, -56.2000, 0),
        ShapePoint(-34.921, -56.1990, 1),
        ShapePoint(-34.9150, -56.1990, 2),
        ShapePoint(-34.909, -56.1990, 3),
        ShapePoint(-34.909, -56.2000, 4),
      ],
    ]);
    final origin = (-34.921, -56.2000);
    final dest = (-34.909, -56.2000);

    final path = graph.shortestPath(origin.$1, origin.$2, dest.$1, dest.$2);
    expect(path, isNotNull);
    expect(
      path!.lengthMeters,
      greaterThan(
        distanceMeters(
              ShapePoint(origin.$1, origin.$2, 0),
              ShapePoint(dest.$1, dest.$2, 0),
            ) +
            50,
      ),
      reason: "el camino rodea el edificio, no atraviesa la manzana",
    );
    expect(
      path.points.any(
        (p) => p.longitude > y1 + .0004 || p.longitude < y0 - .0004,
      ),
      isTrue,
      reason: "el camino pasa por encima o debajo del edificio",
    );
  });

  test("el camino necesita rodear una manzana", () {
    final graph = blockAroundGraph();
    final origin = (x0 - .006, y0);
    final dest = (x1 + .006, y0);

    final path = graph.shortestPath(origin.$1, origin.$2, dest.$1, dest.$2);
    expect(path, isNotNull);
    expect(path!.points.every((p) => !isInsideBlock(p)), isTrue);
  });

  test("el camino usa un cruce o camino peatonal", () {
    // Dos vías que se cruzan en el punto (-34.909, -56.205): el camino
    // debe usar el vértice compartido como cruce.
    final graph = WalkGraph.fromWays([
      [ShapePoint(-34.9105, -56.205, 0), ShapePoint(-34.909, -56.205, 1)],
      [ShapePoint(-34.909, -56.205, 1), ShapePoint(-34.9095, -56.197, 2)],
    ]);
    final path = graph.shortestPath(-34.9105, -56.205, -34.9095, -56.197);
    expect(path, isNotNull);
    expect(
      path!.points.any((p) => p.latitude == -34.909 && p.longitude == -56.205),
      isTrue,
    );
  });

  test("snap con gap: el camino incluye el segmento punteado user→vértice y suma la distancia", () {
    // Vía larga en lon=0..0.2; el usuario está a ~47 m del camino.
    final graph = WalkGraph.fromWays([
      [ShapePoint(0, 0, 0), ShapePoint(0, 0.2, 1)],
    ]);
    final origin = (0.0003, 0.0003);
    final dest = (0.0003, 0.0004);

    final path = graph.shortestPath(origin.$1, origin.$2, dest.$1, dest.$2);
    expect(path, isNotNull);
    expect(path!.gapMeters, greaterThan(30));
    // El primer punto es el punto real del usuario y el segundo el
    // punto proyectado donde empieza el camino real.
    expect(path.points.first.latitude, closeTo(origin.$1, .001));
    expect(path.points.first.longitude, closeTo(origin.$2, .001));
    expect(path.points[1].latitude, closeTo(0, .001));
    expect(path.points[1].longitude, closeTo(origin.$2, .00001));
    expect(path.points.last.latitude, closeTo(dest.$1, .001));
    expect(path.points.last.longitude, closeTo(dest.$2, .001));
    expect(path.points[path.points.length - 2].latitude, closeTo(0, .001));
    expect(
      path.points[path.points.length - 2].longitude,
      closeTo(dest.$2, .00001),
    );
    // La distancia incluye el gap punteado.
    expect(path.lengthMeters, greaterThan(30));
  });

  test("no existen saltos arbitrarios entre puntos del camino", () {
    final graph = blockAroundGraph();
    final origin = (x0 - .006, y0);
    final dest = (x1 + .006, y0);
    final path = graph.shortestPath(origin.$1, origin.$2, dest.$1, dest.$2);
    expect(path, isNotNull);
    for (var i = 1; i < path!.points.length; i++) {
      final jump = distanceMeters(path.points[i - 1], path.points[i]);
      expect(jump, lessThan(1500), reason: "salto arbitrario de ${jump}m");
    }
  });

  test("real MCIO: el camino está sobre la red de OSM real", () async {
    final data = jsonDecode(
      await File("test/fixtures/osm_pedestrian.json").readAsString(),
    );
    final graph = WalkGraph.fromGeoJson(data);
    expect(graph, isNotNull);
    final elements = data["elements"] as List;
    // elements[10] y elements[11] están conectados en la red del fixture.
    final first = elements[10] as Map<String, dynamic>;
    final firstPt = first["geometry"][0] as Map<String, dynamic>;
    final firstLat = (firstPt["lat"] as num).toDouble();
    final firstLon = (firstPt["lon"] as num).toDouble();
    final last = elements[11] as Map<String, dynamic>;
    final lastPt = last["geometry"].last as Map<String, dynamic>;
    final lastLat = (lastPt["lat"] as num).toDouble();
    final lastLon = (lastPt["lon"] as num).toDouble();

    final path = graph!.shortestPath(firstLat, firstLon, lastLat, lastLon);
    expect(path, isNotNull);
    expect(path!.lengthMeters, greaterThan(0));
    expect(path.lengthMeters, closeTo(600.59, .05));
    expect(path.points, hasLength(8));
    expect(path.points.first.latitude, closeTo(firstLat, .01));
    expect(path.points.first.longitude, closeTo(firstLon, .01));
    expect(path.points.last.latitude, closeTo(lastLat, .01));
    expect(path.points.last.longitude, closeTo(lastLon, .01));
  });
}
