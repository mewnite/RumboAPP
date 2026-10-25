import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';
import 'package:rumbo/features/search/domain/ranking_engine.dart';
import 'package:rumbo/features/search/domain/search_models.dart';

void main() {
  const engine = SmartRankingEngine();
  const parser = MontevideoQueryParser();

  group('SmartRankingEngine - Scoring de relevancia', () {
    test('coincidencia exacta supera a coincidencia parcial o por prefijo', () {
      final query = parser.parse('Tres Cruces');

      const exact = SearchResult(
        id: '1',
        kind: SearchEntityKind.poi,
        title: 'Tres Cruces',
        subtitle: 'Terminal y Shopping',
        latitude: -34.89,
        longitude: -56.16,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      const partial = SearchResult(
        id: '2',
        kind: SearchEntityKind.address,
        title: 'Tres Cruces Residencial',
        subtitle: 'Montevideo',
        latitude: -34.89,
        longitude: -56.16,
        precision: GeoPrecision.streetSegment,
        source: SearchDataSource.openStreetMap,
      );

      final scoreExact = engine.computeScore(candidate: exact, query: query);
      final scorePartial = engine.computeScore(
        candidate: partial,
        query: query,
      );

      expect(scoreExact, greaterThan(scorePartial));
    });

    test('búsqueda por código de parada otorga puntaje máximo a parada correspondiente', () {
      final query = parser.parse('3004');

      const matchStop = SearchResult(
        id: 'stop-3004',
        kind: SearchEntityKind.stop,
        title: 'Av. 18 de Julio y Ejido',
        subtitle: 'Parada STM · Código 3004',
        latitude: -34.905,
        longitude: -56.191,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
        stopCode: '3004',
        lines: ['14', '21', '180'],
      );

      const otherStop = SearchResult(
        id: 'stop-9999',
        kind: SearchEntityKind.stop,
        title: 'Colonia y Andes',
        subtitle: 'Parada STM · Código 9999',
        latitude: -34.903,
        longitude: -56.198,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
        stopCode: '9999',
      );

      final scoreMatch = engine.computeScore(
        candidate: matchStop,
        query: query,
      );
      final scoreOther = engine.computeScore(
        candidate: otherStop,
        query: query,
      );

      expect(scoreMatch, greaterThan(90.0));
      expect(scoreMatch, greaterThan(scoreOther));
    });

    test('intersección prioriza candidatos que contienen ambas calles', () {
      final query = parser.parse('18 de Julio y Ejido');

      const bothStreets = SearchResult(
        id: 'cross-1',
        kind: SearchEntityKind.intersection,
        title: 'Av. 18 de Julio y Ejido',
        subtitle: 'Centro, Montevideo',
        latitude: -34.9059,
        longitude: -56.1911,
        precision: GeoPrecision.intersectionPoint,
        source: SearchDataSource.ideUruguay,
      );

      const oneStreet = SearchResult(
        id: 'cross-2',
        kind: SearchEntityKind.address,
        title: 'Av. 18 de Julio 1500',
        subtitle: 'Centro, Montevideo',
        latitude: -34.9050,
        longitude: -56.1850,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.ideUruguay,
      );

      final scoreBoth = engine.computeScore(
        candidate: bothStreets,
        query: query,
      );
      final scoreOne = engine.computeScore(candidate: oneStreet, query: query);

      expect(scoreBoth, greaterThan(scoreOne));
    });

    test('proximidad desempatada pero nunca anula la coincidencia textual', () {
      final query = parser.parse('Hospital de Clínicas');
      // Usuario ubicado en Pocitos (-34.915, -56.150)
      const userLat = -34.915;
      const userLon = -34.150;

      // Candidato 1: Hospital de Clínicas (exacto, a ~3 km)
      const clinicas = SearchResult(
        id: 'clinicas',
        kind: SearchEntityKind.poi,
        title: 'Hospital de Clínicas',
        subtitle: 'Parque Batlle',
        latitude: -34.891,
        longitude: -56.151,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      // Candidato 2: Lugar irrelevante pero muy cercano (a 100 m)
      const nearbyWrong = SearchResult(
        id: 'nearby',
        kind: SearchEntityKind.poi,
        title: 'Clínica Veterinaria Pocitos',
        subtitle: 'Pocitos',
        latitude: -34.914,
        longitude: -56.150,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      final scoreClinicas = engine.computeScore(
        candidate: clinicas,
        query: query,
        userLatitude: userLat,
        userLongitude: userLon,
      );
      final scoreNearby = engine.computeScore(
        candidate: nearbyWrong,
        query: query,
        userLatitude: userLat,
        userLongitude: userLon,
      );

      expect(scoreClinicas, greaterThan(scoreNearby));
    });
  });

  group('SmartRankingEngine - Deduplicación espacial', () {
    test('deduplica candidatos a menos de 25 metros con nombres similares', () {
      final query = parser.parse('Nuevo Centro');

      const item1 = SearchResult(
        id: 'osm-1',
        kind: SearchEntityKind.poi,
        title: 'Nuevo Centro Shopping',
        subtitle: 'Montevideo',
        latitude: -34.85000,
        longitude: -56.17000,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      const item2 = SearchResult(
        id: 'ide-1',
        kind: SearchEntityKind.address,
        title: 'Nuevocentro Shopping',
        subtitle: 'Montevideo',
        latitude: -34.85005, // ~6 metros de diferencia
        longitude: -56.17005,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.ideUruguay,
      );

      const differentPlace = SearchResult(
        id: 'other',
        kind: SearchEntityKind.neighborhood,
        title: 'Centro',
        subtitle: 'Barrio Montevideo',
        latitude: -34.905,
        longitude: -56.195,
        precision: GeoPrecision.approximateArea,
        source: SearchDataSource.openStreetMap,
      );

      final results = engine.rankAndDeduplicate(
        candidates: [item1, item2, differentPlace],
        query: query,
      );

      expect(results, hasLength(2));
      expect(results.first.title, contains('Nuevo Centro'));
    });
  });
}
