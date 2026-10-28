import 'dart:math' as math;

import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

class FakeTransitRepository implements TransitRepository {
  FakeTransitRepository({
    required this.stops,
    required this.routes,
    required this.variants,
    required this.trips,
    required this.times,
    required this.calendars,
    this.status = const FeedStatus(),
  });
  final List<Stop> stops;
  final List<Route> routes;
  final List<RouteVariant> variants;
  final List<Trip> trips;
  final List<StopTime> times;
  final List<ServiceCalendar> calendars;
  final FeedStatus status;
  final Map<String, Shape> shapes = {};

  @override
  Future<List<Stop>> nearbyStops(
    double lat,
    double lon,
    double radiusMeters,
  ) async {
    if (radiusMeters < 0) return const [];
    final latitudeDelta = radiusMeters / 111320;
    final longitudeDelta =
        radiusMeters /
        (111320 * math.cos(lat * math.pi / 180).abs().clamp(.01, 1));
    final list =
        stops
            .map(
              (s) => (stop: s, d: _distance(lat, lon, s.latitude, s.longitude)),
            )
            .where(
              (v) =>
                  (v.stop.latitude - lat).abs() <= latitudeDelta &&
                  (v.stop.longitude - lon).abs() <= longitudeDelta,
            )
            .where((v) => v.d <= radiusMeters)
            .toList()
          ..sort((a, b) => a.d.compareTo(b.d));
    return list.map((v) => v.stop).toList();
  }

