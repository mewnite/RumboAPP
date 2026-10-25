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
  Future<List<UpcomingDeparture>> upcomingDepartures(
    String stopId,
    DateTime now, {
    int limit = 10,
  });
  Future<TransitScheduleData> scheduleForStops(Set<String> stopIds);
  Future<FeedStatus> feedStatus();
}

abstract interface class RealtimeBusSource {
  Future<RealtimeSnapshot> fetch();
}

abstract interface class ArrivalsSource {
  Future<List<StopArrival>> arrivalsForStop(
    String stopId,
    DateTime now, {
    int limit = 10,
  });
}

class RealtimeMatcher {
  const RealtimeMatcher(this.repository);
  final TransitRepository repository;

  Future<List<MatchedBusPosition>> match(RealtimeSnapshot snapshot) async {
    final matches = <MatchedBusPosition>[];
    for (final position in snapshot.positions) {
      final variant = await repository.variantByExternalId(position.variantId);
      final route = variant == null
          ? null
          : await repository.routeById(variant.routeId);
      matches.add(MatchedBusPosition(position, variant: variant, route: route));
    }
    return matches;
  }
}
