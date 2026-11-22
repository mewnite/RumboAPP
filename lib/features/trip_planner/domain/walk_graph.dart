import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';

import '../data/walk_graph_builder.dart';
import '../data/walk_graph_seed.dart';

class WalkPath {
  const WalkPath(this.points, this.lengthMeters, {this.gapMeters = 0});

  final List<ShapePoint> points;
  final double lengthMeters;
  final double gapMeters;
}

class WalkGraph {
  static const double snapGapDashedThresholdMeters = 5;
  static const double _cellSize = 0.0002;
  static const double _mainSnapToleranceMeters = 75;

  factory WalkGraph.fromWays(
    List<List<ShapePoint>> ways, {
    double snapToleranceMeters = 5,
    double mainSnapToleranceMeters = _mainSnapToleranceMeters,
    String sourceDate = '000000',
    String sourceSha256 =
        '0000000000000000000000000000000000000000000000000000000000000000',
  }) {
    final seed = buildWalkGraphSeedDataFromWays(ways);
    return WalkGraph._(
      _withSource(seed, sourceDate, sourceSha256),
      snapToleranceMeters: snapToleranceMeters,
      mainSnapToleranceMeters: mainSnapToleranceMeters,
      copySeedArrays: false,
    );
  }

  static WalkGraph? fromGeoJson(
    Map<String, dynamic> data, {
    double snapToleranceMeters = 5,
    double mainSnapToleranceMeters = _mainSnapToleranceMeters,
    String sourceDate = '000000',
    String sourceSha256 =
        '0000000000000000000000000000000000000000000000000000000000000000',
  }) {
    final seed = buildWalkGraphSeedDataFromGeoJson(data);
    if (seed == null || seed.vertexCount == 0) return null;
    return WalkGraph._(
      _withSource(seed, sourceDate, sourceSha256),
      snapToleranceMeters: snapToleranceMeters,
      mainSnapToleranceMeters: mainSnapToleranceMeters,
      copySeedArrays: false,
    );
  }

  factory WalkGraph.fromSeedBytes(Uint8List bytes) => WalkGraph._(
    WalkGraphSeedCodec.decode(bytes),
    snapToleranceMeters: 5,
    mainSnapToleranceMeters: 75,
    copySeedArrays: false,
  );

  factory WalkGraph.fromSeedData(WalkGraphSeedData seed) => WalkGraph._(
    seed,
    snapToleranceMeters: 5,
    mainSnapToleranceMeters: 75,
    copySeedArrays: true,
  );

  WalkGraph._(
    WalkGraphSeedData seed, {
    required this.snapToleranceMeters,
    required this.mainSnapToleranceMeters,
    required bool copySeedArrays,
  }) : _vertexCoordinates = copySeedArrays
           ? Int32List.fromList(seed.vertexCoordinates)
           : seed.vertexCoordinates,
       _edgeEndpoints = copySeedArrays
           ? Int32List.fromList(seed.edgeEndpoints)
           : seed.edgeEndpoints,
       _edgeLengthsMeters = copySeedArrays
           ? Float32List.fromList(seed.edgeLengthsMeters)
           : seed.edgeLengthsMeters,
       _edgeGeometryOffsets = copySeedArrays
           ? Int32List.fromList(seed.edgeGeometryOffsets)
           : seed.edgeGeometryOffsets,
       _edgeGeometryCoordinates = copySeedArrays
           ? Int32List.fromList(seed.edgeGeometryCoordinates)
           : seed.edgeGeometryCoordinates,
       _adjacencyOffsets = copySeedArrays
           ? Int32List.fromList(seed.adjacencyOffsets)
           : seed.adjacencyOffsets,
       _adjacencyEdgeIds = copySeedArrays
           ? Int32List.fromList(seed.adjacencyEdgeIds)
           : seed.adjacencyEdgeIds,
       sourceDate = seed.sourceDate,
       sourceSha256 = seed.sourceSha256,
       boundsMicrodegrees = copySeedArrays
           ? Int32List.fromList(seed.boundsMicrodegrees)
           : seed.boundsMicrodegrees,
       wayCount = seed.wayCount {
    _buildComponentIndex();
    _buildSpatialIndex();
  }

