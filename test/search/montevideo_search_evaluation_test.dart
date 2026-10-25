import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';
import 'package:rumbo/features/search/domain/ranking_engine.dart';
import 'package:rumbo/features/search/domain/search_models.dart';

class EvaluationTestCase {
  const EvaluationTestCase({
    required this.query,
    required this.expectedIntent,
    required this.expectedPrimaryMatch,
    required this.targetLatitude,
    required this.targetLongitude,
    required this.candidatePool,
  });

  final String query;
  final QueryIntentKind expectedIntent;
  final String expectedPrimaryMatch;
  final double targetLatitude;
  final double targetLongitude;
  final List<SearchResult> candidatePool;
}

void main() {
  const parser = MontevideoQueryParser();
  const engine = SmartRankingEngine();

  // Dataset de 30 consultas canónicas de Montevideo
  final testCases = <EvaluationTestCase>[
    // 1-5: Direcciones con número de puerta
    EvaluationTestCase(
      query: 'Av. Italia 2450',
      expectedIntent: QueryIntentKind.addressWithNumber,
      expectedPrimaryMatch: 'Av. Italia 2450',
      targetLatitude: -34.8887,
      targetLongitude: -56.1492,
      candidatePool: const [
        SearchResult(
          id: '1a',
          kind: SearchEntityKind.address,
          title: 'Av. Italia 2450',
          subtitle: 'La Blanqueada',
          latitude: -34.8887,
          longitude: -56.1492,
          precision: GeoPrecision.exactDoorNumber,
          source: SearchDataSource.ideUruguay,
        ),
        SearchResult(
          id: '1b',
          kind: SearchEntityKind.address,
          title: 'Avenida Italia',
          subtitle: 'Carrasco',
          latitude: -34.87,
          longitude: -56.05,
          precision: GeoPrecision.streetSegment,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: '18 de Julio 1234',
      expectedIntent: QueryIntentKind.addressWithNumber,
      expectedPrimaryMatch: 'Av. 18 de Julio 1234',
      targetLatitude: -34.906,
      targetLongitude: -56.191,
      candidatePool: const [
        SearchResult(
          id: '2a',
          kind: SearchEntityKind.address,
          title: 'Av. 18 de Julio 1234',
          subtitle: 'Centro',
          latitude: -34.906,
          longitude: -56.191,
          precision: GeoPrecision.exactDoorNumber,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Bvar. Artigas 1825',
      expectedIntent: QueryIntentKind.addressWithNumber,
      expectedPrimaryMatch: 'Bulevar Artigas 1825',
      targetLatitude: -34.894,
      targetLongitude: -56.164,
      candidatePool: const [
        SearchResult(
          id: '3a',
          kind: SearchEntityKind.address,
          title: 'Bulevar Artigas 1825',
          subtitle: 'Tres Cruces',
          latitude: -34.894,
          longitude: -56.164,
          precision: GeoPrecision.exactDoorNumber,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'San José 1114',
      expectedIntent: QueryIntentKind.addressWithNumber,
      expectedPrimaryMatch: 'San José 1114',
      targetLatitude: -34.907,
      targetLongitude: -56.194,
      candidatePool: const [
        SearchResult(
          id: '4a',
          kind: SearchEntityKind.address,
          title: 'San José 1114',
          subtitle: 'Centro',
          latitude: -34.907,
          longitude: -56.194,
          precision: GeoPrecision.exactDoorNumber,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Colonia 1250',
      expectedIntent: QueryIntentKind.addressWithNumber,
      expectedPrimaryMatch: 'Colonia 1250',
      targetLatitude: -34.905,
      targetLongitude: -56.190,
      candidatePool: const [
        SearchResult(
          id: '5a',
          kind: SearchEntityKind.address,
          title: 'Colonia 1250',
          subtitle: 'Centro',
          latitude: -34.905,
          longitude: -56.190,
          precision: GeoPrecision.exactDoorNumber,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),

    // 6-10: Intersecciones
    EvaluationTestCase(
      query: '18 de Julio y Ejido',
      expectedIntent: QueryIntentKind.intersection,
      expectedPrimaryMatch: '18 de Julio y Ejido',
      targetLatitude: -34.9059,
      targetLongitude: -56.1911,
      candidatePool: const [
        SearchResult(
          id: '6a',
          kind: SearchEntityKind.intersection,
          title: 'Av. 18 de Julio y Ejido',
          subtitle: 'Intendencia de Montevideo',
          latitude: -34.9059,
          longitude: -56.1911,
          precision: GeoPrecision.intersectionPoint,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Rivera esq. Soca',
      expectedIntent: QueryIntentKind.intersection,
      expectedPrimaryMatch: 'Rivera y Soca',
      targetLatitude: -34.902,
      targetLongitude: -56.155,
      candidatePool: const [
        SearchResult(
          id: '7a',
          kind: SearchEntityKind.intersection,
          title: 'Avenida General Rivera y Francisco Soca',
          subtitle: 'Pocitos',
          latitude: -34.902,
          longitude: -56.155,
          precision: GeoPrecision.intersectionPoint,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Colonia y Convención',
      expectedIntent: QueryIntentKind.intersection,
      expectedPrimaryMatch: 'Colonia y Convención',
      targetLatitude: -34.906,
      targetLongitude: -56.197,
      candidatePool: const [
        SearchResult(
          id: '8a',
          kind: SearchEntityKind.intersection,
          title: 'Colonia y Convención',
          subtitle: 'Centro',
          latitude: -34.906,
          longitude: -56.197,
          precision: GeoPrecision.intersectionPoint,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Av. Brasil / Libertad',
      expectedIntent: QueryIntentKind.intersection,
      expectedPrimaryMatch: 'Brasil y Libertad',
      targetLatitude: -34.914,
      targetLongitude: -56.153,
      candidatePool: const [
        SearchResult(
          id: '9a',
          kind: SearchEntityKind.intersection,
          title: 'Avenida Brasil y Libertad',
          subtitle: 'Pocitos',
          latitude: -34.914,
          longitude: -56.153,
          precision: GeoPrecision.intersectionPoint,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),
    EvaluationTestCase(
      query: '8 de Octubre esq Propios',
      expectedIntent: QueryIntentKind.intersection,
      expectedPrimaryMatch: '8 de Octubre y Propios',
      targetLatitude: -34.881,
      targetLongitude: -56.143,
      candidatePool: const [
        SearchResult(
          id: '10a',
          kind: SearchEntityKind.intersection,
          title: 'Avenida 8 de Octubre y José Batlle y Ordóñez (Propios)',
          subtitle: 'Unión',
          latitude: -34.881,
          longitude: -56.143,
          precision: GeoPrecision.intersectionPoint,
          source: SearchDataSource.ideUruguay,
        ),
      ],
    ),

    // 11-15: Códigos de parada STM
    EvaluationTestCase(
      query: '3004',
      expectedIntent: QueryIntentKind.stopCode,
      expectedPrimaryMatch: '3004',
      targetLatitude: -34.905,
      targetLongitude: -56.191,
      candidatePool: const [
        SearchResult(
          id: '11a',
          kind: SearchEntityKind.stop,
          title: 'Av. 18 de Julio y Ejido',
          subtitle: 'Parada STM',
          latitude: -34.905,
          longitude: -56.191,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '3004',
        ),
      ],
    ),
    EvaluationTestCase(
      query: '4218',
      expectedIntent: QueryIntentKind.stopCode,
      expectedPrimaryMatch: '4218',
      targetLatitude: -34.89,
      targetLongitude: -56.16,
      candidatePool: const [
        SearchResult(
          id: '12a',
          kind: SearchEntityKind.stop,
          title: 'Terminal Tres Cruces',
          subtitle: 'Parada STM',
          latitude: -34.89,
          longitude: -56.16,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '4218',
        ),
      ],
    ),
    EvaluationTestCase(
      query: '2112',
      expectedIntent: QueryIntentKind.stopCode,
      expectedPrimaryMatch: '2112',
      targetLatitude: -34.88,
      targetLongitude: -56.15,
      candidatePool: const [
        SearchResult(
          id: '13a',
          kind: SearchEntityKind.stop,
          title: 'Av. Italia y Centenario',
          subtitle: 'Parada STM',
          latitude: -34.88,
          longitude: -56.15,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '2112',
        ),
      ],
    ),
    EvaluationTestCase(
      query: '1001',
      expectedIntent: QueryIntentKind.stopCode,
      expectedPrimaryMatch: '1001',
      targetLatitude: -34.90,
      targetLongitude: -56.20,
      candidatePool: const [
        SearchResult(
          id: '14a',
          kind: SearchEntityKind.stop,
          title: 'Plaza Independencia',
          subtitle: 'Parada STM',
          latitude: -34.90,
          longitude: -56.20,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '1001',
        ),
      ],
    ),
    EvaluationTestCase(
      query: '5566',
      expectedIntent: QueryIntentKind.stopCode,
      expectedPrimaryMatch: '5566',
      targetLatitude: -34.85,
      targetLongitude: -56.17,
      candidatePool: const [
        SearchResult(
          id: '15a',
          kind: SearchEntityKind.stop,
          title: 'Nuevocentro',
          subtitle: 'Parada STM',
          latitude: -34.85,
          longitude: -56.17,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          stopCode: '5566',
        ),
      ],
    ),

    // 16-20: Paradas STM por denominación
    EvaluationTestCase(
      query: 'Tres Cruces',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Tres Cruces',
      targetLatitude: -34.894,
      targetLongitude: -56.164,
      candidatePool: const [
        SearchResult(
          id: '16a',
          kind: SearchEntityKind.stop,
          title: 'Tres Cruces',
          subtitle: 'Terminal',
          latitude: -34.894,
          longitude: -56.164,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
          lines: ['522', '104', 'D10'],
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Plaza Independencia',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Plaza Independencia',
      targetLatitude: -34.906,
      targetLongitude: -56.199,
      candidatePool: const [
        SearchResult(
          id: '17a',
          kind: SearchEntityKind.stop,
          title: 'Plaza Independencia',
          subtitle: 'Ciudad Vieja',
          latitude: -34.906,
          longitude: -56.199,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Plaza Cagancha',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Plaza Cagancha',
      targetLatitude: -34.905,
      targetLongitude: -56.191,
      candidatePool: const [
        SearchResult(
          id: '18a',
          kind: SearchEntityKind.stop,
          title: 'Plaza Cagancha',
          subtitle: 'Centro',
          latitude: -34.905,
          longitude: -56.191,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Portones Shopping',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Portones',
      targetLatitude: -34.881,
      targetLongitude: -56.083,
      candidatePool: const [
        SearchResult(
          id: '19a',
          kind: SearchEntityKind.stop,
          title: 'Terminal Portones Shopping',
          subtitle: 'Carrasco',
          latitude: -34.881,
          longitude: -56.083,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Punta Carretas Shopping',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Punta Carretas',
      targetLatitude: -34.923,
      targetLongitude: -56.158,
      candidatePool: const [
        SearchResult(
          id: '20a',
          kind: SearchEntityKind.stop,
          title: 'Punta Carretas Shopping',
          subtitle: 'Ellauri y Solano García',
          latitude: -34.923,
          longitude: -56.158,
          precision: GeoPrecision.stopCoordinates,
          source: SearchDataSource.stmGtfsLocal,
        ),
      ],
    ),

    // 21-25: Puntos de Interés (POIs) y edificios públicos
    EvaluationTestCase(
      query: 'Hospital de Clínicas',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Hospital de Clínicas',
      targetLatitude: -34.891,
      targetLongitude: -56.151,
      candidatePool: const [
        SearchResult(
          id: '21a',
          kind: SearchEntityKind.poi,
          title: 'Hospital de Clínicas Dr. Manuel Quintela',
          subtitle: 'Avenida Italia',
          latitude: -34.891,
          longitude: -56.151,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Facultad de Ingeniería',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Facultad de Ingeniería',
      targetLatitude: -34.918,
      targetLongitude: -56.166,
      candidatePool: const [
        SearchResult(
          id: '22a',
          kind: SearchEntityKind.poi,
          title: 'Facultad de Ingeniería (Udelar)',
          subtitle: 'Parque Rodó',
          latitude: -34.918,
          longitude: -56.166,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Palacio Legislativo',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Palacio Legislativo',
      targetLatitude: -34.891,
      targetLongitude: -56.187,
      candidatePool: const [
        SearchResult(
          id: '23a',
          kind: SearchEntityKind.poi,
          title: 'Palacio Legislativo',
          subtitle: 'Aguada',
          latitude: -34.891,
          longitude: -56.187,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Estadio Centenario',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Estadio Centenario',
      targetLatitude: -34.894,
      targetLongitude: -56.153,
      candidatePool: const [
        SearchResult(
          id: '24a',
          kind: SearchEntityKind.poi,
          title: 'Estadio Centenario',
          subtitle: 'Parque Batlle',
          latitude: -34.894,
          longitude: -56.153,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Teatro Solís',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Teatro Solís',
      targetLatitude: -34.907,
      targetLongitude: -56.201,
      candidatePool: const [
        SearchResult(
          id: '25a',
          kind: SearchEntityKind.poi,
          title: 'Teatro Solís',
          subtitle: 'Ciudad Vieja',
          latitude: -34.907,
          longitude: -56.201,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),

    // 26-30: Barrios, tolerancia ortográfica y variaciones
    EvaluationTestCase(
      query: 'Pocitos',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Pocitos',
      targetLatitude: -34.915,
      targetLongitude: -56.150,
      candidatePool: const [
        SearchResult(
          id: '26a',
          kind: SearchEntityKind.neighborhood,
          title: 'Pocitos',
          subtitle: 'Barrio de Montevideo',
          latitude: -34.915,
          longitude: -56.150,
          precision: GeoPrecision.approximateArea,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'av italia', // sin tildes ni mayúsculas
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Avenida Italia',
      targetLatitude: -34.88,
      targetLongitude: -56.14,
      candidatePool: const [
        SearchResult(
          id: '27a',
          kind: SearchEntityKind.address,
          title: 'Avenida Italia',
          subtitle: 'Montevideo',
          latitude: -34.88,
          longitude: -56.14,
          precision: GeoPrecision.streetSegment,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'bvr artigas', // abreviatura informal
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Bulevar Artigas',
      targetLatitude: -34.89,
      targetLongitude: -56.16,
      candidatePool: const [
        SearchResult(
          id: '28a',
          kind: SearchEntityKind.address,
          title: 'Bulevar General Artigas',
          subtitle: 'Montevideo',
          latitude: -34.89,
          longitude: -56.16,
          precision: GeoPrecision.streetSegment,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'facultad de ingeneria', // error tipográfico leve
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Facultad de Ingeniería',
      targetLatitude: -34.918,
      targetLongitude: -56.166,
      candidatePool: const [
        SearchResult(
          id: '29a',
          kind: SearchEntityKind.poi,
          title: 'Facultad de Ingeniería',
          subtitle: 'Parque Rodó',
          latitude: -34.918,
          longitude: -56.166,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
    EvaluationTestCase(
      query: 'Cerro',
      expectedIntent: QueryIntentKind.general,
      expectedPrimaryMatch: 'Cerro',
      targetLatitude: -34.88,
      targetLongitude: -56.25,
      candidatePool: const [
        SearchResult(
          id: '30a',
          kind: SearchEntityKind.neighborhood,
          title: 'Villa del Cerro',
          subtitle: 'Montevideo',
          latitude: -34.88,
          longitude: -56.25,
          precision: GeoPrecision.approximateArea,
          source: SearchDataSource.openStreetMap,
        ),
      ],
    ),
  ];

  group('Montevideo Canonical Benchmark (30 Casos de Prueba)', () {
    test(
      'clasificación de intenciones alcanza 100% en casos estructurados',
      () {
        var correctIntents = 0;
        for (final tc in testCases) {
          final parsed = parser.parse(tc.query);
          if (parsed.intent == tc.expectedIntent) {
            correctIntents++;
          }
        }
        final intentAccuracy = (correctIntents / testCases.length) * 100;
        expect(intentAccuracy, 100.0);
      },
    );

    test('Precision@1 alcanza 100% sobre los candidatos de referencia', () {
      var top1Hits = 0;
      for (final tc in testCases) {
        final parsed = parser.parse(tc.query);
        final ranked = engine.rankAndDeduplicate(
          candidates: tc.candidatePool,
          query: parsed,
        );

        if (ranked.isNotEmpty) {
          final topResult = ranked.first;
          final normTop = parser.normalizeText(topResult.title);
          final normExpected = parser.normalizeText(tc.expectedPrimaryMatch);

          var matches = false;
          if (tc.expectedIntent == QueryIntentKind.stopCode) {
            matches = topResult.stopCode == tc.expectedPrimaryMatch;
          } else if (tc.expectedIntent == QueryIntentKind.intersection) {
            final s1 = parsed.street1 ?? '';
            final s2 = parsed.street2 ?? '';
            matches =
                normTop.contains(s1) &&
                (normTop.contains(s2) ||
                    topResult.subtitle.toLowerCase().contains(s2));
          } else {
            final tokens = normExpected.split(' ').where((t) => t.length > 2);
            matches =
                normTop.contains(normExpected) ||
                normExpected.contains(normTop) ||
                (tokens.isNotEmpty && tokens.every((t) => normTop.contains(t)));
          }

          if (matches) {
            top1Hits++;
          }
        }
      }

      final precisionAt1 = (top1Hits / testCases.length) * 100;
      // Requisito técnico: Precision@1 >= 80%
      expect(precisionAt1, greaterThanOrEqualTo(80.0));
      expect(precisionAt1, 100.0);
    });
  });
}
