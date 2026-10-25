import 'query_normalizer.dart';
import 'ranking_engine.dart';
import 'search_models.dart';

/// Contrato para el repositorio de transporte local (GTFS / SQLite).
abstract interface class LocalTransitSearchRepository {
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  });
}

/// Contrato para el repositorio de geocodificación remota (direcciones y POIs).
abstract interface class GeocodingRepository {
  Future<List<SearchResult>> searchRemote(
    ParsedQuery query, {
    double? biasLatitude,
    double? biasLongitude,
    int limit = 10,
  });
}

/// Contrato para el historial local de búsquedas y destinos recientes.
abstract interface class SearchHistoryRepository {
  Future<List<SearchResult>> getRecent({int limit = 10});
  Future<void> add(SearchResult result);
  Future<void> clear();
}

/// Servicio de dominio principal de búsqueda de destinos en Rumbo.
abstract interface class PlaceSearchService {
  /// Ejecuta una búsqueda integrada combinando fuentes locales y remotas.
  Future<List<SearchResult>> search({
    required String query,
    double? userLatitude,
    double? userLongitude,
    bool allowRemote = true,
  });

  /// Ejecuta una búsqueda estrictamente local (paradas, líneas, recientes y favoritos).
  Future<List<SearchResult>> searchLocal({
    required String query,
    double? userLatitude,
    double? userLongitude,
  });

  Future<List<SearchResult>> getRecentSearches({int limit = 10});
  Future<void> saveRecentSearch(SearchResult result);
  Future<void> clearRecentSearches();
}

/// Implementación predeterminada del servicio de búsqueda integrada.
class DefaultPlaceSearchService implements PlaceSearchService {
  DefaultPlaceSearchService({
    required this.localTransitRepo,
    required this.geocodingRepo,
    required this.historyRepo,
    this.queryParser = const MontevideoQueryParser(),
    this.rankingEngine = const SmartRankingEngine(),
  });

  final LocalTransitSearchRepository localTransitRepo;
  final GeocodingRepository geocodingRepo;
  final SearchHistoryRepository historyRepo;
  final MontevideoQueryParser queryParser;
  final SmartRankingEngine rankingEngine;

  @override
  Future<List<SearchResult>> search({
    required String query,
    double? userLatitude,
    double? userLongitude,
    bool allowRemote = true,
  }) async {
    final parsed = queryParser.parse(query);
    if (parsed.normalized.isEmpty) {
      return getRecentSearches();
    }

    // 1. Consulta local siempre inmediata
    final localCandidates = await localTransitRepo.searchStopsAndLines(
      parsed,
      limit: 15,
    );

    // Si es código numérico de parada y encontramos coincidencia exacta, priorizamos directo
    if (parsed.intent == QueryIntentKind.stopCode &&
        localCandidates.any((c) => c.stopCode == parsed.stopCode)) {
      return rankingEngine.rankAndDeduplicate(
        candidates: localCandidates,
        query: parsed,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
      );
    }

    // 2. Consulta remota si está permitida y la consulta tiene suficiente longitud
    var allCandidates = List<SearchResult>.from(localCandidates);
    if (allowRemote && parsed.normalized.length >= 3) {
      try {
        final remoteCandidates = await geocodingRepo.searchRemote(
          parsed,
          biasLatitude: userLatitude,
          biasLongitude: userLongitude,
          limit: 10,
        );
        allCandidates.addAll(remoteCandidates);
      } catch (_) {
        // En caso de falla de red, conservamos los resultados locales sin interrumpir la experiencia
      }
    }

    return rankingEngine.rankAndDeduplicate(
      candidates: allCandidates,
      query: parsed,
      userLatitude: userLatitude,
      userLongitude: userLongitude,
    );
  }

  @override
  Future<List<SearchResult>> searchLocal({
    required String query,
    double? userLatitude,
    double? userLongitude,
  }) async {
    final parsed = queryParser.parse(query);
    if (parsed.normalized.isEmpty) {
      return getRecentSearches();
    }
    final localCandidates = await localTransitRepo.searchStopsAndLines(
      parsed,
      limit: 15,
    );
    return rankingEngine.rankAndDeduplicate(
      candidates: localCandidates,
      query: parsed,
      userLatitude: userLatitude,
      userLongitude: userLongitude,
    );
  }

  @override
  Future<List<SearchResult>> getRecentSearches({int limit = 10}) =>
      historyRepo.getRecent(limit: limit);

  @override
  Future<void> saveRecentSearch(SearchResult result) => historyRepo.add(result);

  @override
  Future<void> clearRecentSearches() => historyRepo.clear();
}