  final Int32List _vertexCoordinates;
  final Int32List _edgeEndpoints;
  final Float32List _edgeLengthsMeters;
  final Int32List _edgeGeometryOffsets;
  final Int32List _edgeGeometryCoordinates;
  final Int32List _adjacencyOffsets;
  final Int32List _adjacencyEdgeIds;
  final Int32List boundsMicrodegrees;
  final String sourceDate;
  final String sourceSha256;
  final int wayCount;
  final double snapToleranceMeters;
  final double mainSnapToleranceMeters;

  late final Int32List _componentIds;
  late final int _mainComponentId;
  late final Map<(int, int), List<int>> _vertexGrid;
  late final Map<(int, int), List<int>> _segmentGrid;
  late final Int32List _segmentEdgeIds;
  late final Int32List _segmentIndexes;

  int get vertexCount => _vertexCoordinates.length ~/ 2;
  int get edgeCount => _edgeLengthsMeters.length;
  int get geometryPointCount => _edgeGeometryCoordinates.length ~/ 2;

  int? snapToGraph(double lat, double lon) {
    final tolerance = math.max(snapToleranceMeters, mainSnapToleranceMeters);
    final vertex = _nearestVertex(lat, lon, tolerance);
    if (vertex != null) return vertex;
    final projection = _nearestProjection(lat, lon, tolerance);
    if (projection == null) return null;
    final a = _edgeEndpoints[projection.edgeId * 2];
    final b = _edgeEndpoints[projection.edgeId * 2 + 1];
    final distanceToA = _distanceMeters(lat, lon, _latitude(a), _longitude(a));
    final distanceToB = _distanceMeters(lat, lon, _latitude(b), _longitude(b));
    return distanceToA <= distanceToB ? a : b;
  }

  WalkGraphSeedData toSeedData() => WalkGraphSeedData(
    vertexCoordinates: Int32List.fromList(_vertexCoordinates),
    edgeEndpoints: Int32List.fromList(_edgeEndpoints),
    edgeLengthsMeters: Float32List.fromList(_edgeLengthsMeters),
    edgeGeometryOffsets: Int32List.fromList(_edgeGeometryOffsets),
    edgeGeometryCoordinates: Int32List.fromList(_edgeGeometryCoordinates),
    adjacencyOffsets: Int32List.fromList(_adjacencyOffsets),
    adjacencyEdgeIds: Int32List.fromList(_adjacencyEdgeIds),
    sourceDate: sourceDate,
    sourceSha256: sourceSha256,
    boundsMicrodegrees: Int32List.fromList(boundsMicrodegrees),
    wayCount: wayCount,
  );

  Uint8List toSeedBytes() => WalkGraphSeedCodec.encode(toSeedData());

  void _buildComponentIndex() {
    final components = Int32List(vertexCount)..fillRange(0, vertexCount, -1);
    var largestRoot = -1;
    var largestSize = 0;
    for (var start = 0; start < vertexCount; start++) {
      if (components[start] != -1) continue;
      components[start] = start;
      final stack = <int>[start];
      var size = 0;
      while (stack.isNotEmpty) {
        final vertex = stack.removeLast();
        size++;
        for (
          var i = _adjacencyOffsets[vertex];
          i < _adjacencyOffsets[vertex + 1];
          i++
        ) {
          final edgeId = _adjacencyEdgeIds[i];
          final a = _edgeEndpoints[edgeId * 2];
          final b = _edgeEndpoints[edgeId * 2 + 1];
          final other = a == vertex ? b : a;
          if (components[other] == -1) {
            components[other] = start;
            stack.add(other);
          }
        }
      }
      if (size > largestSize) {
        largestRoot = start;
        largestSize = size;
      }
    }
    _componentIds = components;
    _mainComponentId = largestRoot;
    developer.log(
      '[performance] walk_graph_component_index vertices=$vertexCount '
      'main=$largestSize',
      name: 'Rumbo',
    );
  }

  void _buildSpatialIndex() {
    final vertices = <(int, int), List<int>>{};
    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final cell = _cellFor(_latitude(vertex), _longitude(vertex));
      (vertices[cell] ??= <int>[]).add(vertex);
    }
    _vertexGrid = vertices;

