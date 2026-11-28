import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/search_models.dart';

enum _HouseNumberMatch { missing, exact, approximate, different }

/// Fuente remota de geocodificación que interactúa con el gateway o proxy de Rumbo.
class RemoteGeocodingSource implements GeocodingRepository {
  RemoteGeocodingSource({
    required this.endpoint,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final String endpoint;
  final Duration requestTimeout;
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
    final stopwatch = Stopwatch()..start();
    var status = 'network_error';
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            requestTimeout,
            onTimeout: () {
              abort();
              throw TimeoutException('La búsqueda en línea demoró demasiado.');
            },
          );
      status = response.statusCode.toString();
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
    } on TimeoutException {
      status = 'timeout';
      rethrow;
    } on http.RequestAbortedException {
      status = 'aborted';
      rethrow;
    } finally {
      abort();
      stopwatch.stop();
      debugPrint(
        '[performance] geocode_ms=${stopwatch.elapsedMilliseconds} '
        'status=$status',
      );
    }
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

    // 1. Formato estructurado de Rumbo Gateway / Photon.
    if (item.containsKey('title') && item.containsKey('kind')) {
      var title = (item['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) return null;
      final category = item['category']?.toString();
      final kind = _parseStructuredKind(item['kind']?.toString(), category);
      final precision = _parsePrecision(item['precision']?.toString());
      final street = _firstNonEmpty([item['street']]);
      final houseNumber = _firstNonEmpty([item['houseNumber']]);
      final aliases = _readAliases(item['aliases']);
      var resultPrecision =
          kind == SearchEntityKind.neighborhood ||
              kind == SearchEntityKind.geographicArea
          ? GeoPrecision.approximateArea
          : precision;
      if (_isUnrequestedAmenity(category, query)) {
        return null;
      }

      if (query.intent == QueryIntentKind.addressWithNumber) {
        if (kind != SearchEntityKind.address ||
            !_queryParser.streetMatches(street ?? title, query.street1 ?? '')) {
          return null;
        }
        final numberMatch = _matchHouseNumber(
          houseNumber ?? _houseNumberFromTitle(title),
          query.doorNumber!,
        );
        if (numberMatch == _HouseNumberMatch.different) return null;
        final exact =
            numberMatch == _HouseNumberMatch.exact &&
            precision == GeoPrecision.exactDoorNumber;
        resultPrecision = exact
            ? GeoPrecision.exactDoorNumber
            : GeoPrecision.unconfirmedDoorNumber;
        if (!exact) title = query.raw.trim();
      } else if (query.intent == QueryIntentKind.intersection) {
        final providerAddress = item['address'];
        final addressValues = providerAddress is Map<String, dynamic>
            ? providerAddress.values
            : null;
        final providerIntersectionText = [
          item['name'],
          street,
          ...?addressValues,
          ...aliases,
        ].whereType<String>().join(' ');
        if (kind != SearchEntityKind.intersection ||
            !_containsBothIntersectionStreets(
              providerIntersectionText,
              query,
            )) {
          return null;
        }
        title = title.isEmpty ? query.raw.trim() : title;
        if (precision != GeoPrecision.intersectionPoint) {
          resultPrecision = GeoPrecision.approximateIntersection;
        }
      }

      return SearchResult(
        id: item['id']?.toString() ?? 'remote:$index:${latitude}_$longitude',
        kind: kind,
        title: title,
        subtitle: (item['subtitle'] as String?)?.trim() ?? '',
        latitude: latitude,
        longitude: longitude,
        precision: resultPrecision,
        source: _parseSource(item['source']?.toString()),
        neighborhood: item['neighborhood']?.toString(),
        category: item['category']?.toString(),
        externalId: item['externalId']?.toString(),
        street: street,
        houseNumber: houseNumber,
        aliases: aliases,
      );
    }

    // 2. Formato compatible con Nominatim / OSM genérico.
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
    final osmType = item['type']?.toString().toLowerCase() ?? '';
    final osmCategory = item['category']?.toString().toLowerCase() ?? '';
    if (_isUnrequestedAmenity('$osmCategory:$osmType', query)) return null;
    final kind = _inferKindFromOsmType(osmType, osmCategory);
    final hasIntersectionGeometry =
        osmType == 'intersection' ||
        osmType == 'crossing' ||
        osmType == 'junction' ||
        item['addresstype']?.toString().toLowerCase() == 'intersection';
    final aliases = _readAliases([
      item['alt_name'],
      item['official_name'],
      item['short_name'],
      item['name:es'],
      item['name:en'],
      item['brand'],
    ]);
    final name = _firstNonEmpty([
      item['name'],
      item['official_name'],
      parts.isEmpty ? null : parts.first,
    ]);
    var resultKind = kind;
    var resultPrecision = GeoPrecision.rooftopPoi;
    String title = name ?? '';
    final addressMap = address is Map<String, dynamic> ? address : null;
    final subtitle = _buildSubtitle(
      address: addressMap,
      street: street,
      houseNumber: houseNumber,
      isPoi: kind == SearchEntityKind.poi,
    );
    final normalizedAddressParts = parts
        .where(
          (part) =>
              _queryParser.normalizeText(part) !=
                  _queryParser.normalizeText(street ?? '') &&
              _queryParser.normalizeText(part) !=
                  _queryParser.normalizeText(houseNumber ?? ''),
        )
        .where((part) => _queryParser.normalizeText(part) != 'uruguay')
        .take(2)
        .toList(growable: false);
    final resolvedSubtitle = subtitle.isNotEmpty
        ? subtitle
        : normalizedAddressParts.join(' · ');

    if (query.intent == QueryIntentKind.addressWithNumber) {
      if (kind != SearchEntityKind.address ||
          street == null ||
          !_queryParser.streetMatches(street, query.street1 ?? '')) {
        return null;
      }
      final numberMatch = _matchHouseNumber(houseNumber, query.doorNumber!);
      if (numberMatch == _HouseNumberMatch.different) return null;
      final exact = numberMatch == _HouseNumberMatch.exact;
      resultKind = SearchEntityKind.address;
      resultPrecision = exact
          ? GeoPrecision.exactDoorNumber
          : GeoPrecision.unconfirmedDoorNumber;
      title = exact ? '$street ${query.doorNumber}' : query.raw.trim();
    } else if (query.intent == QueryIntentKind.intersection) {
      final addressText = addressMap?.values.join(' ') ?? '';
      final candidateText = [
        item['name'],
        displayName,
        addressText,
        ...aliases,
      ].whereType<String>().join(' ');
      if (!hasIntersectionGeometry ||
          !_containsBothIntersectionStreets(candidateText, query)) {
        return null;
      }
      resultKind = SearchEntityKind.intersection;
      resultPrecision = GeoPrecision.intersectionPoint;
      title = name ?? query.raw.trim();
    } else if (kind == SearchEntityKind.address) {
      if (street != null) title = street;
      resultPrecision = GeoPrecision.streetSegment;
    } else if (query.intent == QueryIntentKind.geographicArea) {
      final osmAreaType = {
        'relation',
        'way',
      }.contains(item['osm_type']?.toString().toLowerCase());
      final categoryArea =
          osmCategory == 'boundary' ||
          osmCategory == 'place' ||
          osmCategory == 'natural' ||
          osmCategory == 'waterway' ||
          osmCategory == 'leisure';
      if (!osmAreaType &&
          !categoryArea &&
          !title.toLowerCase().contains('rambla')) {
        return null;
      }
      resultKind = SearchEntityKind.geographicArea;
      resultPrecision = GeoPrecision.approximateArea;
    } else {
      if (title.isEmpty) return null;
      resultPrecision = GeoPrecision.rooftopPoi;
    }

    final externalId = _nominatimExternalId(item);
    final category = [
      osmCategory,
      osmType,
    ].where((part) => part.isNotEmpty).join(':');
    return SearchResult(
      id: externalId ?? 'osm:$index:${latitude}_$longitude',
      kind: resultKind,
      title: title,
      subtitle: resolvedSubtitle,
      latitude: latitude,
      longitude: longitude,
      precision: resultPrecision,
      source: SearchDataSource.openStreetMap,
      externalId: externalId,
      category: category.isEmpty ? null : category,
      neighborhood: _firstNonEmpty([
        addressMap?['neighbourhood'],
        addressMap?['suburb'],
        addressMap?['quarter'],
      ]),
      street: street,
      houseNumber: houseNumber,
      aliases: aliases,
    );
  }

  String _buildSubtitle({
    required Map<String, dynamic>? address,
    required String? street,
    required String? houseNumber,
    required bool isPoi,
  }) {
    final parts = <String>[];
    if (isPoi && street != null) {
      final streetAddress = [street, ?houseNumber].join(' ');
      parts.add(streetAddress);
    }
    if (address != null) {
      for (final key in [
        'neighbourhood',
        'suburb',
        'quarter',
        'city_district',
        'city',
        'town',
        'village',
        'state',
        'country',
      ]) {
        final value = address[key];
        if (value is String &&
            value.trim().isNotEmpty &&
            !parts.any(
              (part) =>
                  _queryParser.normalizeText(part) ==
                  _queryParser.normalizeText(value),
            )) {
          parts.add(value.trim());
        }
      }
    }
    return parts.join(' · ');
  }

  List<String> _readAliases(Object? value) {
    final values = <Object?>[];
    if (value is List) {
      values.addAll(value);
    } else if (value is String) {
      values.addAll(value.split(RegExp(r'[;,|]')));
    }
    return values
        .whereType<String>()
        .map((alias) => alias.trim())
        .where((alias) => alias.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  _HouseNumberMatch _matchHouseNumber(String? value, int requested) {
    if (value == null || value.trim().isEmpty) {
      return _HouseNumberMatch.missing;
    }
    final normalized = value.trim().toLowerCase();
    final exact = RegExp(
      r'^0*(\d+)(?:\s*(?:bis|b|a))?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (exact != null) {
      return int.tryParse(exact.group(1)!) == requested
          ? _HouseNumberMatch.exact
          : _HouseNumberMatch.different;
    }

    final range = RegExp(r'^\s*(\d+)\s*[-–]\s*(\d+)\s*$')
        .firstMatch(normalized);
    if (range != null) {
      final start = int.tryParse(range.group(1)!);
      final end = int.tryParse(range.group(2)!);
      if (start != null &&
          end != null &&
          requested >= math.min(start, end) &&
          requested <= math.max(start, end)) {
        return _HouseNumberMatch.approximate;
      }
      return _HouseNumberMatch.different;
    }

    final numbers = RegExp(r'\d+')
        .allMatches(normalized)
        .map((match) => int.tryParse(match.group(0)!))
        .whereType<int>()
        .toList(growable: false);
    if (numbers.contains(requested)) return _HouseNumberMatch.approximate;
    if (numbers.isNotEmpty) return _HouseNumberMatch.different;
    return _HouseNumberMatch.missing;
  }

  String? _houseNumberFromTitle(String title) {
    final matches = RegExp(r'\b(\d{1,5})\b').allMatches(title);
    return matches.isEmpty ? null : matches.last.group(1);
  }

  String? _nominatimExternalId(Map<String, dynamic> item) {
    final osmId = item['osm_id']?.toString();
    final osmType = item['osm_type']?.toString().toLowerCase();
    if (osmId == null || osmType == null || osmId.isEmpty || osmType.isEmpty) {
      return null;
    }
    return 'osm:$osmType:$osmId';
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  bool _containsBothIntersectionStreets(String candidate, ParsedQuery query) {
    return _queryParser.streetMatches(candidate, query.street1 ?? '') &&
        _queryParser.streetMatches(candidate, query.street2 ?? '');
  }

  SearchEntityKind _parseKind(String? value) {
    return SearchEntityKind.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SearchEntityKind.poi,
    );
  }

  SearchEntityKind _parseStructuredKind(String? kind, String? category) {
    final normalizedCategory = category?.toLowerCase() ?? '';
    if (kind == 'geographicArea') {
      return SearchEntityKind.geographicArea;
    }
    if (kind == 'street') {
      return SearchEntityKind.street;
    }
    if (normalizedCategory == 'boundary:neighborhood' ||
        normalizedCategory == 'boundary:neighbourhood' ||
        normalizedCategory == 'place:suburb' ||
        normalizedCategory == 'place:neighborhood' ||
        normalizedCategory == 'place:neighbourhood' ||
        normalizedCategory == 'place:quarter') {
      return SearchEntityKind.neighborhood;
    }
    return _parseKind(kind);
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

  SearchEntityKind _inferKindFromOsmType(String type, String category) {
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
      case 'neighborhood':
      case 'quarter':
        return SearchEntityKind.neighborhood;
      case 'bus_stop':
      case 'platform':
        return SearchEntityKind.stop;
      default:
        if (category == 'highway') return SearchEntityKind.address;
        return SearchEntityKind.poi;
    }
  }

  bool _isUnrequestedAmenity(String? category, ParsedQuery query) {
    if (category == null) return false;
    final value = category.toLowerCase().split(':').last;
    final normalizedQuery = _queryParser.normalizeText(query.raw);
    final queryTokens = normalizedQuery.split(' ').toSet();
    return switch (value) {
      'atm' => !queryTokens.contains('atm') && !queryTokens.contains('cajero'),
      'bicycle_rental' => !queryTokens.any(
        {'bicicleta', 'bicicletas', 'bici', 'bicicletero', 'alquiler'}.contains,
      ),
      'parking' => !queryTokens.any(
        {'parking', 'estacionamiento', 'estacionar'}.contains,
      ),
      _ => false,
    };
  }
}
