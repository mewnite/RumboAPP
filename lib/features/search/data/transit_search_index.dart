import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../stops_and_lines/data/gtfs_parser.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';

class TransitSearchIndex {
  TransitSearchIndex._(this._entries);

  final List<_IndexedEntry> _entries;

  static Future<TransitSearchIndex> fromDatabase(Database db) async {
    final stops = await db.query(
      'stops',
      columns: ['id', 'name', 'code', 'lat', 'lon'],
      orderBy: 'rowid ASC',
    );
    final routes = await db.query(
      'routes',
      columns: ['id', 'short_name', 'long_name'],
      orderBy: 'rowid ASC',
    );
    final variants = await db.query(
      'variants',
      columns: ['route_id', 'destination'],
      orderBy: 'rowid ASC',
    );
    final raw = <Map<String, String>>[
      ...stops.map(
        (row) => {
          'kind': 'stop',
          'id': row['id'] as String,
          'title': row['name'] as String,
          'code': row['code'] as String? ?? '',
          'lat': '${row['lat']}',
          'lon': '${row['lon']}',
        },
      ),
      ...routes.map((row) {
        final routeId = row['id'] as String;
        final destinations = variants
            .where((variant) => variant['route_id'] == routeId)
            .map((variant) => variant['destination'] as String? ?? '')
            .where((destination) => destination.isNotEmpty)
            .toSet()
            .join(' · ');
        return {
          'kind': 'route',
          'id': routeId,
          'title': row['short_name'] as String? ?? '',
          'subtitle': row['long_name'] as String? ?? '',
          'destination': destinations,
        };
      }),
    ];
    return _fromRaw(raw);
  }

  static Future<TransitSearchIndex> fromFeed(GtfsParseResult? feed) async {
    if (feed == null) return TransitSearchIndex._(const []);
    final variantsByRoute = <String, Set<String>>{};
    for (final variant in feed.variants) {
      if (variant.destination.isNotEmpty) {
        variantsByRoute
            .putIfAbsent(variant.routeId, () => <String>{})
            .add(variant.destination);
      }
    }
    final raw = <Map<String, String>>[
      ...feed.stops.map(
        (stop) => {
          'kind': 'stop',
          'id': stop.id,
          'title': stop.name,
          'code': stop.code,
          'lat': '${stop.latitude}',
          'lon': '${stop.longitude}',
        },
      ),
      ...feed.routes.map(
        (route) => {
          'kind': 'route',
          'id': route.id,
          'title': route.shortName,
          'subtitle': route.longName,
          'destination': variantsByRoute[route.id]?.join(' · ') ?? '',
        },
      ),
    ];
    return _fromRaw(raw);
  }

  static Future<TransitSearchIndex> _fromRaw(
    List<Map<String, String>> raw,
  ) async {
    final normalized = await compute(_normalizeEntries, raw);
    return TransitSearchIndex._(
      normalized.map(_IndexedEntry.fromMap).toList(growable: false),
    );
  }

  List<SearchResult> search(
    ParsedQuery query, {
    int limit = 20,
    Iterable<SearchResult> additionalResults = const [],
  }) {
    if (query.normalized.length < 2 || limit <= 0) return const [];
    final tokens = query.normalized.split(' ');
    final ranked = <({int rank, int index, SearchResult result})>[];
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      final rank = entry.matchRank(query.normalized, tokens);
      if (rank != null) {
        ranked.add((rank: rank, index: index, result: entry.toSearchResult()));
      }
    }
    var additionalIndex = 0;
    for (final result in additionalResults) {
      final rank = _resultMatchRank(result, query.normalized, tokens);
      if (rank != null) {
        ranked.add((
          rank: rank,
          index: _entries.length + additionalIndex,
          result: result,
        ));
      }
      additionalIndex++;
    }
    ranked.sort(
      (a, b) => a.rank != b.rank
          ? a.rank.compareTo(b.rank)
          : a.index.compareTo(b.index),
    );
    return ranked
        .take(limit)
        .map((item) => item.result)
        .toList(growable: false);
  }

  static int? _resultMatchRank(
    SearchResult result,
    String query,
    List<String> tokens,
  ) {
    const parser = MontevideoQueryParser();
    final title = parser.normalizeText(result.title);
    final code = parser.normalizeText(result.stopCode ?? '');
    final search = parser.normalizeText(
      '${result.title} ${result.subtitle} ${result.stopCode ?? ''}',
    );
    if (code == query && code.isNotEmpty) return 0;
    if (title.startsWith(query)) return 1;
    if (tokens.any(
      (token) =>
          token.isNotEmpty &&
          search.split(' ').any((word) => word.startsWith(token)),
    )) {
      return 2;
    }
    if (search.contains(query)) return 3;
    return null;
  }
}