    final segmentEdges = <int>[];
    final segmentIndexes = <int>[];
    final segments = <(int, int), List<int>>{};
    for (var edge = 0; edge < edgeCount; edge++) {
      final start = _edgeGeometryOffsets[edge];
      final end = _edgeGeometryOffsets[edge + 1];
      for (var point = start; point + 1 < end; point++) {
        final segmentId = segmentEdges.length;
        segmentEdges.add(edge);
        segmentIndexes.add(point - start);
        final lat1 = _geometryLatitude(point);
        final lon1 = _geometryLongitude(point);
        final lat2 = _geometryLatitude(point + 1);
        final lon2 = _geometryLongitude(point + 1);
        final samples =
            (math.max((lat2 - lat1).abs(), (lon2 - lon1).abs()) /
                    (_cellSize / 2))
                .ceil()
                .clamp(1, 20000);
        (int, int)? previousCell;
        for (var sample = 0; sample <= samples; sample++) {
          final fraction = sample / samples;
          final cell = _cellFor(
            lat1 + (lat2 - lat1) * fraction,
            lon1 + (lon2 - lon1) * fraction,
          );
          if (cell == previousCell) continue;
          (segments[cell] ??= <int>[]).add(segmentId);
          previousCell = cell;
        }
      }
    }
    _segmentGrid = segments;
    _segmentEdgeIds = Int32List.fromList(segmentEdges);
    _segmentIndexes = Int32List.fromList(segmentIndexes);
    developer.log(
      '[performance] walk_graph_spatial_index vertices=$vertexCount '
      'segments=${segmentEdges.length} cells=${segments.length}',
      name: 'Rumbo',
    );
  }

  WalkPath? shortestPath(double lat, double lon, double toLat, double toLon) {
    final totalWatch = Stopwatch()..start();
    final snapWatch = Stopwatch()..start();
    final from = _snap(lat, lon, 0);
    final to = _snap(toLat, toLon, 1);
    snapWatch.stop();
    if (from == null || to == null) return null;

    final dynamicNodeCount = vertexCount + 2;
    final longitudeScale = math.cos(to.point.latitude * math.pi / 180);
    final overlay = _buildOverlay([from, to]);
    final distances = List<double>.filled(dynamicNodeCount, double.infinity);
    final previousNodes = List<int>.filled(dynamicNodeCount, -1);
    final previousArcs = List<_RouteArc?>.filled(dynamicNodeCount, null);
    final closed = List<bool>.filled(dynamicNodeCount, false);
    distances[from.vertexId] = 0;
    final queue =
        SplayTreeSet<_DijkstraEntry>((a, b) {
          final priority = a.estimatedTotal.compareTo(b.estimatedTotal);
          if (priority != 0) return priority;
          final distance = a.distance.compareTo(b.distance);
          return distance != 0 ? distance : a.vertex.compareTo(b.vertex);
        })..add(
          _DijkstraEntry(
            0,
            _heuristicDistance(from.vertexId, from, to, longitudeScale),
            from.vertexId,
          ),
        );
    var settledVertices = 0;

    while (queue.isNotEmpty) {
      final current = queue.first;
      queue.remove(current);
      if (closed[current.vertex] ||
          current.distance != distances[current.vertex]) {
        continue;
      }
      closed[current.vertex] = true;
      settledVertices++;
      if (current.vertex == to.vertexId) break;
      final start = current.vertex < vertexCount
          ? _adjacencyOffsets[current.vertex]
          : 0;
      final end = current.vertex < vertexCount
          ? _adjacencyOffsets[current.vertex + 1]
          : 0;
      for (var i = start; i < end; i++) {
        final edgeId = _adjacencyEdgeIds[i];
        final a = _edgeEndpoints[edgeId * 2];
        final b = _edgeEndpoints[edgeId * 2 + 1];
        final next = a == current.vertex ? b : a;
        final arc = _RouteArc(
          from: current.vertex,
          to: next,
          edgeId: edgeId,
          reverse: b == current.vertex,
          lengthMeters: _edgeLengthsMeters[edgeId],
        );
        _relax(
          arc,
          current.distance,
          distances,
          previousNodes,
          previousArcs,
          closed,
          queue,
          from,
          to,
          longitudeScale,
        );
      }
      for (final arc in overlay[current.vertex] ?? const <_RouteArc>[]) {
        _relax(
          arc,
          current.distance,
          distances,
          previousNodes,
          previousArcs,
          closed,
          queue,
          from,
          to,
          longitudeScale,
        );
      }
    }
    if (distances[to.vertexId] == double.infinity) return null;

    final route = <_RouteArc>[];
    for (var vertex = to.vertexId; vertex != from.vertexId;) {
      final arc = previousArcs[vertex];
      if (arc == null) return null;
      route.add(arc);
      vertex = previousNodes[vertex];
    }
    final points = <ShapePoint>[ShapePoint(lat, lon, 0)];
    var index = 0;
    var gapMeters = 0.0;
    if (from.gapMeters > snapGapDashedThresholdMeters) {
      _appendPoint(points, from.point, ++index);
      gapMeters += from.gapMeters;
    }
    for (final arc in route.reversed) {
      final arcPoints = arc.edgeId == null
          ? arc.points!
          : _edgePoints(arc.edgeId!, reverse: arc.reverse);
      for (var i = 1; i < arcPoints.length; i++) {
        _appendPoint(points, arcPoints[i], ++index);
      }
    }
    if (to.gapMeters > snapGapDashedThresholdMeters) {
      _appendPoint(points, to.point, ++index);
      _appendPoint(points, ShapePoint(toLat, toLon, index + 1), ++index);
      gapMeters += to.gapMeters;
    } else {
      _appendPoint(points, ShapePoint(toLat, toLon, index + 1), ++index);
    }
    final result = WalkPath(
      List<ShapePoint>.unmodifiable(points),
      distances[to.vertexId] + from.gapMeters + to.gapMeters,
      gapMeters: gapMeters,
    );
    totalWatch.stop();
    developer.log(
      '[performance] walk_graph_path=${totalWatch.elapsedMilliseconds}ms '
      'snap=${snapWatch.elapsedMilliseconds}ms settled=$settledVertices '
      'points=${result.points.length}',
      name: 'Rumbo',
    );
    return result;
  }

  void _relax(
    _RouteArc arc,
    double currentDistance,
    List<double> distances,
    List<int> previousNodes,
    List<_RouteArc?> previousArcs,
    List<bool> closed,
    SplayTreeSet<_DijkstraEntry> queue,
    _Snap from,
    _Snap to,
    double longitudeScale,
  ) {
    if (closed[arc.to]) return;
    final nextDistance = currentDistance + arc.lengthMeters;
    if (nextDistance >= distances[arc.to]) return;
    distances[arc.to] = nextDistance;
    previousNodes[arc.to] = arc.from;
    previousArcs[arc.to] = arc;
    final targetDistance = _heuristicDistance(arc.to, from, to, longitudeScale);
    queue.add(
      _DijkstraEntry(nextDistance, nextDistance + targetDistance, arc.to),
    );
  }

  double _heuristicDistance(
    int vertex,
    _Snap from,
    _Snap to,
    double longitudeScale,
  ) {
    if (vertex == to.vertexId) return 0;
    final point = vertex == from.vertexId ? from.point : _vertexPoint(vertex);
    final x = (point.longitude - to.point.longitude) * 111320 * longitudeScale;
    final y = (point.latitude - to.point.latitude) * 110574;
    return math.sqrt(x * x + y * y) * .99;
  }

  Map<int, List<_RouteArc>> _buildOverlay(List<_Snap> snaps) {
    final overlay = <int, List<_RouteArc>>{};
    final byEdge = <int, List<_Snap>>{};
    for (final snap in snaps) {
      final edgeId = snap.edgeId;
      if (edgeId != null) (byEdge[edgeId] ??= <_Snap>[]).add(snap);
    }
    for (final entry in byEdge.entries) {
      final edgeId = entry.key;
      final points = _edgePoints(edgeId);
      final totalLength = _polylineLength(points);
      final startVertex = _edgeEndpoints[edgeId * 2];
      final endVertex = _edgeEndpoints[edgeId * 2 + 1];
      final anchors = <_EdgeAnchor>[
        _EdgeAnchor(0, startVertex, points.first),
        for (final snap in entry.value)
          _EdgeAnchor(snap.distanceAlongEdge, snap.vertexId, snap.point),
        _EdgeAnchor(totalLength, endVertex, points.last),
      ]..sort((a, b) => a.distanceAlong.compareTo(b.distanceAlong));
      for (var i = 0; i + 1 < anchors.length; i++) {
        final start = anchors[i];
        final end = anchors[i + 1];
        if (start.vertexId == end.vertexId) continue;
        final segment = _slicePolyline(
          points,
          start.distanceAlong,
          end.distanceAlong,
        );
        _addOverlayArc(
          overlay,
          _RouteArc(
            from: start.vertexId,
            to: end.vertexId,
            points: segment,
            lengthMeters: end.distanceAlong - start.distanceAlong,
          ),
        );
        _addOverlayArc(
          overlay,
          _RouteArc(
            from: end.vertexId,
            to: start.vertexId,
            points: segment.reversed.toList(growable: false),
            lengthMeters: end.distanceAlong - start.distanceAlong,
          ),
        );
      }
    }
    return overlay;
  }

  void _addOverlayArc(Map<int, List<_RouteArc>> overlay, _RouteArc arc) {
    (overlay[arc.from] ??= <_RouteArc>[]).add(arc);
  }

  _Snap? _snap(double lat, double lon, int snapIndex) {
    final tolerance = math.max(snapToleranceMeters, mainSnapToleranceMeters);
    final vertex = _nearestVertex(lat, lon, tolerance);
    _Snap? vertexSnap;
    if (vertex != null && _componentIds[vertex] == _mainComponentId) {
      final point = _vertexPoint(vertex);
      vertexSnap = _Snap(
        vertexId: vertex,
        point: point,
        gapMeters: _distanceMeters(lat, lon, point.latitude, point.longitude),
      );
    }
    final projection = _nearestProjection(lat, lon, tolerance);
    if (projection == null ||
        (vertexSnap != null &&
            vertexSnap.gapMeters <= projection.distanceMeters)) {
      return vertexSnap;
    }
    final edge = projection.edgeId;
    final a = _edgeEndpoints[edge * 2];
    final b = _edgeEndpoints[edge * 2 + 1];
    if (_componentIds[a] != _mainComponentId &&
        _componentIds[b] != _mainComponentId) {
      return null;
    }
    return _Snap(
      vertexId: vertexCount + snapIndex,
      point: projection.point,
      gapMeters: projection.distanceMeters,
      edgeId: edge,
      distanceAlongEdge: projection.distanceAlongEdge,
    );
  }

  int? _nearestVertex(double lat, double lon, double tolerance) {
    final cells = _searchCells(lat, lon, tolerance);
    int? best;
    var bestDistanceSquared = tolerance * tolerance;
    final longitudeScale = math.cos(lat * math.pi / 180);
    for (final cell in cells) {
      for (final vertex in _vertexGrid[cell] ?? const <int>[]) {
        if (_componentIds[vertex] != _mainComponentId) continue;
        final latitudeDistance = (_latitude(vertex) - lat) * 110574;
        final longitudeDistance =
            (_longitude(vertex) - lon) * 111320 * longitudeScale;
        final distanceSquared =
            latitudeDistance * latitudeDistance +
            longitudeDistance * longitudeDistance;
        if (distanceSquared < bestDistanceSquared) {
          best = vertex;
          bestDistanceSquared = distanceSquared;
        }
      }
    }
    if (best == null ||
        _distanceMeters(lat, lon, _latitude(best), _longitude(best)) >=
            tolerance) {
      return null;
    }
    return best;
  }

  _Projection? _nearestProjection(double lat, double lon, double tolerance) {
    final cells = _searchCells(lat, lon, tolerance);
    final candidateIds = <int>{};
    for (final cell in cells) {
      candidateIds.addAll(_segmentGrid[cell] ?? const <int>[]);
    }
    int? bestEdge;
    var bestSegmentIndex = -1;
    ShapePoint? bestPoint;
    var bestDistanceSquared = tolerance * tolerance;
    for (final segmentId in candidateIds) {
      final edgeId = _segmentEdgeIds[segmentId];
      final a = _edgeEndpoints[edgeId * 2];
      final b = _edgeEndpoints[edgeId * 2 + 1];
      if (_componentIds[a] != _mainComponentId &&
          _componentIds[b] != _mainComponentId) {
        continue;
      }
      final segmentIndex = _segmentIndexes[segmentId];
      final pointIndex = _edgeGeometryOffsets[edgeId] + segmentIndex;
      final start = _geometryPoint(pointIndex);
      final end = _geometryPoint(pointIndex + 1);
      final projected = _project(lat, lon, start, end);
      final distanceSquared = projected.distance * projected.distance;
      if (distanceSquared >= bestDistanceSquared) continue;
      bestEdge = edgeId;
      bestSegmentIndex = segmentIndex;
      bestPoint = projected.point;
      bestDistanceSquared = distanceSquared;
    }
    if (bestEdge == null || bestPoint == null) return null;
    final exactDistance = _distanceMeters(
      lat,
      lon,
      bestPoint.latitude,
      bestPoint.longitude,
    );
    if (exactDistance >= tolerance) return null;
    final result = _Projection(
      edgeId: bestEdge,
      point: bestPoint,
      distanceMeters: exactDistance,
      distanceAlongEdge: _distanceAlongEdge(
        bestEdge,
        bestSegmentIndex,
        bestPoint,
      ),
    );
    return result;
  }

  double _distanceAlongEdge(int edgeId, int segmentIndex, ShapePoint point) {
    var distance = 0.0;
    final start = _edgeGeometryOffsets[edgeId];
    for (var i = 0; i < segmentIndex; i++) {
      distance += _distanceMeters(
        _geometryLatitude(start + i),
        _geometryLongitude(start + i),
        _geometryLatitude(start + i + 1),
        _geometryLongitude(start + i + 1),
      );
    }
    final segmentStart = _geometryPoint(start + segmentIndex);
    distance += _distanceMeters(
      segmentStart.latitude,
      segmentStart.longitude,
      point.latitude,
      point.longitude,
    );
    return distance;
  }

  ({ShapePoint point, double distance}) _project(
    double lat,
    double lon,
    ShapePoint start,
    ShapePoint end,
  ) {
    final longitudeScale = math.cos(lat * math.pi / 180);
    final x = (start.longitude - lon) * 111320 * longitudeScale;
    final y = (start.latitude - lat) * 110574;
    final dx = (end.longitude - start.longitude) * 111320 * longitudeScale;
    final dy = (end.latitude - start.latitude) * 110574;
    final denominator = dx * dx + dy * dy;
    final fraction = denominator == 0
        ? 0.0
        : (-(x * dx + y * dy) / denominator).clamp(0.0, 1.0);
    final point = ShapePoint(
      start.latitude + fraction * (end.latitude - start.latitude),
      start.longitude + fraction * (end.longitude - start.longitude),
      0,
    );
    return (
      point: point,
      distance: math.sqrt(
        math.pow(x + fraction * dx, 2) + math.pow(y + fraction * dy, 2),
      ),
    );
  }

  List<(int, int)> _searchCells(double lat, double lon, double tolerance) {
    final latDegrees = tolerance / 111320;
    final lonDegrees =
        tolerance /
        (111320 * math.cos(lat * math.pi / 180).abs().clamp(0.2, 1.0));
    final minLat = ((lat - latDegrees) / _cellSize).floor();
    final maxLat = ((lat + latDegrees) / _cellSize).floor();
    final minLon = ((lon - lonDegrees) / _cellSize).floor();
    final maxLon = ((lon + lonDegrees) / _cellSize).floor();
    final cells = <(int, int)>[];
    for (var x = minLat; x <= maxLat; x++) {
      for (var y = minLon; y <= maxLon; y++) {
        cells.add((x, y));
      }
    }
    return cells;
  }

  static (int, int) _cellFor(double lat, double lon) =>
      ((lat / _cellSize).floor(), (lon / _cellSize).floor());

  List<ShapePoint> _edgePoints(int edgeId, {bool reverse = false}) {
    final points = <ShapePoint>[];
    final start = _edgeGeometryOffsets[edgeId];
    final end = _edgeGeometryOffsets[edgeId + 1];
    for (var i = start; i < end; i++) {
      points.add(_geometryPoint(i));
    }
    return reverse ? points.reversed.toList(growable: false) : points;
  }

  List<ShapePoint> _slicePolyline(
    List<ShapePoint> points,
    double fromDistance,
    double toDistance,
  ) {
    final reversed = fromDistance > toDistance;
    final start = math.min(fromDistance, toDistance);
    final end = math.max(fromDistance, toDistance);
    final cumulative = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      cumulative[i] =
          cumulative[i - 1] +
          _distanceMeters(
            points[i - 1].latitude,
            points[i - 1].longitude,
            points[i].latitude,
            points[i].longitude,
          );
    }
    ShapePoint at(double distance) {
      if (distance <= 0) return points.first;
      if (distance >= cumulative.last) return points.last;
      for (var i = 0; i + 1 < cumulative.length; i++) {
        if (distance <= cumulative[i + 1]) {
          final segmentLength = cumulative[i + 1] - cumulative[i];
          final fraction = segmentLength == 0
              ? 0.0
              : (distance - cumulative[i]) / segmentLength;
          return ShapePoint(
            points[i].latitude +
                fraction * (points[i + 1].latitude - points[i].latitude),
            points[i].longitude +
                fraction * (points[i + 1].longitude - points[i].longitude),
            0,
          );
        }
      }
      return points.last;
    }

    final result = <ShapePoint>[at(start)];
    for (var i = 1; i + 1 < points.length; i++) {
      if (cumulative[i] > start && cumulative[i] < end) {
        result.add(points[i]);
      }
    }
    result.add(at(end));
    return reversed ? result.reversed.toList(growable: false) : result;
  }

  ShapePoint _vertexPoint(int vertex) =>
      ShapePoint(_latitude(vertex), _longitude(vertex), vertex);

  ShapePoint _geometryPoint(int point) =>
      ShapePoint(_geometryLatitude(point), _geometryLongitude(point), point);

  double _latitude(int vertex) => _vertexCoordinates[vertex * 2] / 1000000;
  double _longitude(int vertex) => _vertexCoordinates[vertex * 2 + 1] / 1000000;
  double _geometryLatitude(int point) =>
      _edgeGeometryCoordinates[point * 2] / 1000000;
  double _geometryLongitude(int point) =>
      _edgeGeometryCoordinates[point * 2 + 1] / 1000000;

  static double _polylineLength(List<ShapePoint> points) {
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
    const radius = 6371000.0;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lon2 - lon1) * math.pi / 180;
    final a =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
    return 2 * radius * math.asin(math.sqrt(a));
  }

  static void _appendPoint(
    List<ShapePoint> points,
    ShapePoint point,
    int index,
  ) {
    if (points.isNotEmpty &&
        points.last.latitude == point.latitude &&
        points.last.longitude == point.longitude) {
      return;
    }
    points.add(ShapePoint(point.latitude, point.longitude, index));
  }

  static WalkGraphSeedData _withSource(
    WalkGraphSeedData data,
    String sourceDate,
    String sourceSha256,
  ) => WalkGraphSeedData(
    vertexCoordinates: data.vertexCoordinates,
    edgeEndpoints: data.edgeEndpoints,
    edgeLengthsMeters: data.edgeLengthsMeters,
    edgeGeometryOffsets: data.edgeGeometryOffsets,
    edgeGeometryCoordinates: data.edgeGeometryCoordinates,
    adjacencyOffsets: data.adjacencyOffsets,
    adjacencyEdgeIds: data.adjacencyEdgeIds,
    sourceDate: sourceDate,
    sourceSha256: sourceSha256,
    boundsMicrodegrees: data.boundsMicrodegrees,
    wayCount: data.wayCount,
  );
}

