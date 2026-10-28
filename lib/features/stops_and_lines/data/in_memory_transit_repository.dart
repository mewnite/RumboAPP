import 'dart:math' as math;

import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';
import 'gtfs_parser.dart';

/// Read-only transit repository for web, where sqflite is unavailable.
///
/// It indexes the compact GTFS trip patterns once, then serves the same domain
/// queries as the native SQLite repository without sending data to a server.
class InMemoryTransitRepository implements TransitRepository {
  InMemoryTransitRepository(GtfsParseResult? feed, {FeedStatus? status})
    : _stops = feed?.stops ?? const [],
      _routes = feed?.routes ?? const [],
      _variants = feed?.variants ?? const [],
      _trips = feed?.trips ?? const [],
      _calendars = feed?.calendars ?? const [],
      _shapesById = {
        for (final shape in feed?.shapes ?? const <Shape>[]) shape.id: shape,
      },
      _status = status ?? const FeedStatus() {
    final patterns = feed?.patterns;
    _patternsById = {
      for (final pattern in patterns ?? const <TripPattern>[])
        pattern.id: pattern,
    };
    if (_patternsById.isEmpty && feed != null && feed.stopTimes.isNotEmpty) {
      final (computed, tripPatternIds, tripStartSecs) =
          computePatternsFromTimes(feed.stopTimes);
      _patternsById = {for (final pattern in computed) pattern.id: pattern};
      _trips = [
        for (final trip in feed.trips)
          Trip(
            id: trip.id,
            routeId: trip.routeId,
            serviceId: trip.serviceId,
            variantId: trip.variantId,
            headsign: trip.headsign,
            patternId: trip.patternId ?? tripPatternIds[trip.id],
            startSecs: trip.startSecs ?? tripStartSecs[trip.id],
          ),
      ];
    }
    _indexData();
  }

  final List<Stop> _stops;
  final List<Route> _routes;
  final List<RouteVariant> _variants;
  List<Trip> _trips;
  final List<ServiceCalendar> _calendars;
  final Map<String, Shape> _shapesById;
  final FeedStatus _status;
  late Map<String, TripPattern> _patternsById;
  late final Map<String, Stop> _stopsById = {
    for (final stop in _stops) stop.id: stop,
  };
  late final Map<String, Route> _routesById = {
    for (final route in _routes) route.id: route,
  };
  late final Map<String, RouteVariant> _variantsById = {
    for (final variant in _variants) variant.id: variant,
  };
  late final Map<int, RouteVariant> _variantsByExternalId = {
    for (final variant in _variants)
      if (variant.externalVariantId != null)
        variant.externalVariantId!: variant,
  };
  late final Map<String, List<RouteVariant>> _variantsByRoute = {};
  late final Map<String, List<Trip>> _tripsByVariant = {};
  late final Map<String, List<_TripAtStop>> _tripsAtStop = {};
  late final Map<String, ServiceCalendar> _calendarsById = {
    for (final calendar in _calendars) calendar.serviceId: calendar,
  };

  void _indexData() {
    for (final variant in _variants) {
      _variantsByRoute.putIfAbsent(variant.routeId, () => []).add(variant);
    }
    for (final trip in _trips) {
      _tripsByVariant.putIfAbsent(trip.variantId, () => []).add(trip);
      final patternId = trip.patternId;
      final pattern = patternId == null ? null : _patternsById[patternId];
      if (pattern == null) continue;
      for (final stop in pattern.stops) {
        _tripsAtStop
            .putIfAbsent(stop.stopId, () => [])
            .add(_TripAtStop(trip, stop));
      }
    }
  }

  @override
  Future<List<Stop>> nearbyStops(
    double latitude,
    double longitude,
    double radiusMeters,
  ) async {
    if (radiusMeters < 0) return const [];
    final candidates = [
      for (final stop in _stops)
        (
          stop: stop,
          distance: _distance(
            latitude,
            longitude,
            stop.latitude,
            stop.longitude,
          ),
        ),
    ]..removeWhere((item) => item.distance > radiusMeters);
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    return candidates.map((item) => item.stop).toList(growable: false);
  }

