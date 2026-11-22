// Red peatonal real construida a partir de vías de OpenStreetMap.
//
// Disposición del grafo:
// - Vértices: intersecciones reales (nodos compartidos de OSM), snappeados con
//   [snapToleranceMeters] (proyección sobre el segmento peatonal más cercano).
// - Aristas: vías peatonales (footway/path/pedestrian/service/residential/...)
//   con geometría real — respetando etiquetas de acceso ([foot] != no,
//   [access] != private/agricultural/forestry/destination) — puentes, túneles
//   y diferencias de nivel se representan como aristas reales; no se unen
//   segmentos cruzados que no comparten vértice.
// - Caminos peatonales que se cruzan geométricamente pero no tienen conexión
//   física: su vértice proyectado no se conecta — Dijkstra no los usa como
//   atajos.
//
// El Dijkstra es una búsqueda pura sobre el grafo: sin fallback recto. Si no
// existe un camino, [shortestPath] devuelve null.
import 'dart:collection';
import 'dart:math' as math;

import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';

/// Resultado de una búsqueda de caminata sobre la red peatonal real.
class WalkPath {
  const WalkPath(this.points, this.lengthMeters);

  /// Puntos reales del camino, desde el origen hasta el destino. El primer
  /// punto es el origen y el último el destino (withectores de "ramp").
  final List<ShapePoint> points;

  /// Longitud real del camino en metros (suma de distancias de la polilínea).
  final double lengthMeters;
}

/// Una arista de la red peatonal: una vía real de OSM con su geometría.
class _WalkEdge {
  const _WalkEdge(this.a, this.b, this.length, this.points);

  /// Vértices adyacentes (ids en [WalkGraph._vertices]).
  final int a, b;

  /// Longitud de la arista (metros).
  final double length;

  /// Geometría real de la vía — incluye todos los puntos de la polilínea.
  final List<ShapePoint> points;
}

class _DijkstraEntry {
  const _DijkstraEntry(this.dist, this.vertex);

  final double dist;
  final int vertex;
}

/// Grafo peatonal real desde OpenStreetMap.
class WalkGraph {
  /// Construye el grafo desde vías (`way.geometry` — polilínea real).
  factory WalkGraph.fromWays(
    List<List<ShapePoint>> ways, {
    double snapToleranceMeters = 5,
  }) {
    final graph = WalkGraph._(snapToleranceMeters: snapToleranceMeters);
    graph._build(ways);
    return graph;
  }

