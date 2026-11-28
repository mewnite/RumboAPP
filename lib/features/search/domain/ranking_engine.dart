import 'dart:math' as math;

import 'query_normalizer.dart';
import 'search_models.dart';

/// Motor inteligente de relevancia, ordenamiento y deduplicación espacial de destinos.
class SmartRankingEngine {
  const SmartRankingEngine({this.queryParser = const MontevideoQueryParser()});

  final MontevideoQueryParser queryParser;

  /// Ordena y deduplica una lista mixta de candidatos según su relevancia para la consulta.
  List<SearchResult> rankAndDeduplicate({
    required List<SearchResult> candidates,
    required ParsedQuery query,
    double? userLatitude,
    double? userLongitude,
    int limit = 15,
  }) {
    if (candidates.isEmpty) return const [];

    final scored = candidates
        .where((candidate) => _textScore(candidate, query) >= 25)
        .map((candidate) {
          final score = computeScore(
            candidate: candidate,
            query: query,
            userLatitude: userLatitude,
            userLongitude: userLongitude,
          );
          return candidate.copyWith(score: score);
        })
        .toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    final deduplicated = <SearchResult>[];
    for (final candidate in scored) {
      final isDuplicate = deduplicated.any((existing) {
        final sameExternalObject =
            candidate.externalId != null &&
            candidate.externalId == existing.externalId;
        if (sameExternalObject || candidate.id == existing.id) return true;

        final distance = _haversineMeters(
          candidate.latitude,
          candidate.longitude,
          existing.latitude,
          existing.longitude,
        );
        return _sameNamedPlace(candidate, existing, distance);
      });

      if (!isDuplicate) {
        deduplicated.add(candidate);
      }
    }

    if (deduplicated.length > limit) {
      return List<SearchResult>.unmodifiable(deduplicated.take(limit));
    }
    return List<SearchResult>.unmodifiable(deduplicated);
  }

  /// Calcula la puntuación ponderada (0 a 100) para un candidato.
  double computeScore({
    required SearchResult candidate,
    required ParsedQuery query,
    double? userLatitude,
    double? userLongitude,
  }) {
    // Si es búsqueda exacta por código de parada y coincide, es acierto pleno
    if (query.intent == QueryIntentKind.stopCode &&
        candidate.stopCode != null &&
        candidate.stopCode == query.stopCode) {
      return 100.0;
    }

    final textScore = _textScore(candidate, query);
    final typeScore = _typeScore(candidate, query);
    final precisionScore = _precisionScore(candidate);
    final localityScore = _localityScore(candidate);
    final distanceScore = _distanceScore(
      candidate,
      userLatitude,
      userLongitude,
    );

    return (0.66 * textScore +
            0.20 * typeScore +
            0.08 * precisionScore +
            0.04 * localityScore +
            0.02 * distanceScore)
        .clamp(0.0, 100.0);
  }

  double _textScore(SearchResult candidate, ParsedQuery query) {
    final queryText = query.normalized;
    if (queryText.isEmpty) return 50;

    final category = candidate.category?.toLowerCase() ?? '';
    if (query.intent == QueryIntentKind.poi ||
        query.intent == QueryIntentKind.general ||
        query.intent == QueryIntentKind.unknown) {
      final normalizedQuery = queryParser.normalizeText(query.raw);
      final categoryIsUnrequestedService =
          (category.endsWith(':parking') &&
              !normalizedQuery.contains('parking') &&
              !normalizedQuery.contains('estacionamiento')) ||
          (category.endsWith(':bicycle_rental') &&
              !normalizedQuery.contains('bicicleta') &&
              !normalizedQuery.contains('bici') &&
              !normalizedQuery.contains('bicicletero') &&
              !normalizedQuery.contains('alquiler'));
      if (categoryIsUnrequestedService) return 0;
    }

    if (query.intent == QueryIntentKind.stopCode) {
      if (candidate.stopCode != null && candidate.stopCode == query.stopCode) {
        return 100.0;
      }
      return candidate.title.contains(query.stopCode!) ? 90 : 0;
    }

    if (query.intent == QueryIntentKind.intersection) {
      final candidateText = _candidateText(candidate);
      final hasFirst = queryParser.streetMatches(
        candidateText,
        query.street1 ?? '',
      );
      final hasSecond = queryParser.streetMatches(
        candidateText,
        query.street2 ?? '',
      );
      if (hasFirst && hasSecond) {
        return candidate.kind == SearchEntityKind.intersection ? 100 : 78;
      }
      return 0;
    }

    if (query.intent == QueryIntentKind.addressWithNumber) {
      if (candidate.kind != SearchEntityKind.address ||
          !queryParser.streetMatches(
            _candidateText(candidate),
            query.street1 ?? '',
          )) {
        return 0;
      }
      final requested = query.doorNumber;
      if (requested == null) return 40;
      final requestedNumber = requested.toString();
      final hasRequestedNumber =
          _containsWholeNumber(candidate.houseNumber, requestedNumber) ||
          _containsWholeNumber(candidate.title, requestedNumber);
      if (hasRequestedNumber &&
          candidate.precision == GeoPrecision.exactDoorNumber) {
        return 100;
      }
      return candidate.precision == GeoPrecision.unconfirmedDoorNumber
          ? 58
          : 35;
    }

    if (query.intent == QueryIntentKind.routeCode) {
      final route = query.routeCode?.toLowerCase() ?? '';
      if (candidate.title.toLowerCase() == route) return 100.0;
      if (candidate.lines.any((line) => line.toLowerCase() == route)) {
        return 90.0;
      }
      return 0;
    }

    final queryNorm = queryParser.normalizeText(queryText);
    final titles = [
      candidate.title,
      ...candidate.aliases,
    ].map(queryParser.normalizeText).where((title) => title.isNotEmpty);
    final titleMatches = titles.toList(growable: false);
    if (titleMatches.contains(queryNorm)) return 100;
    if (titleMatches.any((title) => title.startsWith(queryNorm))) return 88;
    if (titleMatches.any((title) => title.contains(queryNorm))) return 82;

    const ignoredTokens = {'de', 'del', 'la', 'las', 'el', 'los', 'y'};
    final queryTokens = queryNorm
        .split(' ')
        .where((token) => token.length > 1 && !ignoredTokens.contains(token));
    final titleTokenText = titleMatches.join(' ');
    if (queryTokens.isNotEmpty) {
      final tokens = queryTokens.toList(growable: false);
      final matchedTokens = tokens
          .where((token) => _containsToken(titleTokenText, token))
          .length;
      if (matchedTokens == tokens.length) return 76;
    }

    final contextualText = queryParser.normalizeText(
      '${candidate.subtitle} ${candidate.street ?? ''}',
    );
    if (contextualText == queryNorm || contextualText.contains(queryNorm)) {
      return 45;
    }
    return 5;
  }

