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

    final scored = candidates.map((candidate) {
      final score = computeScore(
        candidate: candidate,
        query: query,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
      );
      return candidate.copyWith(score: score);
    }).toList();

    // Orden inicial por puntuación descendente
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Deduplicación espacial y semántica
    final deduplicated = <SearchResult>[];
    for (final candidate in scored) {
      final isDuplicate = deduplicated.any((existing) {
        final distance = _haversineMeters(
          candidate.latitude,
          candidate.longitude,
          existing.latitude,
          existing.longitude,
        );

        // Si están a menos de 25 metros y comparten similitud en el nombre
        if (distance < 25) {
          final cNorm = queryParser.normalizeText(candidate.title);
          final eNorm = queryParser.normalizeText(existing.title);
          final cClean = cNorm.replaceAll(' ', '');
          final eClean = eNorm.replaceAll(' ', '');
          if (cNorm == eNorm ||
              cNorm.contains(eNorm) ||
              eNorm.contains(cNorm) ||
              cClean == eClean ||
              cClean.contains(eClean) ||
              eClean.contains(cClean)) {
            return true;
          }
        }

        // Si tienen exactamente las mismas coordenadas y el mismo tipo
        if (distance < 5 && candidate.kind == existing.kind) {
          return true;
        }

        return false;
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

    final sText = _textScore(candidate, query);
    final sType = _typeScore(candidate, query);
    final sPrec = _precisionScore(candidate);
    final sDist = _distanceScore(candidate, userLatitude, userLongitude);

    // Ponderación: 50% texto, 25% tipo, 15% precisión, 10% distancia
    final total =
        (0.50 * sText) + (0.25 * sType) + (0.15 * sPrec) + (0.10 * sDist);
    return total.clamp(0.0, 100.0);
  }

  double _textScore(SearchResult candidate, ParsedQuery query) {
    final titleNorm = queryParser.normalizeText(candidate.title);
    final subtitleNorm = queryParser.normalizeText(candidate.subtitle);
    final qNorm = query.normalized;

    if (qNorm.isEmpty) return 50.0;

    // Caso 1: Búsqueda por código de parada
    if (query.intent == QueryIntentKind.stopCode) {
      if (candidate.stopCode != null && candidate.stopCode == query.stopCode) {
        return 100.0;
      }
      if (candidate.title.contains(query.stopCode!)) return 90.0;
    }

    // Caso 2: Intersección (ambas calles deben coincidir)
    if (query.intent == QueryIntentKind.intersection) {
      final s1 = query.street1 ?? '';
      final s2 = query.street2 ?? '';
      final fullText = '$titleNorm $subtitleNorm';
      final hasS1 = fullText.contains(s1);
      final hasS2 = fullText.contains(s2);
      if (hasS1 && hasS2) return 95.0;
      if (hasS1 || hasS2) return 60.0;
    }

    // Caso 3: Dirección con número
    if (query.intent == QueryIntentKind.addressWithNumber) {
      final street = query.street1 ?? '';
      final numStr = query.doorNumber.toString();
      final fullText = '$titleNorm $subtitleNorm';
      final hasStreet = fullText.contains(street);
      final hasNum = fullText.contains(numStr);
      if (hasStreet && hasNum) return 95.0;
      if (hasStreet) return 70.0;
    }

    // Caso 4: Búsqueda por línea de bus (ej. "522")
    if (query.intent == QueryIntentKind.routeCode) {
      final route = query.routeCode?.toLowerCase() ?? '';
      if (candidate.title.toLowerCase() == route) return 100.0;
      if (candidate.lines.any((line) => line.toLowerCase() == route)) {
        return 90.0;
      }
    }

    // Coincidencia exacta completa
    if (titleNorm == qNorm) return 100.0;

    // Coincidencia por prefijo
    if (titleNorm.startsWith(qNorm)) return 85.0;

    // Contiene la consulta completa
    if (titleNorm.contains(qNorm)) return 75.0;
    if (subtitleNorm.contains(qNorm)) return 65.0;

    // Coincidencia de tokens
    final qTokens = qNorm.split(' ').where((t) => t.length > 2).toList();
    if (qTokens.isNotEmpty) {
      var matches = 0;
      for (final token in qTokens) {
        if (titleNorm.contains(token) || subtitleNorm.contains(token)) {
          matches++;
        }
      }
      final ratio = matches / qTokens.length;
      return (ratio * 60.0).clamp(10.0, 60.0);
    }

    return 20.0;
  }

  double _typeScore(SearchResult candidate, ParsedQuery query) {
    switch (candidate.kind) {
      case SearchEntityKind.stop:
        // Paradas con múltiples líneas de conexión son más valiosas para el viaje
        final lineBonus = math.min(candidate.lines.length * 3.0, 15.0);
        return 75.0 + lineBonus;
      case SearchEntityKind.route:
        return 80.0;
      case SearchEntityKind.address:
        return 80.0;
      case SearchEntityKind.intersection:
        return 80.0;
      case SearchEntityKind.poi:
        return 75.0;
      case SearchEntityKind.favorite:
        return 90.0;
      case SearchEntityKind.recentSearch:
        return 70.0;
      case SearchEntityKind.neighborhood:
        return 50.0;
    }
  }

  double _precisionScore(SearchResult candidate) {
    switch (candidate.precision) {
      case GeoPrecision.exactDoorNumber:
        return 100.0;
      case GeoPrecision.intersectionPoint:
        return 95.0;
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