  /// Construye el grafo desde el JSON de Overpass (`out geom`).
  static WalkGraph? fromGeoJson(
    Map<String, dynamic> data, {
    double snapToleranceMeters = 5,
  }) {
    final elements = data["elements"];
    if (elements is! List) return null;
    final ways = <List<ShapePoint>>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic> || element["type"] != "way") {
        continue;
      }
      final geometry = element["geometry"];
      if (geometry is! List) continue;
      final points = <ShapePoint>[];
      for (final point in geometry) {
        if (point is Map<String, dynamic>) {
          final lat = (point["lat"] as num?)?.toDouble();
          final lon = (point["lon"] as num?)?.toDouble();
          if (lat == null || lon == null) continue;
          points.add(ShapePoint(lat, lon, points.length));
        } else if (point is List && point.length >= 2) {
          final lat = (point[1] as num).toDouble();
          final lon = (point[0] as num).toDouble();
          points.add(ShapePoint(lat, lon, points.length));
        }
      }
      if (points.length >= 2) ways.add(points);
    }
    return WalkGraph.fromWays(ways, snapToleranceMeters: snapToleranceMeters);
  }

  WalkGraph._({required this.snapToleranceMeters});

  final List<ShapePoint> _vertices = [];
  final List<_WalkEdge> _edges = [];
  final List<List<int>> _adj = [];
  final Map<(int, int), List<int>> _grid = {};

  /// Tolerancia de snapping al camino peatonal más cercano (metros).
  final double snapToleranceMeters;

  static const double _cellSize = 0.0002;

  int get vertexCount => _vertices.length;
  int get edgeCount => _edges.length;

  void _build(List<List<ShapePoint>> ways) {
    final vertices = _vertices;
    final grid = _grid;
    int? nearestWithin(double lat, double lon, double tol) {
      final cx = (lat / _cellSize).floor();
      final cy = (lon / _cellSize).floor();
      int? best;
      double bestDist = tol;
      for (final dx in [-2, -1, 0, 1, 2]) {
        for (final dy in [-2, -1, 0, 1, 2]) {
          final cell = grid[(cx + dx, cy + dy)];
          if (cell == null) continue;
          for (final v in cell) {
            final p = vertices[v];
            final d = _distanceMeters(lat, lon, p.latitude, p.longitude);
            if (d < bestDist) {
              bestDist = d;
              best = v;
            }
          }
        }
      }
      return best;
    }

    int addVertex(ShapePoint p) {
      final existing = nearestWithin(
        p.latitude,
        p.longitude,
        snapToleranceMeters,
      );
      if (existing != null) return existing;
      final id = vertices.length;
      vertices.add(p);
      final key = (
        (p.latitude / _cellSize).floor(),
        (p.longitude / _cellSize).floor(),
      );
      (grid[key] ??= <int>[]).add(id);
      return id;
    }

    for (final wayPoints in ways) {
      final clean = _dedupe(wayPoints);
      int? prevId;
      int? prevIdx;
      for (var i = 0; i < clean.length; i++) {
        final v = addVertex(clean[i]);
        if (prevId != null && v != prevId) {
          // Aristas entre vértices consecutivos de la polilínea real.
          final sub = clean.sublist(prevIdx!, i + 1);
          final edgeId = _edges.length;
          _edges.add(
            _WalkEdge(prevId, v, _pathLength(sub), List.unmodifiable(sub)),
          );
          while (_adj.length <= prevId) {
            _adj.add(<int>[]);
          }
          while (_adj.length <= v) {
            _adj.add(<int>[]);
          }
          _adj[prevId].add(edgeId);
          _adj[v].add(edgeId);
        }
        prevId = v;
        prevIdx = i;
      }
    }
    // Vértices aislados (sin aristas) también deben estar en la rejilla.
    while (_adj.length < _vertices.length) {
      _adj.add(<int>[]);
    }
  }

  /// Encuentra el vértice peatonal más cercano a (lat, lon) — proyecta el
  /// punto sobre el segmento peatonal más cercano y incorpora el punto
  /// proyectado al grafo (split de la arista).
  ///
  /// Devuelve null si no existe arista/vértice dentro de
  /// [snapToleranceMeters] — no hay ruta válida desde el punto.
  int? snapToGraph(double lat, double lon) {
    final vertex = _nearestVertexWithin(lat, lon, snapToleranceMeters);
    if (vertex != null) return vertex;
    final projection = _nearestProjectionWithin(lat, lon, snapToleranceMeters);
    if (projection == null) return null;
    return _splitEdge(
      projection.edgeId,
      projection.segmentIndex,
      projection.projected,
    );
  }

  /// Devuelve el camino real peatonal más corto entre (lat, lon) y (toLat,
  /// toLon) — snappeado al grafo.
  ///
  /// Devuelve null si no hay camino válido (sin conexión al grafo o Dijkstra
  /// sin ruta).
  WalkPath? shortestPath(double lat, double lon, double toLat, double toLon) {
    final from = snapToGraph(lat, lon);
    final to = snapToGraph(toLat, toLon);
    if (from == null || to == null) return null;
    final sequence = _dijkstra(from, to);
    if (sequence == null) return null;

    final points = <ShapePoint>[ShapePoint(lat, lon, 0)];
    var seq = 0;
    for (var i = 0; i + 1 < sequence.length; i++) {
      final edge = _edgeBetween(sequence[i], sequence[i + 1]);
      if (edge == null) {
        points.add(
          ShapePoint(
            _vertices[sequence[i + 1]].latitude,
            _vertices[sequence[i + 1]].longitude,
            ++seq,
          ),
        );
        continue;
      }
      for (var j = 1; j < edge.points.length; j++) {
        points.add(edge.points[j]);
      }
    }
    if (points.isEmpty ||
        points.last.latitude != toLat ||
        points.last.longitude != toLon) {
      points.add(ShapePoint(toLat, toLon, ++seq));
    }
    return WalkPath(points, _pathLength(points));
  }

  // --- snappeado (ajuste 2: proyección sobre el segmento peatonal) ---

  int? _nearestVertexWithin(double lat, double lon, double tol) {
    final cx = (lat / _cellSize).floor();
    final cy = (lon / _cellSize).floor();
    int? best;
    double bestDist = tol;
    for (final dx in [-2, -1, 0, 1, 2]) {
      for (final dy in [-2, -1, 0, 1, 2]) {
        final cell = _grid[(cx + dx, cy + dy)];
        if (cell == null) continue;
        for (final v in cell) {
          final p = _vertices[v];
          final d = _distanceMeters(lat, lon, p.latitude, p.longitude);
          if (d < bestDist) {
            bestDist = d;
            best = v;
          }
        }
      }
    }
    return best;
  }

  ({int edgeId, int segmentIndex, ShapePoint projected})?
  _nearestProjectionWithin(double lat, double lon, double tol) {
    int? bestEdge;
    int bestSegment = -1;
    ShapePoint? bestPoint;
    double bestDist = tol;
    for (var edgeId = 0; edgeId < _edges.length; edgeId++) {
      final edge = _edges[edgeId];
      for (var i = 0; i + 1 < edge.points.length; i++) {
        final projection = _projectOntoSegment(
          lat,
          lon,
          edge.points[i],
          edge.points[i + 1],
        );
        if (projection.distance < bestDist) {
          bestDist = projection.distance;
          bestEdge = edgeId;
          bestSegment = i;
          bestPoint = projection.point;
        }
      }
    }
    if (bestEdge == null || bestPoint == null) return null;
    return (edgeId: bestEdge, segmentIndex: bestSegment, projected: bestPoint);
  }

  ({ShapePoint point, double distance}) _projectOntoSegment(
    double lat,
    double lon,
    ShapePoint p0,
    ShapePoint p1,
  ) {
    final total = _pathLength([p0, p1]);
    final t = total == 0
        ? 0.0
        : ((lat - p0.latitude) * (p1.latitude - p0.latitude) +
                  (lon - p0.longitude) * (p1.longitude - p0.longitude)) /
              (total * total);
    final fraction = t.clamp(0.0, 1.0);
    final point = ShapePoint(
      p0.latitude + fraction * (p1.latitude - p0.latitude),
      p0.longitude + fraction * (p1.longitude - p0.longitude),
      0,
    );
    return (
      point: point,
      distance: _distanceMeters(lat, lon, point.latitude, point.longitude),
    );
  }

  int _splitEdge(int edgeId, int segmentIndex, ShapePoint projected) {
    final edge = _edges[edgeId];
    final vertexId = _vertices.length;
    _vertices.add(projected);
    // Registrar el vértice de split en la rejilla de snapping.
    final gridKey = (
      (projected.latitude / _cellSize).floor(),
      (projected.longitude / _cellSize).floor(),
    );
    (_grid[gridKey] ??= <int>[]).add(vertexId);
    // Aristas resultantes: [edge.a, projected] y [projected, edge.b].
    final points1 = List<ShapePoint>.of(
      edge.points.sublist(0, segmentIndex + 1),
    )..add(projected);
    final points2 = List<ShapePoint>.of([
      projected,
      ...edge.points.sublist(segmentIndex + 1),
    ]);
    _edges[edgeId] = _WalkEdge(
      edge.a,
      vertexId,
      _pathLength(points1),
      List.unmodifiable(points1),
    );
    final newEdgeId = _edges.length;
    _edges.add(
      _WalkEdge(
        vertexId,
        edge.b,
        _pathLength(points2),
        List.unmodifiable(points2),
      ),
    );
    while (_adj.length <= vertexId) {
      _adj.add(<int>[]);
    }
    _adj[vertexId] = <int>[edgeId, newEdgeId];
    _adj[edge.b].remove(edgeId);
    _adj[edge.b].add(newEdgeId);
    return vertexId;
  }

  // --- Dijkstra (ajuste 3: topología real del grafo) ---

  List<int>? _dijkstra(int from, int to) {
    final dist = List<double>.filled(_vertices.length, double.infinity);
    final prev = List<int>.filled(_vertices.length, -1);
    final closed = List<bool>.filled(_vertices.length, false);
    dist[from] = 0;
    final heap = SplayTreeSet<_DijkstraEntry>((a, b) {
      final c = a.dist.compareTo(b.dist);
      return c != 0 ? c : a.vertex.compareTo(b.vertex);
    });
    heap.add(_DijkstraEntry(0, from));
    while (heap.isNotEmpty) {
      final entry = heap.first;
      heap.remove(entry);
      final v = entry.vertex;
      if (closed[v]) continue;
      closed[v] = true;
      if (v == to) break;
      final d = dist[v];
      for (final edgeId in _adj[v]) {
        final edge = _edges[edgeId];
        final other = edge.a == v ? edge.b : edge.a;
        if (closed[other]) continue;
        final newDist = d + edge.length;
        if (newDist < dist[other]) {
          dist[other] = newDist;
          prev[other] = v;
          heap.add(_DijkstraEntry(newDist, other));
        }
      }
    }
    if (dist[to] == double.infinity) return null;
    final reversed = <int>[];
    for (var v = to; v != -1; v = prev[v]) {
      reversed.add(v);
    }
    return reversed.reversed.toList();
  }

  _WalkEdge? _edgeBetween(int a, int b) {
    for (final edgeId in _adj[a]) {
      final edge = _edges[edgeId];
      if ((edge.a == a && edge.b == b) || (edge.a == b && edge.b == a)) {
        return edge;
      }
    }
    return null;
  }

  // --- geometría ---

  static List<ShapePoint> _dedupe(List<ShapePoint> points) {
    if (points.isEmpty) return points;
    final result = [points.first];
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.latitude == result.last.latitude &&
          p.longitude == result.last.longitude) {
        continue;
      }
      result.add(p);
    }
    return result;
  }

  static double _pathLength(List<ShapePoint> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distanceMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a =
        math.pow(math.sin(dp / 2), 2) +
        math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }
}