  @override
  Future<List<Stop>> searchStops(String query, {int limit = 25}) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || limit <= 0) return const [];
    return stops
        .where((stop) => stop.name.toLowerCase().contains(normalizedQuery))
        .take(limit.clamp(1, 100))
        .toList(growable: false);
  }

  @override
  Future<Stop?> stopById(String id) async {
    for (final s in stops) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<Route>> routesForStop(String stopId) async {
    final tripIds = times
        .where((t) => t.stopId == stopId)
        .map((t) => t.tripId)
        .toSet();
    final ids = trips
        .where((t) => tripIds.contains(t.id))
        .map((t) => t.routeId)
        .toSet();
    return routes.where((r) => ids.contains(r.id)).toList();
  }

  @override
  Future<Map<String, List<Route>>> routesForStops(Set<String> stopIds) async {
    final result = <String, List<Route>>{};
    for (final stopId in stopIds) {
      result[stopId] = await routesForStop(stopId);
    }
    return result;
  }

  @override
  Future<Route?> routeById(String id) async {
    for (final r in routes) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<List<RouteVariant>> variantsForRoute(String routeId) async =>
      variants.where((v) => v.routeId == routeId).toList();

  @override
  Future<RouteVariant?> variantByExternalId(int externalVariantId) async =>
      variants
          .where((v) => v.externalVariantId == externalVariantId)
          .firstOrNull;
  @override
  Future<Shape?> shapeForVariant(String variantId) async {
    final id = variants.where((v) => v.id == variantId).firstOrNull?.shapeId;
    return id == null ? null : shapes[id];
  }

  @override
  Future<List<Stop>> stopsForVariant(String variantId) async {
    final variantTrips = trips.where((t) => t.variantId == variantId).toList();
    if (variantTrips.isEmpty) return const [];
    final tripIds = variantTrips.map((t) => t.id).toSet();
    final matchingTimes = times
        .where((t) => tripIds.contains(t.tripId))
        .toList();
    if (matchingTimes.isEmpty) return const [];
    final timesByTrip = <String, List<StopTime>>{};
    for (final t in matchingTimes) {
      timesByTrip.putIfAbsent(t.tripId, () => []).add(t);
    }
    final bestTripTimes = timesByTrip.values.reduce(
      (a, b) => a.length >= b.length ? a : b,
    )..sort((a, b) => a.sequence.compareTo(b.sequence));

    final stopMap = {for (final s in stops) s.id: s};
    return bestTripTimes
        .map((t) => stopMap[t.stopId])
        .whereType<Stop>()
        .toList(growable: false);
  }

  @override
  Future<List<DateTime>> upcomingDeparturesForVariant(
    String variantId,
    DateTime now, {
    int limit = 10,
  }) async {
    final variantTrips = trips.where((t) => t.variantId == variantId).toList();
    if (variantTrips.isEmpty) return const [];
    final serviceDay = DateTime(now.year, now.month, now.day);
    final departures = <DateTime>{};
    final calendarById = {for (final c in calendars) c.serviceId: c};

    for (final trip in variantTrips) {
      final calendar = calendarById[trip.serviceId];
      if (calendar == null) continue;
      int? startSecs = trip.startSecs;
      if (startSecs == null) {
        final tripTimes = times.where((t) => t.tripId == trip.id).toList();
        if (tripTimes.isNotEmpty) {
          tripTimes.sort((a, b) => a.sequence.compareTo(b.sequence));
          startSecs = tripTimes.first.departureSeconds;
        }
      }
      if (startSecs == null) continue;
      for (var offset = -1; offset <= 0; offset++) {
        final day = serviceDay.add(Duration(days: offset));
        if (!calendar.activeOn(day)) continue;
        final dep = day.add(Duration(seconds: startSecs));
        if (!dep.isBefore(now)) {
          departures.add(dep);
        }
      }
    }
    final sorted = departures.toList()..sort();
    return sorted.take(limit.clamp(0, sorted.length)).toList(growable: false);
  }

  @override
  Future<FeedStatus> feedStatus() async => status;

  @override
  Future<TransitScheduleData> scheduleForStops(
    Set<String> stopIds, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    final tripIds = times
        .where((time) => stopIds.contains(time.stopId))
        .map((time) => time.tripId)
        .toSet();
    final selectedTrips = trips.where((trip) => tripIds.contains(trip.id));
    final selectedTripIds = selectedTrips.map((trip) => trip.id).toSet();
    final selectedServiceIds = selectedTrips
        .map((trip) => trip.serviceId)
        .toSet();
    final selectedRouteIds = selectedTrips.map((trip) => trip.routeId).toSet();
    final selectedVariantIds = selectedTrips
        .map((trip) => trip.variantId)
        .toSet();
    final includedStopIds = times
        .where((time) => selectedTripIds.contains(time.tripId))
        .map((time) => time.stopId)
        .toSet();
    return TransitScheduleData(
      stops: stops.where((stop) => includedStopIds.contains(stop.id)).toList(),
      routes: routes
          .where((route) => selectedRouteIds.contains(route.id))
          .toList(),
      variants: variants
          .where((variant) => selectedVariantIds.contains(variant.id))
          .toList(),
      trips: selectedTrips.toList(),
      stopTimes: times
          .where((time) => selectedTripIds.contains(time.tripId))
          .toList(),
      calendars: calendars
          .where((calendar) => selectedServiceIds.contains(calendar.serviceId))
          .toList(),
    );
  }

  @override
  Future<List<UpcomingDeparture>> upcomingDepartures(
    String stopId,
    DateTime now, {
    int limit = 10,
  }) async {
    final out = <UpcomingDeparture>[];
    final day = DateTime(now.year, now.month, now.day);
    for (final time in times.where((t) => t.stopId == stopId)) {
      final trip = trips.where((t) => t.id == time.tripId).firstOrNull;
      if (trip == null) continue;
      final calendar = calendars
          .where((c) => c.serviceId == trip.serviceId)
          .firstOrNull;
      if (calendar == null) continue;
      for (var offset = -1; offset <= 0; offset++) {
        final serviceDay = day.add(Duration(days: offset));
        if (!calendar.activeOn(serviceDay)) continue;
        final departure = serviceDay.add(
          Duration(seconds: time.departureSeconds),
        );
        if (!departure.isBefore(now)) {
          out.add(
            UpcomingDeparture(trip: trip, stopTime: time, departure: departure),
          );
        }
      }
    }
    out.sort((a, b) => a.departure.compareTo(b.departure));
    return out.take(limit.clamp(0, out.length)).toList();
  }
}

double _distance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000;
  final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
  final a =
      (1 - math.cos(dLat)) / 2 +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * (1 - math.cos(dLon)) / 2;
  return 2 * r * math.asin(math.sqrt(a));
}

double _rad(double d) => d * 3.141592653589793 / 180;
