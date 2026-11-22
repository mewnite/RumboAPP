import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';

import 'walk_graph_seed.dart';

const _vertexCellSize = 0.0002;

WalkGraphSeedData buildWalkGraphSeedDataFromWays(List<List<ShapePoint>> ways) =>
    _MutableWalkGraphBuilder.fromWays(ways).toSeedData();

WalkGraphSeedData? buildWalkGraphSeedDataFromGeoJson(
  Map<String, dynamic> data,
) => _MutableWalkGraphBuilder.fromGeoJson(data)?.toSeedData();

bool _isPedestrianWay(Map<String, dynamic> tags) {
  final highway = tags['highway'];
  final foot = tags['foot'];
  if (foot == 'no' || tags['access'] == 'private') return false;
  final barrier = tags['barrier'];
  if (barrier == 'wall' || barrier == 'fence') return false;
  if (highway == 'construction' || highway == 'proposed') return false;
  if (highway == 'motorway' ||
      highway == 'motorway_link' ||
      highway == 'trunk' ||
      highway == 'trunk_link') {
    return foot == 'yes';
  }
  return const {
    'footway',
    'path',
    'pedestrian',
    'steps',
    'living_street',
    'residential',
    'service',
    'track',
    'unclassified',
    'tertiary',
    'secondary',
    'primary',
    'primary_link',
    'secondary_link',
    'tertiary_link',
  }.contains(highway);
}

class _BuiltEdge {
  const _BuiltEdge(this.a, this.b, this.points, this.lengthMeters);

  final int a;
  final int b;
  final List<ShapePoint> points;
  final double lengthMeters;
}

class _MutableWalkGraphBuilder {
  factory _MutableWalkGraphBuilder.fromWays(List<List<ShapePoint>> ways) {
    final builder = _MutableWalkGraphBuilder._();
    builder._build(ways);
    return builder;
  }

