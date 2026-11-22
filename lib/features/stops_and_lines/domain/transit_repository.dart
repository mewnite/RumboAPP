import 'transit_models.dart';

abstract interface class TransitRepository {
  Future<List<Stop>> nearbyStops(
    double latitude,
    double longitude,
    double radiusMeters,
  );
  Future<List<Stop>> searchStops(String query, {int limit = 25});
  Future<Stop?> stopById(String id);
  Future<List<Route>> routesForStop(String stopId);
  Future<Map<String, List<Route>>> routesForStops(Set<String> stopIds);
  Future<Route?> routeById(String id);
  Future<List<RouteVariant>> variantsForRoute(String routeId);
  Future<RouteVariant?> variantByExternalId(int externalVariantId);
  Future<Shape?> shapeForVariant(String variantId);
  Future<List<Stop>> stopsForVariant(String variantId);
  Future<List<DateTime>> upcomingDeparturesForVariant(
    String variantId,
    DateTime now, {
    int limit = 10,
  });
  Future<List<UpcomingDeparture>> upcomingDepartures(
    String stopId,
    DateTime now, {
    int limit = 10,
  });
  Future<TransitScheduleData> scheduleForStops(
    Set<String> stopIds, {
    DateTime? windowStart,
    DateTime? windowEnd,
  });
  Future<FeedStatus> feedStatus();
}

abstract interface class RealtimeBusSource {
  Future<RealtimeSnapshot> fetch({Set<String>? lines});
}

abstract interface class ArrivalsSource {
  Future<List<StopArrival>> arrivalsForStop(
    String stopId,
    DateTime now, {
    int limit = 10,
  });
}

class OfficialBusArrival {
  const OfficialBusArrival({
    required this.busId,
    required this.lineVariantId,
    required this.line,
    required this.etaSeconds,
    this.destination = '',
    this.latitude,
    this.longitude,
  });

  final int busId;
  final int lineVariantId;
  final String line;

  /// The captured response is consistent with seconds; the public schema is
  /// not explicit about the unit.
  final int etaSeconds;
  final String destination;
  final double? latitude;
  final double? longitude;
}

abstract interface class OfficialUpcomingBusArrivalsSource {
  Future<List<OfficialBusArrival>> upcomingForStop({
    required String stopId,
    required Set<String> lines,
    int amountPerLine = 1,
  });

  void close();
}

class RealtimeMatcher {
  const RealtimeMatcher(this.repository);
  final TransitRepository repository;

  static MatchedBusPosition? matchPositionToVariant(
    BusPosition position,
    RouteVariant variant, {
    Route? route,
  }) {
    final externalVariantId =
        variant.externalVariantId ?? int.tryParse(variant.shapeId ?? '');
    if (externalVariantId != position.variantId) return null;
    final routeLine = route?.shortName;
    if (routeLine != null &&
        routeLine.isNotEmpty &&
        _normalizeLine(routeLine) != _normalizeLine(position.lineLabel)) {
      return null;
    }
    return MatchedBusPosition(position, variant: variant, route: route);
  }

  Future<List<MatchedBusPosition>> match(RealtimeSnapshot snapshot) async {
    final matches = <MatchedBusPosition>[];
    for (final position in snapshot.positions) {
      final variant = await repository.variantByExternalId(position.variantId);
      final route = variant == null
          ? null
          : await repository.routeById(variant.routeId);
      matches.add(
        variant == null
            ? MatchedBusPosition(position)
            : matchPositionToVariant(position, variant, route: route) ??
                  MatchedBusPosition(position),
      );
    }
    return matches;
  }
}

String _normalizeLine(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