  @override
  Future<List<Stop>> searchStops(String query, {int limit = 25}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || limit <= 0) return const [];
    return _stops
        .where(
          (stop) =>
              stop.name.toLowerCase().contains(normalized) ||
              stop.code.toLowerCase().contains(normalized),
        )
        .take(limit.clamp(1, 100))
        .toList(growable: false);
  }

  @override
  Future<Stop?> stopById(String id) async => _stopsById[id];

  @override
  Future<List<Route>> routesForStop(String stopId) async {
    final routeIds = _tripsAtStop[stopId]
        ?.map((entry) => entry.trip.routeId)
        .toSet();
    if (routeIds == null) return const [];
    return [
      for (final route in _routes)
        if (routeIds.contains(route.id)) route,
    ];
  }

  @override
  Future<Map<String, List<Route>>> routesForStops(Set<String> stopIds) async =>
      {for (final stopId in stopIds) stopId: await routesForStop(stopId)};

  @override
  Future<Route?> routeById(String id) async => _routesById[id];

  @override
  Future<List<RouteVariant>> variantsForRoute(String routeId) async =>
      _variantsByRoute[routeId] ?? const [];

  @override
  Future<RouteVariant?> variantByExternalId(int externalVariantId) async =>
      _variantsByExternalId[externalVariantId];

  @override
  Future<Shape?> shapeForVariant(String variantId) async {
    final shapeId = _variantsById[variantId]?.shapeId;
    return shapeId == null ? null : _shapesById[shapeId];
  }

  @override
  Future<List<Stop>> stopsForVariant(String variantId) async {
    final trips = _tripsByVariant[variantId] ?? const [];
    final patterns = <String, int>{};
    for (final trip in trips) {
      final id = trip.patternId;
      if (id != null && _patternsById.containsKey(id)) {
        patterns.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    if (patterns.isEmpty) return const [];
    final patternId = patterns.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    return [
      for (final item in _patternsById[patternId]!.stops)
        if (_stopsById[item.stopId] case final Stop stop) stop,
    ];
  }

  @override
  Future<List<DateTime>> upcomingDeparturesForVariant(
    String variantId,
    DateTime now, {
    int limit = 10,
  }) async {
    final dates = <DateTime>{};
    final serviceDay = DateTime(now.year, now.month, now.day);
    for (final trip in _tripsByVariant[variantId] ?? const []) {
      final calendar = _calendarsById[trip.serviceId];
      final startSecs = trip.startSecs;
      if (calendar == null || startSecs == null) continue;
      for (var offset = -1; offset <= 0; offset++) {
        final day = serviceDay.add(Duration(days: offset));
        final departure = day.add(Duration(seconds: startSecs));
        if (calendar.activeOn(day) && !departure.isBefore(now)) {
          dates.add(departure);
        }
      }
    }
    final sorted = dates.toList()..sort();
    return sorted.take(limit.clamp(0, sorted.length)).toList(growable: false);
  }

  @override
  Future<List<UpcomingDeparture>> upcomingDepartures(
    String stopId,
    DateTime now, {
    int limit = 10,
  }) async {
    final serviceDay = DateTime(now.year, now.month, now.day);
    final results = <UpcomingDeparture>[];
    for (final entry in _tripsAtStop[stopId] ?? const []) {
      final trip = entry.trip;
      final calendar = _calendarsById[trip.serviceId];
      if (calendar == null || trip.startSecs == null) continue;
      final row = StopTime(
        tripId: trip.id,
        stopId: stopId,
        arrivalSeconds: trip.startSecs! + entry.stop.arrivalOffsetSecs,
        departureSeconds: trip.startSecs! + entry.stop.departureOffsetSecs,
        sequence: entry.stop.ordinal,
      );
      for (var offset = -1; offset <= 0; offset++) {
        final day = serviceDay.add(Duration(days: offset));
        final departure = day.add(Duration(seconds: row.departureSeconds));
        if (calendar.activeOn(day) && !departure.isBefore(now)) {
          results.add(
            UpcomingDeparture(trip: trip, stopTime: row, departure: departure),
          );
        }
      }
    }
    results.sort((a, b) => a.departure.compareTo(b.departure));
    return results.take(limit.clamp(0, results.length)).toList(growable: false);
  }

  @override
  Future<TransitScheduleData> scheduleForStops(
    Set<String> stopIds, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    if (stopIds.isEmpty) return const TransitScheduleData();
    final selectedTripIds = <String>{};
    for (final stopId in stopIds) {
      selectedTripIds.addAll(
        (_tripsAtStop[stopId] ?? const []).map((entry) => entry.trip.id),
      );
    }
    final trips = _trips
        .where((trip) => selectedTripIds.contains(trip.id))
        .toList();
    final stopTimes = <StopTime>[];
    final includedStopIds = <String>{};
    for (final trip in trips) {
      final pattern = trip.patternId == null
          ? null
          : _patternsById[trip.patternId];
      if (pattern == null || trip.startSecs == null) continue;
      for (final item in pattern.stops) {
        includedStopIds.add(item.stopId);
        stopTimes.add(
          StopTime(
            tripId: trip.id,
            stopId: item.stopId,
            arrivalSeconds: trip.startSecs! + item.arrivalOffsetSecs,
            departureSeconds: trip.startSecs! + item.departureOffsetSecs,
            sequence: item.ordinal,
          ),
        );
      }
    }
    final routeIds = trips.map((trip) => trip.routeId).toSet();
    final variantIds = trips.map((trip) => trip.variantId).toSet();
    final serviceIds = trips.map((trip) => trip.serviceId).toSet();
    return TransitScheduleData(
      stops: [
        for (final id in includedStopIds)
          if (_stopsById[id] case final Stop stop) stop,
      ],
      routes: [
        for (final id in routeIds)
          if (_routesById[id] case final Route route) route,
      ],
      variants: [
        for (final id in variantIds)
          if (_variantsById[id] case final RouteVariant variant) variant,
      ],
      trips: trips,
      stopTimes: stopTimes,
      calendars: [
        for (final id in serviceIds)
          if (_calendarsById[id] case final ServiceCalendar calendar) calendar,
      ],
    );
  }

  @override
  Future<FeedStatus> feedStatus() async => _status;
}

class _TripAtStop {
  const _TripAtStop(this.trip, this.stop);
  final Trip trip;
  final TripPatternStop stop;
}

double _distance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  final latDelta = _radians(lat2 - lat1);
  final lonDelta = _radians(lon2 - lon1);
  final value =
      math.sin(latDelta / 2) * math.sin(latDelta / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(lonDelta / 2) *
          math.sin(lonDelta / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(value));
}

double _radians(double value) => value * math.pi / 180;