  static _MutableWalkGraphBuilder? fromGeoJson(Map<String, dynamic> data) {
    final elements = data['elements'];
    if (elements is! List) return null;
    final ways = <List<ShapePoint>>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic> || element['type'] != 'way') {
        continue;
      }
      final tags = element['tags'];
      if (tags is! Map<String, dynamic> || !_isPedestrianWay(tags)) continue;
      final geometry = element['geometry'];
      if (geometry is! List) continue;
      final points = <ShapePoint>[];
      for (final point in geometry) {
        if (point is Map<String, dynamic>) {
          final latitude = (point['lat'] as num?)?.toDouble();
          final longitude = (point['lon'] as num?)?.toDouble();
          if (latitude != null && longitude != null) {
            points.add(ShapePoint(latitude, longitude, points.length));
          }
        } else if (point is List &&
            point.length >= 2 &&
            point[0] is num &&
            point[1] is num) {
          points.add(
            ShapePoint(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
              points.length,
            ),
          );
        }
      }
      if (points.length >= 2) ways.add(points);
    }
    return _MutableWalkGraphBuilder.fromWays(ways);
  }

  _MutableWalkGraphBuilder._();

  final List<ShapePoint> _vertices = [];
  final List<_BuiltEdge> _edges = [];
  final List<List<int>> _adjacency = [];
  final Map<(int, int), List<int>> _vertexGrid = {};
  int _wayCount = 0;

  WalkGraphSeedData toSeedData() {
    final vertexCoordinates = Int32List(_vertices.length * 2);
    for (var i = 0; i < _vertices.length; i++) {
      vertexCoordinates[i * 2] = (_vertices[i].latitude * 1000000).round();
      vertexCoordinates[i * 2 + 1] = (_vertices[i].longitude * 1000000).round();
    }

    final edgeEndpoints = Int32List(_edges.length * 2);
    final edgeLengths = Float32List(_edges.length);
    final geometryOffsets = Int32List(_edges.length + 1);
    final geometryCoordinates = <int>[];
    for (var edgeId = 0; edgeId < _edges.length; edgeId++) {
      final edge = _edges[edgeId];
      edgeEndpoints[edgeId * 2] = edge.a;
      edgeEndpoints[edgeId * 2 + 1] = edge.b;
      edgeLengths[edgeId] = edge.lengthMeters;
      geometryOffsets[edgeId] = geometryCoordinates.length ~/ 2;
      for (final point in edge.points) {
        geometryCoordinates
          ..add((point.latitude * 1000000).round())
          ..add((point.longitude * 1000000).round());
      }
    }
    geometryOffsets[_edges.length] = geometryCoordinates.length ~/ 2;

    final adjacencyOffsets = Int32List(_vertices.length + 1);
    final adjacencyEdgeIds = <int>[];
    for (var vertex = 0; vertex < _vertices.length; vertex++) {
      adjacencyOffsets[vertex] = adjacencyEdgeIds.length;
      adjacencyEdgeIds.addAll(_adjacency[vertex]);
    }
    adjacencyOffsets[_vertices.length] = adjacencyEdgeIds.length;

    var minLatitude = 0.0;
    var minLongitude = 0.0;
    var maxLatitude = 0.0;
    var maxLongitude = 0.0;
    if (_vertices.isNotEmpty) {
      minLatitude = maxLatitude = _vertices.first.latitude;
      minLongitude = maxLongitude = _vertices.first.longitude;
      for (final point in _vertices.skip(1)) {
        minLatitude = math.min(minLatitude, point.latitude);
        minLongitude = math.min(minLongitude, point.longitude);
        maxLatitude = math.max(maxLatitude, point.latitude);
        maxLongitude = math.max(maxLongitude, point.longitude);
      }
    }
    return WalkGraphSeedData(
      vertexCoordinates: vertexCoordinates,
      edgeEndpoints: edgeEndpoints,
      edgeLengthsMeters: edgeLengths,
      edgeGeometryOffsets: geometryOffsets,
      edgeGeometryCoordinates: Int32List.fromList(geometryCoordinates),
      adjacencyOffsets: adjacencyOffsets,
      adjacencyEdgeIds: Int32List.fromList(adjacencyEdgeIds),
      sourceDate: '000000',
      sourceSha256: List.filled(64, '0').join(),
      boundsMicrodegrees: Int32List.fromList([
        (minLatitude * 1000000).round(),
        (minLongitude * 1000000).round(),
        (maxLatitude * 1000000).round(),
        (maxLongitude * 1000000).round(),
      ]),
      wayCount: _wayCount,
    );
  }

  void _build(List<List<ShapePoint>> ways) {
    for (final way in ways) {
      final points = _dedupe(way);
      if (points.length < 2) continue;
      _wayCount++;
      var previousVertex = _addVertex(points.first);
      var previousPointIndex = 0;
      for (var i = 1; i < points.length; i++) {
        final nextVertex = _addVertex(points[i]);
        if (nextVertex != previousVertex) {
          final geometry = points.sublist(previousPointIndex, i + 1);
          geometry[0] = _vertices[previousVertex];
          geometry[geometry.length - 1] = _vertices[nextVertex];
          final edgeId = _edges.length;
          _edges.add(
            _BuiltEdge(
              previousVertex,
              nextVertex,
              List<ShapePoint>.unmodifiable(geometry),
              _pathLength(geometry),
            ),
          );
          _adjacency[previousVertex].add(edgeId);
          _adjacency[nextVertex].add(edgeId);
        }
        previousVertex = nextVertex;
        previousPointIndex = i;
      }
    }
  }

  int _addVertex(ShapePoint point) {
    final cell = _cell(point.latitude, point.longitude);
    int? nearest;
    var nearestDistance = 5.0;
    for (var dx = -2; dx <= 2; dx++) {
      for (var dy = -2; dy <= 2; dy++) {
        for (final candidate
            in _vertexGrid[(cell.$1 + dx, cell.$2 + dy)] ?? const <int>[]) {
          final existing = _vertices[candidate];
          final distance = _distanceMeters(
            point.latitude,
            point.longitude,
            existing.latitude,
            existing.longitude,
          );
          if (distance < nearestDistance) {
            nearest = candidate;
            nearestDistance = distance;
          }
        }
      }
    }
    if (nearest != null) return nearest;
    final id = _vertices.length;
    _vertices.add(point);
    _adjacency.add(<int>[]);
    (_vertexGrid[cell] ??= <int>[]).add(id);
    return id;
  }

  static (int, int) _cell(double latitude, double longitude) => (
    (latitude / _vertexCellSize).floor(),
    (longitude / _vertexCellSize).floor(),
  );

  static List<ShapePoint> _dedupe(List<ShapePoint> points) {
    if (points.isEmpty) return points;
    final result = <ShapePoint>[points.first];
    for (final point in points.skip(1)) {
      if (point.latitude != result.last.latitude ||
          point.longitude != result.last.longitude) {
        result.add(point);
      }
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
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lon2 - lon1) * math.pi / 180;
    final a =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }
}
