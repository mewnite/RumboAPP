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

/// Punto de integración futuro para `/buses/busstops/{id}/upcomingbuses`.
/// El contrato oficial todavía no está confirmado: ninguna implementación
/// debe inferir campos de ETA del payload hasta que se documente.
abstract interface class OfficialUpcomingBusArrivalsSource {
  Future<List<StopArrival>> arrivalsForStop(
    String stopId,
    DateTime now, {
    int limit = 10,
  });
}

class RealtimeMatcher {
  const RealtimeMatcher(this.repository);
  final TransitRepository repository;

  static MatchedBusPosition? matchPositionToVariant(
    BusPosition position,
    RouteVariant variant, {
    Route? route,
  }) {
    if (variant.externalVariantId != position.variantId) return null;
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
