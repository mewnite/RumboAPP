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

    test('un POI coincidente supera una parada cercana no relacionada', () {
      final query = parser.parse('Palacio Legislativo');
      const poi = SearchResult(
        id: 'poi',
        kind: SearchEntityKind.poi,
        title: 'Palacio Legislativo',
        subtitle: 'Avenida de las Leyes · Montevideo',
        latitude: -34.8914,
        longitude: -56.1975,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );
      const stop = SearchResult(
        id: 'stop',
        kind: SearchEntityKind.stop,
        title: 'Parada Palacio',
        subtitle: 'Parada STM · Montevideo',
        latitude: -34.8915,
        longitude: -56.1976,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
      );

      final ranked = engine.rankAndDeduplicate(
        candidates: [stop, poi],
        query: query,
      );

      expect(ranked.first, poi);
    });

    test('deduplica por OSM ID y conserva alias para nombres alternativos', () {
      final query = parser.parse('SODRE');
      const official = SearchResult(
        id: 'remote-1',
        externalId: 'osm:relation:9001',
        kind: SearchEntityKind.poi,
        title: 'Auditorio Nacional Adela Reta',
        subtitle: 'Andes · Montevideo',
        latitude: -34.9037,
        longitude: -56.1882,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        aliases: ['SODRE'],
      );
      const duplicate = SearchResult(
        id: 'remote-2',
        externalId: 'osm:relation:9001',
        kind: SearchEntityKind.poi,
        title: 'SODRE',
        subtitle: 'Andes · Montevideo',
        latitude: -34.9038,
        longitude: -56.1883,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      final results = engine.rankAndDeduplicate(
        candidates: [official, duplicate],
        query: query,
      );

      expect(results, hasLength(1));
      expect(results.single.title, 'Auditorio Nacional Adela Reta');
    });

    test('parking y alquiler de bicicletas no desplazan al POI solicitado', () {
      final query = parser.parse('Shopping Punta Carretas');
      const parking = SearchResult(
        id: 'parking',
        kind: SearchEntityKind.poi,
        title: 'Parking Punta Carretas',
        subtitle: 'Montevideo',
        latitude: -34.923,
        longitude: -56.158,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        category: 'amenity:parking',
      );
      const shopping = SearchResult(
        id: 'shopping',
        kind: SearchEntityKind.poi,
        title: 'Shopping Punta Carretas',
        subtitle: 'Montevideo',
        latitude: -34.923,
        longitude: -56.158,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        category: 'shop:mall',
      );

      final results = engine.rankAndDeduplicate(
        candidates: [parking, shopping],
        query: query,
      );

      expect(results, hasLength(1));
      expect(results.single.category, 'shop:mall');
    });

    test('deduplica un POI remoto con su parada local coincidente', () {
      final query = parser.parse('SODRE');
      const stop = SearchResult(
        id: 'stm:stop:100',
        kind: SearchEntityKind.stop,
        title: 'SODRE',
        subtitle: 'Parada STM',
        latitude: -34.9037,
        longitude: -56.1882,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
      );
      const poi = SearchResult(
        id: 'osm:poi',
        kind: SearchEntityKind.poi,
        title: 'Auditorio Nacional Adela Reta',
        subtitle: 'Andes · Montevideo',
        latitude: -34.9037,
        longitude: -56.1882,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        aliases: ['SODRE'],
      );

      final results = engine.rankAndDeduplicate(
        candidates: [stop, poi],
        query: query,
      );

      expect(results, hasLength(1));
      expect(results.single.kind, SearchEntityKind.poi);
    });

    test(
      'elimina candidatos de intersección que solo coinciden con una calle',
      () {
        const streetStop = SearchResult(
          id: 'stm:stop:200',
          kind: SearchEntityKind.stop,
          title: 'Parada Rivera',
          subtitle: 'Parada STM · Avenida Rivera',
          latitude: -34.9,
          longitude: -56.1,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        );

        final results = engine.rankAndDeduplicate(
          candidates: [streetStop],
          query: parser.parse('Rivera esquina Soca'),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'no muestra una parada que coincide solo con parte del nombre de un POI',
      () {
        const unrelatedStop = SearchResult(
          id: 'stm:stop:300',
          kind: SearchEntityKind.stop,
          title: 'Camino Cibils - Costanera Parque Tomkinson',
          subtitle: 'Parada STM · Montevideo',
          latitude: -34.8,
          longitude: -56.2,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        );

        final results = engine.rankAndDeduplicate(
          candidates: [unrelatedStop],
          query: parser.parse('Parque Rodo'),
        );

        expect(results, isEmpty);
      },
    );
  });

  group('SmartRankingEngine - Deduplicación espacial', () {
    test('deduplica registros exactos de una misma dirección de puerta', () {
      final query = parser.parse('Rivera');
      const address1 = SearchResult(
        id: 'osm:node:1',
        kind: SearchEntityKind.address,
        title: 'Avenida General Rivera 3245',
        subtitle: 'Parque Batlle · Montevideo',
        latitude: -34.8950,
        longitude: -56.1600,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.openStreetMap,
      );
      const address2 = SearchResult(
        id: 'osm:way:2',
        kind: SearchEntityKind.address,
        title: 'Avenida General Rivera 3245',
        subtitle: 'Parque Batlle · Montevideo',
        latitude: -34.8970,
        longitude: -56.1620,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.openStreetMap,
      );
      const nearbyDifferentAddress = SearchResult(
        id: 'osm:node:3',
        kind: SearchEntityKind.address,
        title: 'Avenida General Rivera 3250',
        subtitle: 'Parque Batlle · Montevideo',
        latitude: -34.8951,
        longitude: -56.1601,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.openStreetMap,
      );

      final results = engine.rankAndDeduplicate(
        candidates: [address1, address2, nearbyDifferentAddress],
        query: query,
      );

      expect(results, hasLength(2));
      expect(
        results.map((result) => result.title),
        containsAll([
          'Avenida General Rivera 3245',
          'Avenida General Rivera 3250',
        ]),
      );
    });

    test('deduplica dos representaciones OSM del mismo barrio', () {
      final query = parser.parse('Parque Rodo');
      const suburb = SearchResult(
        id: 'osm:node:953469120',
        externalId: 'osm:node:953469120',
        kind: SearchEntityKind.neighborhood,
        title: 'Parque Rodó',
        subtitle: 'Parque Rodó · Montevideo',
        latitude: -34.9100822,
        longitude: -56.1697776,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        category: 'place:suburb',
      );
      const boundary = SearchResult(
        id: 'osm:relation:13353266',
        externalId: 'osm:relation:13353266',
        kind: SearchEntityKind.neighborhood,
        title: 'Parque Rodó',
        subtitle: 'Parque Rodó · Montevideo',
        latitude: -34.9141426,
        longitude: -56.1676888,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        category: 'boundary:neighborhood',
      );
      const park = SearchResult(
        id: 'osm:way:36807838',
        externalId: 'osm:way:36807838',
        kind: SearchEntityKind.poi,
        title: 'Parque Rodó',
        subtitle: 'Parque Rodó · Montevideo',
        latitude: -34.9155643,
        longitude: -56.1675704,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
        category: 'leisure:park',
      );

      final results = engine.rankAndDeduplicate(
        candidates: [suburb, boundary, park],
        query: query,
      );

      expect(results, hasLength(2));
      expect(
        results.where((result) => result.kind == SearchEntityKind.neighborhood),
        hasLength(1),
      );
      expect(
        results.where((result) => result.kind == SearchEntityKind.poi),
        hasLength(1),
      );
    });

    test('conserva lugares diferentes cercanos aunque compartan un token', () {
      final query = parser.parse('Parque');
      const firstPark = SearchResult(
        id: 'park-1',
        kind: SearchEntityKind.poi,
        title: 'Parque Rodó',
        subtitle: 'Montevideo',
        latitude: -34.91556,
        longitude: -56.16757,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );
      const secondPark = SearchResult(
        id: 'park-2',
        kind: SearchEntityKind.poi,
        title: 'Parque Batlle',
        subtitle: 'Montevideo',
        latitude: -34.91560,
        longitude: -56.16760,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      );

      final results = engine.rankAndDeduplicate(
        candidates: [firstPark, secondPark],
        query: query,
      );

      expect(results, hasLength(2));
    });

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

      expect(results, hasLength(1));
      expect(results.first.title, contains('Nuevo Centro'));
    });
  });
}
