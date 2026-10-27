import '../../stops_and_lines/data/gtfs_parser.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';
import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';

/// Local stop/line search over the compact GTFS feed used by Flutter web.
class InMemoryTransitSearchSource implements LocalTransitSearchRepository {
  const InMemoryTransitSearchSource(this.feed, this.repository);

  final GtfsParseResult? feed;
  final TransitRepository repository;

  @override
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  }) async {
    if (limit <= 0 || query.normalized.isEmpty) return const [];
    final feed = this.feed;
    if (feed == null) return const [];
    final results = <SearchResult>[];
    final normalized = query.normalized;

    if (query.intent == QueryIntentKind.stopCode && query.stopCode != null) {
      final exact = feed.stops.where((stop) => stop.code == query.stopCode);
      results.addAll(exact.map((stop) => _stopResult(stop, exact: true)));
      if (results.isNotEmpty) return results.take(limit).toList();
    }

    if (query.intent == QueryIntentKind.routeCode && query.routeCode != null) {
      final routes = feed.routes.where(
        (route) =>
            route.shortName.toLowerCase() == query.routeCode!.toLowerCase(),
      );
      for (final route in routes.take(5)) {
        final variant = feed.variants
            .where((item) => item.routeId == route.id)
            .firstOrNull;
        final routeStops = variant == null
            ? const <Stop>[]
            : await repository.stopsForVariant(variant.id);
        final anchor = routeStops.firstOrNull;
        results.add(
          SearchResult(
            id: 'stm:route:${route.id}',
            kind: SearchEntityKind.route,
            title: 'Línea ${route.shortName}',
            subtitle: route.longName.isNotEmpty
                ? route.longName
                : 'Línea de ómnibus del STM',
            latitude: anchor?.latitude ?? -34.9058,
            longitude: anchor?.longitude ?? -56.1991,
            precision: GeoPrecision.streetSegment,
            source: SearchDataSource.stmGtfsLocal,
            lines: [route.shortName],
          ),
        );
      }
    }

    final matchingStops = feed.stops.where((stop) {
      return stop.name.toLowerCase().contains(normalized) ||
          stop.code.toLowerCase().contains(normalized);
    });
    for (final stop in matchingStops.take(limit - results.length)) {
      results.add(_stopResult(stop));
    }
    return results.take(limit).toList(growable: false);
  }

  SearchResult _stopResult(Stop stop, {bool exact = false}) => SearchResult(
    id: 'stm:stop:${stop.id}',
    kind: SearchEntityKind.stop,
    title: stop.name,
    subtitle: stop.code.isEmpty
        ? 'Parada del STM'
        : 'Parada del STM · Código ${stop.code}',
    latitude: stop.latitude,
    longitude: stop.longitude,
    precision: GeoPrecision.stopCoordinates,
    source: SearchDataSource.stmGtfsLocal,
    score: exact ? 100 : 0,
    stop: stop,
    stopCode: stop.code.isEmpty ? null : stop.code,
  );
}
