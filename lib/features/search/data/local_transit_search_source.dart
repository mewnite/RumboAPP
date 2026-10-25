import 'package:sqflite/sqflite.dart';

import '../../../features/stops_and_lines/data/sqflite_transit_repository.dart';
import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';

/// Implementación del repositorio de búsqueda de transporte local contra SQLite.
class LocalTransitSearchSource implements LocalTransitSearchRepository {
  LocalTransitSearchSource(
    this._databaseProvider, {
    this.queryParser = const MontevideoQueryParser(),
  });

  final Future<Database> Function() _databaseProvider;
  final MontevideoQueryParser queryParser;

  @override
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  }) async {
    final rawNorm = query.normalized;
    if (rawNorm.isEmpty || limit <= 0) return const [];

    final db = await _databaseProvider();
    final results = <SearchResult>[];

    // 1. Si es búsqueda por código de parada (ej. "3004")
    if (query.intent == QueryIntentKind.stopCode && query.stopCode != null) {
      final codeRows = await db.query(
        'stops',
        where: 'code = ?',
        whereArgs: [query.stopCode],
        limit: limit,
      );
      if (codeRows.isNotEmpty) {
        final stops = codeRows.map(_mapStop).toList(growable: false);
        final linesByStop = await _fetchLinesForStops(db, stops);
        for (final stop in stops) {
          final lines = linesByStop[stop.id] ?? const [];
          results.add(_buildStopResult(stop, lines, exactCodeMatch: true));
        }
        return results;
      }
    }

    // 2. Si es búsqueda por línea de ómnibus (ej. "522", "104", "D10")
    if (query.intent == QueryIntentKind.routeCode && query.routeCode != null) {
      final routeRows = await db.query(
        'routes',
        where: 'short_name = ? COLLATE NOCASE',
        whereArgs: [query.routeCode],
        limit: 5,
      );
      for (final row in routeRows) {
        final shortName = row['short_name'] as String? ?? '';
        final longName = row['long_name'] as String? ?? '';
        final routeId = row['id'] as String;

        // Buscar algunas paradas destacadas de esta línea
        final stopRows = await db.rawQuery(
          'SELECT DISTINCT s.* FROM stops s '
          'JOIN stop_times st ON st.stop_id = s.id '
          'JOIN trips t ON t.id = st.trip_id '
          'WHERE t.route_id = ? '
          'LIMIT 5',
          [routeId],
        );
        final routeStops = stopRows.map(_mapStop).toList(growable: false);

        results.add(
          SearchResult(
            id: 'stm:route:$routeId',
            kind: SearchEntityKind.route,
            title: 'Línea $shortName',
            subtitle: longName.isNotEmpty
                ? longName
                : 'Línea de ómnibus del STM',
            latitude: routeStops.isNotEmpty
                ? routeStops.first.latitude
                : -34.9058,
            longitude: routeStops.isNotEmpty
                ? routeStops.first.longitude
                : -56.1991,
            precision: GeoPrecision.streetSegment,
            source: SearchDataSource.stmGtfsLocal,
            lines: [shortName],
          ),
        );
      }
    }

    // 3. Búsqueda por nombre de parada o intersección
    final sanitizedQuery = rawNorm
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');

    final nameRows = await db.query(
      'stops',
      where: "name LIKE ? ESCAPE '\\' OR code LIKE ? ESCAPE '\\'",
      whereArgs: ['%$sanitizedQuery%', '%$sanitizedQuery%'],
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );

    final stops = nameRows.map(_mapStop).toList(growable: false);
    if (stops.isNotEmpty) {
      final linesByStop = await _fetchLinesForStops(db, stops);
      for (final stop in stops) {
        final lines = linesByStop[stop.id] ?? const [];
        results.add(_buildStopResult(stop, lines));
      }
    }

    return results;
  }

  Future<Map<String, List<String>>> _fetchLinesForStops(
    Database db,
    List<Stop> stops,
  ) async {
    final stopIds = stops.map((s) => s.id).toSet();
    if (stopIds.isEmpty) return const {};
    try {
      final repo = SqfliteTransitRepository(() async => db);
      final routesMap = await repo.routesForStops(stopIds);
      return {
        for (final entry in routesMap.entries)
          entry.key: entry.value
              .map((route) => route.shortName)
              .where((name) => name.isNotEmpty)
              .toList(growable: false),
      };
    } catch (_) {
      return const {};
    }
  }

  SearchResult _buildStopResult(
    Stop stop,
    List<String> lines, {
    bool exactCodeMatch = false,
  }) {
    final subtitleParts = <String>['Parada del STM'];
    if (stop.code.isNotEmpty) {
      subtitleParts.add('Código ${stop.code}');
    }
    if (lines.isNotEmpty) {
      subtitleParts.add('Líneas ${lines.join(', ')}');
    }

    return SearchResult(
      id: 'stm:stop:${stop.id}',
      kind: SearchEntityKind.stop,
      title: stop.name,
      subtitle: subtitleParts.join(' · '),
      latitude: stop.latitude,
      longitude: stop.longitude,
      precision: GeoPrecision.stopCoordinates,
      source: SearchDataSource.stmGtfsLocal,
      stop: stop,
      stopCode: stop.code.isNotEmpty ? stop.code : null,
      lines: lines,
      score: exactCodeMatch ? 100.0 : 0.0,
    );
  }

  Stop _mapStop(Map<String, Object?> row) {
    return Stop(
      id: row['id'] as String,
      name: row['name'] as String,
      latitude: (row['lat'] as num).toDouble(),
      longitude: (row['lon'] as num).toDouble(),
      code: (row['code'] as String?) ?? '',
    );
  }
}