List<Map<String, String>> _normalizeEntries(List<Map<String, String>> raw) {
  const parser = MontevideoQueryParser();
  return raw
      .map(
        (entry) => {
          ...entry,
          'normalized_title': parser.normalizeText(entry['title'] ?? ''),
          'normalized_code': parser.normalizeText(entry['code'] ?? ''),
          'normalized_search': parser.normalizeText(
            '${entry['title'] ?? ''} ${entry['code'] ?? ''} '
            '${entry['subtitle'] ?? ''} ${entry['destination'] ?? ''}',
          ),
        },
      )
      .toList(growable: false);
}

class _IndexedEntry {
  const _IndexedEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.code,
    required this.normalizedTitle,
    required this.normalizedCode,
    required this.normalizedSubtitle,
    required this.normalizedSearch,
    required this.latitude,
    required this.longitude,
  });

  factory _IndexedEntry.fromMap(Map<String, String> map) {
    const parser = MontevideoQueryParser();
    return _IndexedEntry(
      kind: map['kind']!,
      id: map['id']!,
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      code: map['code'] ?? '',
      normalizedTitle: map['normalized_title'] ?? '',
      normalizedCode: map['normalized_code'] ?? '',
      normalizedSubtitle: parser.normalizeText(map['subtitle'] ?? ''),
      normalizedSearch: map['normalized_search'] ?? '',
      latitude: double.tryParse(map['lat'] ?? '') ?? -34.9058,
      longitude: double.tryParse(map['lon'] ?? '') ?? -56.1991,
    );
  }

  final String kind,
      id,
      title,
      subtitle,
      code,
      normalizedTitle,
      normalizedCode,
      normalizedSubtitle,
      normalizedSearch;
  final double latitude, longitude;

  int? matchRank(String query, List<String> tokens) {
    if (normalizedCode == query && normalizedCode.isNotEmpty) return 0;
    if (normalizedTitle.startsWith(query) || normalizedCode.startsWith(query)) {
      return 1;
    }
    if (tokens.any(
      (token) =>
          token.isNotEmpty &&
          normalizedSearch.split(' ').any((word) => word.startsWith(token)),
    )) {
      return 2;
    }
    if (normalizedSearch.contains(query)) {
      return 3;
    }
    return null;
  }

  SearchResult toSearchResult() {
    if (kind == 'route') {
      return SearchResult(
        id: 'stm:route:$id',
        kind: SearchEntityKind.route,
        title: 'Línea $title',
        subtitle: subtitle.isNotEmpty ? subtitle : 'Línea de ómnibus del STM',
        latitude: latitude,
        longitude: longitude,
        precision: GeoPrecision.streetSegment,
        source: SearchDataSource.stmGtfsLocal,
        lines: [title],
      );
    }
    final stop = Stop(
      id: id,
      name: title,
      latitude: latitude,
      longitude: longitude,
      code: code,
    );
    return SearchResult(
      id: 'stm:stop:$id',
      kind: SearchEntityKind.stop,
      title: title,
      subtitle: code.isEmpty
          ? 'Parada del STM'
          : 'Parada del STM · Código $code',
      latitude: latitude,
      longitude: longitude,
      precision: GeoPrecision.stopCoordinates,
      source: SearchDataSource.stmGtfsLocal,
      stop: stop,
      stopCode: code.isEmpty ? null : code,
      score: code.isNotEmpty && code == title ? 100 : 0,
    );
  }
}