class _DijkstraEntry {
  const _DijkstraEntry(this.distance, this.estimatedTotal, this.vertex);

  final double distance;
  final double estimatedTotal;
  final int vertex;
}

class _Snap {
  const _Snap({
    required this.vertexId,
    required this.point,
    required this.gapMeters,
    this.edgeId,
    this.distanceAlongEdge = 0,
  });

  final int vertexId;
  final ShapePoint point;
  final double gapMeters;
  final int? edgeId;
  final double distanceAlongEdge;
}

class _Projection {
  const _Projection({
    required this.edgeId,
    required this.point,
    required this.distanceMeters,
    required this.distanceAlongEdge,
  });

  final int edgeId;
  final ShapePoint point;
  final double distanceMeters;
  final double distanceAlongEdge;
}

class _EdgeAnchor {
  const _EdgeAnchor(this.distanceAlong, this.vertexId, this.point);

  final double distanceAlong;
  final int vertexId;
  final ShapePoint point;
}

class _RouteArc {
  const _RouteArc({
    required this.from,
    required this.to,
    required this.lengthMeters,
    this.edgeId,
    this.reverse = false,
    this.points,
  });

  final int from;
  final int to;
  final double lengthMeters;
  final int? edgeId;
  final bool reverse;
  final List<ShapePoint>? points;
}
