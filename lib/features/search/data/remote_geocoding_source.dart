import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';

/// Fuente remota de geocodificación que interactúa con el gateway o proxy de Rumbo.
class RemoteGeocodingSource implements GeocodingRepository {
  RemoteGeocodingSource({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final String endpoint;
  final http.Client _client;
  final Map<String, List<SearchResult>> _cache = <String, List<SearchResult>>{};

  void close() => _client.close();

  @override
  Future<List<SearchResult>> searchRemote(
    ParsedQuery query, {
    double? biasLatitude,
    double? biasLongitude,
    int limit = 10,
    Future<void>? abortTrigger,
  }) async {
    final queryText = query.normalized.trim();
    if (queryText.length < 3 || queryText.length > 160) {
      return const [];
    }

    final cacheKey =
        '${queryText.toLowerCase()}_${biasLatitude?.toStringAsFixed(3)}_${biasLongitude?.toStringAsFixed(3)}';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final baseUri = Uri.tryParse(endpoint);
    final localDevelopmentHost =
        baseUri != null &&
        (baseUri.host == 'localhost' ||
            baseUri.host == '127.0.0.1' ||
            baseUri.host == '10.0.2.2' ||
            baseUri.host == '::1');

    if (baseUri == null ||
        !baseUri.hasAuthority ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' && localDevelopmentHost))) {
      throw const FormatException(
        'La URL de búsqueda de lugares no es válida.',
      );
    }

    final queryParams = <String, String>{'q': queryText};

    if (biasLatitude != null && biasLongitude != null) {
      queryParams['bias_lat'] = biasLatitude.toStringAsFixed(5);
      queryParams['bias_lon'] = biasLongitude.toStringAsFixed(5);
    }

    final uri = baseUri.replace(queryParameters: queryParams);

    final abortRequest = Completer<void>();
    void abort() {
      if (!abortRequest.isCompleted) abortRequest.complete();
    }

    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => abort()));
    }
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abortRequest.future)
          ..headers.addAll(const {
            'Accept': 'application/json',
            'User-Agent': 'RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)',
          });
    late http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              abort();
              throw TimeoutException('La búsqueda en línea demoró demasiado.');
            },
          );
    } finally {
      abort();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'El servicio de lugares respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'La respuesta del servicio de lugares no es una lista válida.',
      );
    }

    final results = <SearchResult>[];
    for (var i = 0; i < decoded.length; i++) {
      final value = decoded[i];
      if (value is! Map<String, dynamic>) continue;

      final parsed = _parseItem(value, i);
      if (parsed != null) {
        results.add(parsed);
      }
    }

    final immutable = List<SearchResult>.unmodifiable(results);
    _cache[cacheKey] = immutable;
    while (_cache.length > 20) {
      _cache.remove(_cache.keys.first);
    }
    return immutable;
  }

  SearchResult? _parseItem(Map<String, dynamic> item, int index) {
    final latitude = double.tryParse(item['lat']?.toString() ?? '');
    final longitude = double.tryParse(
      item['lon']?.toString() ?? item['lng']?.toString() ?? '',
    );

    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -35.2 ||
        latitude > -30.0 ||
        longitude < -58.5 ||
        longitude > -53.0) {
      return null;
    }

    // 1. Formato estructurado nativo de Rumbo Gateway
    if (item.containsKey('title') && item.containsKey('kind')) {
      final title = (item['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) return null;

      return SearchResult(
        id: item['id']?.toString() ?? 'remote:$index:${latitude}_$longitude',
        kind: _parseKind(item['kind']?.toString()),
        title: title,
        subtitle: (item['subtitle'] as String?)?.trim() ?? 'Montevideo',
        latitude: latitude,
        longitude: longitude,
        precision: _parsePrecision(item['precision']?.toString()),
        source: _parseSource(item['source']?.toString()),
        neighborhood: item['neighborhood']?.toString(),
      );
    }

    // 2. Formato compatible con Nominatim / OSM genérico
    final displayName =
        item['display_name'] as String? ?? item['name'] as String? ?? '';
    if (displayName.trim().isEmpty) return null;

    final parts = displayName.split(',');
    final primaryTitle = parts.first.trim();
    final secondary = parts.length > 1
        ? parts.sublist(1, parts.length > 3 ? 3 : parts.length).join(',').trim()
        : 'Montevideo';

    final osmType = item['type']?.toString().toLowerCase() ?? '';
    final kind = _inferKindFromOsmType(osmType);

    return SearchResult(
      id: 'osm:${item['osm_id'] ?? index}:${latitude}_$longitude',
      kind: kind,
      title: primaryTitle,
      subtitle: secondary,
      latitude: latitude,
      longitude: longitude,
      precision: kind == SearchEntityKind.address
          ? GeoPrecision.streetSegment
          : GeoPrecision.rooftopPoi,
      source: SearchDataSource.openStreetMap,
    );
  }

  SearchEntityKind _parseKind(String? value) {
    return SearchEntityKind.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SearchEntityKind.poi,
    );
  }

  GeoPrecision _parsePrecision(String? value) {
    return GeoPrecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GeoPrecision.streetSegment,
    );
  }

  SearchDataSource _parseSource(String? value) {
    return SearchDataSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SearchDataSource.openStreetMap,
    );
  }

  SearchEntityKind _inferKindFromOsmType(String type) {
    switch (type) {
      case 'house':
      case 'building':
      case 'residential':
        return SearchEntityKind.address;
      case 'intersection':
      case 'crossing':
        return SearchEntityKind.intersection;
      case 'suburb':
      case 'neighbourhood':
      case 'quarter':
        return SearchEntityKind.neighborhood;
      case 'bus_stop':
      case 'platform':
        return SearchEntityKind.stop;
      default:
        return SearchEntityKind.poi;
    }
  }
}
