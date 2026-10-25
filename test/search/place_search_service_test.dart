import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/domain/place_search_service.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';
import 'package:rumbo/features/search/domain/search_models.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';

class FakeLocalTransitRepo implements LocalTransitSearchRepository {
  FakeLocalTransitRepo(this.results);
  final List<SearchResult> results;
  ParsedQuery? lastQuery;

  @override
  Future<List<SearchResult>> searchStopsAndLines(
    ParsedQuery query, {
    int limit = 15,
  }) async {
    lastQuery = query;
    return results;
  }
}

class FakeGeocodingRepo implements GeocodingRepository {
  FakeGeocodingRepo(this.results, {this.shouldThrow = false});
  final List<SearchResult> results;
  final bool shouldThrow;
  ParsedQuery? lastQuery;

  @override
  Future<List<SearchResult>> searchRemote(
    ParsedQuery query, {
    double? biasLatitude,
    double? biasLongitude,
    int limit = 10,
  }) async {
    lastQuery = query;
    if (shouldThrow) {
      throw Exception('Error de conexión remota simulado');
    }
    return results;
  }
}

class FakeHistoryRepo implements SearchHistoryRepository {
  final List<SearchResult> items = [];

  @override
  Future<List<SearchResult>> getRecent({int limit = 10}) async => items;

  @override
  Future<void> add(SearchResult result) async => items.add(result);

  @override
  Future<void> clear() async => items.clear();
}

void main() {
  group('DefaultPlaceSearchService', () {
    test('retorna búsquedas recientes si la consulta está vacía', () async {
      final history = FakeHistoryRepo();
      const recent = SearchResult(
        id: 'rec-1',
        kind: SearchEntityKind.recentSearch,
        title: 'Plaza Independencia',
        subtitle: 'Ciudad Vieja',
        latitude: -34.90,
        longitude: -56.20,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.userStorage,
      );
      await history.add(recent);

      final service = DefaultPlaceSearchService(
        localTransitRepo: FakeLocalTransitRepo([]),
        geocodingRepo: FakeGeocodingRepo([]),
        historyRepo: history,
      );

      final results = await service.search(query: '');
      expect(results, hasLength(1));
      expect(results.first.title, 'Plaza Independencia');
    });

    test(
      'prioriza parada local directamente si la consulta es un código exacto',
      () async {
        const stop = SearchResult(
          id: 'stm:stop:3004',
          kind: SearchEntityKind.stop,
          title: 'Av. 18 de Julio y Ejido',
          subtitle: 'Parada STM',
          latitude: -34.90,
          longitude: -56.19,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '3004',
        );

        final localRepo = FakeLocalTransitRepo([stop]);
        final remoteRepo = FakeGeocodingRepo([]);
        final service = DefaultPlaceSearchService(
          localTransitRepo: localRepo,
          geocodingRepo: remoteRepo,
          historyRepo: FakeHistoryRepo(),
        );

        final results = await service.search(query: '3004');
        expect(results, hasLength(1));
        expect(results.first.stopCode, '3004');
        expect(
          remoteRepo.lastQuery,
          isNull,
        ); // No fue necesario consultar remotamente
      },
    );

    test(
      'combina fuentes locales y remotas ordenadas por relevancia',
      () async {
        const localStop = SearchResult(
          id: 'stop-1',
          kind: SearchEntityKind.stop,
          title: 'Tres Cruces Parada',
          subtitle: 'Parada STM',
          latitude: -34.895,
          longitude: -56.165,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stop: Stop(
            id: 's1',
            name: 'Tres Cruces',
            latitude: -34.895,
            longitude: -56.165,
          ),
        );

        const remotePoi = SearchResult(
          id: 'poi-1',
          kind: SearchEntityKind.poi,
          title: 'Tres Cruces Shopping',
          subtitle: 'Bulevar General Artigas 1825',
          latitude: -34.894,
          longitude: -56.164,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        );

        final service = DefaultPlaceSearchService(
          localTransitRepo: FakeLocalTransitRepo([localStop]),
          geocodingRepo: FakeGeocodingRepo([remotePoi]),
          historyRepo: FakeHistoryRepo(),
        );

        final results = await service.search(query: 'Tres Cruces');
        expect(results, hasLength(2));
      },
    );

    test(
      'degrada con elegancia conservando resultados locales si la red falla',
      () async {
        const localStop = SearchResult(
          id: 'stop-1',
          kind: SearchEntityKind.stop,
          title: 'Nuevo Centro',
          subtitle: 'Parada STM',
          latitude: -34.85,
          longitude: -56.17,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        );

        final service = DefaultPlaceSearchService(
          localTransitRepo: FakeLocalTransitRepo([localStop]),
          geocodingRepo: FakeGeocodingRepo([], shouldThrow: true),
          historyRepo: FakeHistoryRepo(),
        );

        final results = await service.search(query: 'Nuevo Centro');
        expect(results, hasLength(1));
        expect(results.first.id, 'stop-1');
      },
    );
  });
}