  double _typeScore(SearchResult candidate, ParsedQuery query) {
    if (query.intent == QueryIntentKind.poi) {
      return switch (candidate.kind) {
        SearchEntityKind.poi => 100,
        SearchEntityKind.address => 25,
        SearchEntityKind.stop => 20,
        _ => 10,
      };
    }
    if (query.intent == QueryIntentKind.neighborhood) {
      return switch (candidate.kind) {
        SearchEntityKind.neighborhood => 100,
        SearchEntityKind.geographicArea => 60,
        SearchEntityKind.poi => 20,
        _ => 10,
      };
    }
    if (query.intent == QueryIntentKind.street) {
      return switch (candidate.kind) {
        SearchEntityKind.address => 100,
        SearchEntityKind.street => 100,
        SearchEntityKind.poi => 15,
        _ => 10,
      };
    }
    if (query.intent == QueryIntentKind.geographicArea) {
      return switch (candidate.kind) {
        SearchEntityKind.geographicArea => 100,
        SearchEntityKind.neighborhood => 65,
        SearchEntityKind.poi => 30,
        _ => 10,
      };
    }
    if (query.intent == QueryIntentKind.addressWithNumber) {
      return switch (candidate.kind) {
        SearchEntityKind.address => 100,
        SearchEntityKind.poi => 20,
        SearchEntityKind.neighborhood => 10,
        SearchEntityKind.street => 30,
        SearchEntityKind.geographicArea => 5,
        _ => 0,
      };
    }
    if (query.intent == QueryIntentKind.intersection) {
      return switch (candidate.kind) {
        SearchEntityKind.intersection => 100,
        SearchEntityKind.stop => 58,
        SearchEntityKind.address => 15,
        _ => 0,
      };
    }
    if (query.intent == QueryIntentKind.routeCode) {
      return candidate.kind == SearchEntityKind.route ? 100 : 0;
    }
    switch (candidate.kind) {
      case SearchEntityKind.stop:
        return 32.0;
      case SearchEntityKind.route:
        return 45.0;
      case SearchEntityKind.address:
        return 70.0;
      case SearchEntityKind.intersection:
        return 70.0;
      case SearchEntityKind.street:
        return 75.0;
      case SearchEntityKind.geographicArea:
        return 65.0;
      case SearchEntityKind.poi:
        return 90.0;
      case SearchEntityKind.favorite:
        return 78.0;
      case SearchEntityKind.recentSearch:
        return 55.0;
      case SearchEntityKind.neighborhood:
        return 50.0;
    }
  }

  double _localityScore(SearchResult candidate) {
    final locality = queryParser.normalizeText(
      '${candidate.subtitle} ${candidate.neighborhood ?? ''}',
    );
    if (locality.contains('montevideo')) return 100;
    if (locality.contains('uruguay')) return 70;
    return 25;
  }

  String _candidateText(SearchResult candidate) => [
    candidate.title,
    candidate.subtitle,
    candidate.street,
    candidate.houseNumber,
    ...candidate.aliases,
  ].whereType<String>().join(' ');

  bool _containsWholeNumber(String? value, String number) {
    if (value == null || value.isEmpty) return false;
    return RegExp(r'(^|[^\d])' + number + r'($|[^\d])').hasMatch(value);
  }

