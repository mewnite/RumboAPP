import '../../stops_and_lines/data/gtfs_parser.dart';
import '../../stops_and_lines/domain/transit_repository.dart';
import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';
import 'transit_search_index.dart';

/// Local stop/line search over the compact GTFS feed used by Flutter web.
class InMemoryTransitSearchSource implements LocalTransitSearchRepository {
  InMemoryTransitSearchSource(this.feed, this.repository)
    : _index = TransitSearchIndex.fromFeed(feed);

  final GtfsParseResult? feed;
  final TransitRepository repository;
  final Future<TransitSearchIndex> _index;

  @override
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  }) async {
    if (limit <= 0 || query.normalized.isEmpty) return const [];
    return (await _index).search(query, limit: limit);
  }
}
