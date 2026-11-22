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
  static const _queryParser = MontevideoQueryParser();

  void close() => _client.close();

  @override
  Future<List<SearchResult>> searchRemote(
    ParsedQuery query, {
    int limit = 10,
    Future<void>? abortTrigger,
  }) async {
    final queryText = query.normalized.trim();
    if (queryText.length < 3 || queryText.length > 160) {
      return const [];
    }

    final cacheKey = queryText.toLowerCase();
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

    // Send only the text the person typed. The GPS fix is used by the local
    // ranking engine and must never leave this device.
    final queryParams = <String, String>{'q': query.raw.trim()};
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

      final parsed = _parseItem(value, i, query: query);
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

  SearchResult? _parseItem(
    Map<String, dynamic> item,
    int index, {
    required ParsedQuery query,
  }) {
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
      var title = (item['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) return null;
      final isIntersection = query.intent == QueryIntentKind.intersection;
      final precision = _parsePrecision(item['precision']?.toString());
      final kind = _parseKind(item['kind']?.toString());
      final titleHasRequestedNumber =
          query.doorNumber != null &&
          RegExp('(?<!\\d)${query.doorNumber}(?!\\d)').hasMatch(title);
      final hasDifferentDoorNumber =
          query.intent == QueryIntentKind.addressWithNumber &&
          RegExp(r'\b\d{1,5}\b').hasMatch(title) &&
          !titleHasRequestedNumber;
      if (hasDifferentDoorNumber) return null;
      final hasUnconfirmedDoorNumber =
          query.intent == QueryIntentKind.addressWithNumber &&
          (precision != GeoPrecision.exactDoorNumber ||
              !titleHasRequestedNumber);

      if (query.intent == QueryIntentKind.addressWithNumber &&
          kind != SearchEntityKind.address) {
        return null;
      }
      if (query.intent == QueryIntentKind.addressWithNumber &&
          hasUnconfirmedDoorNumber) {
        title = query.raw.trim();
      }
      if (isIntersection) {
        if (!_containsBothIntersectionStreets(
          '$title ${item['subtitle'] ?? ''}',
          query,
        )) {
          return null;
        }
        title = query.raw.trim();
      }
      final isApproximateIntersection =
          isIntersection && precision != GeoPrecision.intersectionPoint;
      final resultPrecision = switch (query.intent) {
        QueryIntentKind.addressWithNumber when hasUnconfirmedDoorNumber =>
          GeoPrecision.unconfirmedDoorNumber,
        QueryIntentKind.intersection when isApproximateIntersection =>
          GeoPrecision.approximateIntersection,
        _ => precision,
      };

      return SearchResult(
        id: item['id']?.toString() ?? 'remote:$index:${latitude}_$longitude',
        kind: isIntersection ? SearchEntityKind.intersection : kind,
        title: title,
        subtitle: (item['subtitle'] as String?)?.trim() ?? 'Montevideo',
        latitude: latitude,
        longitude: longitude,
        precision: resultPrecision,
        source: _parseSource(item['source']?.toString()),
        neighborhood: item['neighborhood']?.toString(),
      );
    }

    // 2. Formato compatible con Nominatim / OSM genérico
    final displayName =
        item['display_name'] as String? ?? item['name'] as String? ?? '';
    if (displayName.trim().isEmpty) return null;

    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final address = item['address'];
    final street = address is Map<String, dynamic>
        ? _firstNonEmpty([
            address['road'],
            address['residential'],
            address['pedestrian'],
            address['street'],
          ])
        : null;
    final houseNumber = address is Map<String, dynamic>
        ? _firstNonEmpty([address['house_number']])
        : null;
    final isIntersection = query.intent == QueryIntentKind.intersection;
    if (isIntersection) {
      final addressText = address is Map<String, dynamic>
          ? address.values.join(' ')
          : '';
      if (!_containsBothIntersectionStreets(
        '${item['name'] ?? ''} $displayName $addressText',
        query,
      )) {
        return null;
      }
    }
    final exactAddress = street == null
        ? null
        : houseNumber == null
        ? street
        : '$street $houseNumber';
    final primaryTitle =
        exactAddress ??
        _firstNonEmpty([item['name']]) ??
        (parts.isEmpty ? '' : parts.first);
    final remainingParts = exactAddress == null
        ? parts.skip(1).toList(growable: false)
        : parts
              .where(
                (part) =>
                    part.toLowerCase() != street?.toLowerCase() &&
                    part.toLowerCase() != houseNumber?.toLowerCase(),
              )
              .toList(growable: false);
    final secondary = remainingParts.isNotEmpty
        ? remainingParts.take(3).join(', ')
        : 'Montevideo';

    final osmType = item['type']?.toString().toLowerCase() ?? '';
    var kind = isIntersection
        ? SearchEntityKind.intersection
        : _inferKindFromOsmType(osmType);
    final hasIntersectionGeometry =
        osmType == 'intersection' ||
        osmType == 'crossing' ||
        osmType == 'junction';
    final houseNumberMatch = houseNumber == null
        ? null
        : RegExp(
            r'^\s*(\d+)(?:\s*(?:bis|b|a))?\s*$',
            caseSensitive: false,
          ).firstMatch(houseNumber);
    final hasExactRequestedHouseNumber =
        query.intent == QueryIntentKind.addressWithNumber &&
        houseNumberMatch != null &&
        int.tryParse(houseNumberMatch.group(1)!) == query.doorNumber;
    if (query.intent == QueryIntentKind.addressWithNumber) {
      if (!{
        'house',
        'building',
        'residential',
        'road',
        'pedestrian',
        'unclassified',
        'primary',
        'secondary',
        'tertiary',
        'living_street',
        'service',
      }.contains(osmType)) {
        return null;
      }
      if (houseNumber != null && !hasExactRequestedHouseNumber) return null;
      kind = SearchEntityKind.address;
    }
    final approximateAddress =
        query.intent == QueryIntentKind.addressWithNumber &&
        !hasExactRequestedHouseNumber;
    return SearchResult(
      id: 'osm:${item['osm_id'] ?? index}:${latitude}_$longitude',
      kind: kind,
      title: isIntersection
          ? query.raw.trim()
          : approximateAddress
          ? query.raw.trim()
          : primaryTitle,
      subtitle: secondary,
      latitude: latitude,
      longitude: longitude,
      precision: isIntersection
          ? hasIntersectionGeometry
                ? GeoPrecision.intersectionPoint
                : GeoPrecision.approximateIntersection
          : kind == SearchEntityKind.address
          ? hasExactRequestedHouseNumber
                ? GeoPrecision.exactDoorNumber
                : GeoPrecision.unconfirmedDoorNumber
          : GeoPrecision.rooftopPoi,
      source: SearchDataSource.openStreetMap,
    );
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  bool _containsBothIntersectionStreets(String candidate, ParsedQuery query) {
    final normalizedCandidate = _queryParser.normalizeText(candidate);
    final candidateTokens = normalizedCandidate.split(' ');
    bool containsPhrase(String phrase) {
      final phraseTokens = phrase.split(' ');
      for (
        var start = 0;
        start + phraseTokens.length <= candidateTokens.length;
        start++
      ) {
        if (candidateTokens.skip(start).take(phraseTokens.length).join(' ') ==
            phrase) {
          return true;
        }
      }
      return false;
    }

    bool containsStreet(String? street) {
      if (street == null || street.trim().isEmpty) return false;
      final normalizedStreet = _queryParser.normalizeText(street);
      if (containsPhrase(normalizedStreet)) return true;
      final streetWithoutType = normalizedStreet.replaceFirst(
        RegExp(r'^(?:avenida|calle|camino|bulevar|rambla|pasaje|plaza)\s+'),
        '',
      );
      return streetWithoutType != normalizedStreet &&
          containsPhrase(streetWithoutType);
    }

    return containsStreet(query.street1) && containsStreet(query.street2);
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
      case 'road':
      case 'pedestrian':
      case 'unclassified':
      case 'primary':
      case 'secondary':
      case 'tertiary':
      case 'living_street':
      case 'service':
        return SearchEntityKind.address;
      case 'intersection':
      case 'crossing':
      case 'junction':
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
