import 'package:sqflite/sqflite.dart';

import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';
import 'transit_search_index.dart';

/// Implementación del repositorio de búsqueda de transporte local contra SQLite.
class LocalTransitSearchSource implements LocalTransitSearchRepository {
  LocalTransitSearchSource(
    this._databaseProvider, {
    this.queryParser = const MontevideoQueryParser(),
  });

  final Future<Database> Function() _databaseProvider;
  final MontevideoQueryParser queryParser;
  Future<TransitSearchIndex>? _index;

  @override
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  }) async {
    if (query.normalized.isEmpty || limit <= 0) return const [];
    _index ??= _databaseProvider().then(TransitSearchIndex.fromDatabase);
    final index = await _index!;
    return index.search(query, limit: limit);
  }
}
