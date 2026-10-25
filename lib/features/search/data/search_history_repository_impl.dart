import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../domain/place_search_service.dart';
import '../domain/search_models.dart';

/// Implementación local del historial de destinos usando SharedPreferences.
///
/// La información se mantiene estrictamente en el dispositivo y no se sincroniza
/// ni se envía a servidores externos.
class SearchHistoryRepositoryImpl implements SearchHistoryRepository {
  SearchHistoryRepositoryImpl({Future<SharedPreferences>? prefs})
    : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;
  static const String _storageKey = 'rumbo_recent_searches_v1';

  @override
  Future<List<SearchResult>> getRecent({int limit = 10}) async {
    final prefs = await _prefsFuture;
    final jsonList = prefs.getStringList(_storageKey) ?? [];
    final results = <SearchResult>[];

    for (final raw in jsonList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        results.add(_fromMap(map));
      } catch (_) {
        // Ignora entradas corruptas
      }
    }

    if (results.length > limit) {
      return results.take(limit).toList(growable: false);
    }
    return results;
  }

  @override
  Future<void> add(SearchResult result) async {
    final prefs = await _prefsFuture;
    final current = await getRecent(limit: 20);

    // Evita duplicados: remueve si ya existe uno con el mismo id o título
    final updated = current.where((item) => item.id != result.id).toList();
    updated.insert(0, result.copyWith(kind: SearchEntityKind.recentSearch));

    // Limita a máximo 10 destinos recientes
    final clamped = updated.take(10).toList(growable: false);
    final encoded = clamped.map((item) => jsonEncode(_toMap(item))).toList();
    await prefs.setStringList(_storageKey, encoded);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefsFuture;
    await prefs.remove(_storageKey);
  }

  Map<String, dynamic> _toMap(SearchResult item) {
    return {
      'id': item.id,
      'kind': item.kind.name,
      'title': item.title,
      'subtitle': item.subtitle,
      'lat': item.latitude,
      'lon': item.longitude,
      'precision': item.precision.name,
      'source': item.source.name,
      'stopCode': item.stopCode,
      if (item.stop != null)
        'stop': {
          'id': item.stop!.id,
          'name': item.stop!.name,
          'lat': item.stop!.latitude,
          'lon': item.stop!.longitude,
          'code': item.stop!.code,
        },
    };
  }

  SearchResult _fromMap(Map<String, dynamic> map) {
    Stop? stop;
    if (map['stop'] is Map<String, dynamic>) {
      final stopMap = map['stop'] as Map<String, dynamic>;
      stop = Stop(
        id: stopMap['id']?.toString() ?? '',
        name: stopMap['name']?.toString() ?? '',
        latitude: (stopMap['lat'] as num).toDouble(),
        longitude: (stopMap['lon'] as num).toDouble(),
        code: stopMap['code']?.toString() ?? '',
      );
    }

    return SearchResult(
      id: map['id']?.toString() ?? '',
      kind: SearchEntityKind.values.firstWhere(
        (e) => e.name == map['kind'],
        orElse: () => SearchEntityKind.recentSearch,
      ),
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      latitude: (map['lat'] as num).toDouble(),
      longitude: (map['lon'] as num).toDouble(),
      precision: GeoPrecision.values.firstWhere(
        (e) => e.name == map['precision'],
        orElse: () => GeoPrecision.rooftopPoi,
      ),
      source: SearchDataSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => SearchDataSource.userStorage,
      ),
      stop: stop,
      stopCode: map['stopCode']?.toString(),
    );
  }
}