  bool _containsToken(String text, String token) {
    final exact = RegExp('(^|\\s)${RegExp.escape(token)}(\\s|\$)');
    if (exact.hasMatch(text)) return true;
    return text.split(' ').any((candidate) => _isOneEditAway(candidate, token));
  }

  bool _isOneEditAway(String first, String second) {
    if ((first.length - second.length).abs() > 1) return false;
    var firstIndex = 0;
    var secondIndex = 0;
    var edits = 0;
    while (firstIndex < first.length && secondIndex < second.length) {
      if (first[firstIndex] == second[secondIndex]) {
        firstIndex++;
        secondIndex++;
        continue;
      }
      if (++edits > 1) return false;
      if (first.length > second.length) {
        firstIndex++;
      } else if (second.length > first.length) {
        secondIndex++;
      } else {
        firstIndex++;
        secondIndex++;
      }
    }
    return edits +
            (firstIndex < first.length ? 1 : 0) +
            (secondIndex < second.length ? 1 : 0) <=
        1;
  }

  bool _sameNamedPlace(
    SearchResult first,
    SearchResult second,
    double distanceMeters,
  ) {
    final sameConfirmedAddress =
        first.kind == SearchEntityKind.address &&
        second.kind == SearchEntityKind.address &&
        first.precision == GeoPrecision.exactDoorNumber &&
        second.precision == GeoPrecision.exactDoorNumber &&
        queryParser.normalizeText(first.title) ==
            queryParser.normalizeText(second.title) &&
        _localityScore(first) == 100 &&
        _localityScore(second) == 100;
    if (sameConfirmedAddress) return true;

    final firstNames = _normalizedNames(first);
    final secondNames = _normalizedNames(second);
    final exactNamesMatch = firstNames.any(secondNames.contains);
    if (distanceMeters > 20) {
      return distanceMeters <= 500 &&
          first.kind == SearchEntityKind.neighborhood &&
          second.kind == SearchEntityKind.neighborhood &&
          exactNamesMatch &&
          _localityScore(first) == 100 &&
          _localityScore(second) == 100;
    }

    final namesMatch =
        exactNamesMatch ||
        firstNames.any(
          (firstName) => secondNames.any(
            (secondName) => _similarNames(firstName, secondName),
          ),
        );
    if (!namesMatch) return false;

    final sameKind = first.kind == second.kind;
    final localRemoteTwin =
        distanceMeters <= 8 &&
        {
          first.kind,
          second.kind,
        }.containsAll({SearchEntityKind.stop, SearchEntityKind.poi});
    final addressPlaceTwin =
        distanceMeters <= 8 &&
        {
          first.kind,
          second.kind,
        }.containsAll({SearchEntityKind.address, SearchEntityKind.poi});
    final sameCategory =
        first.category != null && first.category == second.category;
    return localRemoteTwin ||
        addressPlaceTwin ||
        (sameKind && (sameCategory || distanceMeters <= 8));
  }

  bool _similarNames(String first, String second) {
    if (first.replaceAll(' ', '') == second.replaceAll(' ', '')) return true;
    final firstTokens = first
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    final secondTokens = second
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    if (firstTokens.isEmpty || secondTokens.isEmpty) return false;
    final intersectionSize = firstTokens.intersection(secondTokens).length;
    final overlap =
        intersectionSize / math.min(firstTokens.length, secondTokens.length);
    return overlap >= 0.8;
  }

  Set<String> _normalizedNames(SearchResult result) => {
    result.title,
    ...result.aliases,
  }.map(queryParser.normalizeText).where((name) => name.isNotEmpty).toSet();

  double _precisionScore(SearchResult candidate) {
    switch (candidate.precision) {
      case GeoPrecision.exactDoorNumber:
        return 100.0;
      case GeoPrecision.unconfirmedDoorNumber:
        return 30.0;
      case GeoPrecision.intersectionPoint:
        return 95.0;
      case GeoPrecision.approximateIntersection:
        return 35.0;
      case GeoPrecision.stopCoordinates:
        return 90.0;
      case GeoPrecision.rooftopPoi:
        return 85.0;
      case GeoPrecision.streetSegment:
        return 45.0;
      case GeoPrecision.approximateArea:
        return 25.0;
    }
  }

  double _distanceScore(
    SearchResult candidate,
    double? userLatitude,
    double? userLongitude,
  ) {
    if (userLatitude == null || userLongitude == null) {
      return 50.0; // Neutro si el usuario no tiene ubicación activa
    }
    final distanceMeters = _haversineMeters(
      userLatitude,
      userLongitude,
      candidate.latitude,
      candidate.longitude,
    );

    // Decaimiento exponencial suave con constante de 5000 metros
    return (100.0 * math.exp(-distanceMeters / 5000.0)).clamp(0.0, 100.0);
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Radio medio de la Tierra en metros
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaPhi = (lat2 - lat1) * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;

    final a =
        math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return r * c;
  }
}
