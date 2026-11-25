import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/search/data/remote_geocoding_source.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';
import 'package:rumbo/features/search/domain/search_models.dart';

class _AbortableTestClient extends http.BaseClient {
  _AbortableTestClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {}
}

void main() {
  const parser = MontevideoQueryParser();

  group('RemoteGeocodingSource', () {
    test(
      'consulta endpoint configurado, parsea formato enriquecido y cachea',
      () async {
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          expect(request.url.host, 'example.test');
          expect(request.url.queryParameters['q'], 'Av. Italia 2450');
          expect(request.url.queryParameters, isNot(contains('bias_lat')));
          expect(request.url.queryParameters, isNot(contains('bias_lon')));
          return http.Response(
            '['
            '  {'
            '    "id": "ide:8110:2451",'
            '    "kind": "address",'
            '    "title": "Av. Italia 2450",'
            '    "subtitle": "La Blanqueada, Montevideo",'
            '    "lat": -34.8887,'
            '    "lon": -56.1492,'
            '    "precision": "exactDoorNumber",'
            '    "source": "ideUruguay"'
            '  },'
            '  {'
            '    "id": "out-of-bounds",'
            '    "kind": "address",'
            '    "title": "Fuera de Uruguay",'
            '    "lat": -20.0,'
            '    "lon": -60.0'
            '  }'
            ']',
            200,
          );
        });

        final source = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: client,
        );
        addTearDown(source.close);

        final query = parser.parse('Av. Italia 2450');
        final first = await source.searchRemote(query);
        final second = await source.searchRemote(query);

        expect(first, hasLength(1));
        expect(first.single.title, 'Av. Italia 2450');
        expect(first.single.precision, GeoPrecision.exactDoorNumber);
        expect(first.single.source, SearchDataSource.ideUruguay);
        expect(second, first);
        expect(requests, 1); // La segunda vino de caché
      },
    );

    test('acepta una respuesta vacía como resultado vacío', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      addTearDown(source.close);

      expect(await source.searchRemote(parser.parse('Faramiñán 801')), isEmpty);
    });

    test('propaga HTTP 429 del geocodificador', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );
      addTearDown(source.close);

      await expectLater(
        source.searchRemote(parser.parse('Shopping Nuevo Centro')),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 429'),
          ),
        ),
      );
    });

    test('aborta y propaga timeout del geocodificador', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('[]', 200);
        }),
      );
      addTearDown(source.close);

      await expectLater(
        source.searchRemote(parser.parse('Shopping Nuevo Centro')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('soporta formato heredado de OpenStreetMap / Nominatim', () async {
      final client = MockClient((request) async {
        return http.Response(
          '['
          '  {'
          '    "display_name": "Nuevo Centro Shopping, Avenida Luis Alberto de Herrera, Montevideo, Uruguay",'
          '    "lat": "-34.85",'
          '    "lon": "-56.17",'
          '    "type": "mall"'
          '  }'
          ']',
          200,
        );
      });

      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(parser.parse('Nuevo Centro'));
      expect(results, hasLength(1));
      expect(results.first.title, 'Nuevo Centro Shopping');
      expect(results.first.kind, SearchEntityKind.poi);
      expect(results.first.source, SearchDataSource.openStreetMap);
    });

    test('clasifica las dos variantes de neighborhood como barrio', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: MockClient(
          (_) async => http.Response(
            '['
            '{"name":"Parque Rodó","display_name":"Parque Rodó, Montevideo, Uruguay",'
            '"category":"boundary","type":"neighborhood","osm_type":"relation",'
            '"osm_id":13353266,"lat":"-34.9141426","lon":"-56.1676888"},'
            '{"name":"Parque Rodó","display_name":"Parque Rodó, Montevideo, Uruguay",'
            '"category":"boundary","type":"neighbourhood","osm_type":"relation",'
            '"osm_id":13353267,"lat":"-34.9141426","lon":"-56.1676888"}'
            ']',
            200,
          ),
        ),
      );
      addTearDown(source.close);

      final results = await source.searchRemote(parser.parse('Parque Rodo'));

      expect(results, hasLength(2));
      expect(
        results.map((result) => result.kind),
        everyElement(SearchEntityKind.neighborhood),
      );
    });

    test(
      'ignora un cajero nombrado como el destino salvo que se busque un cajero',
      () async {
        const response =
            '['
            '{"name":"Terminal Tres Cruces","display_name":"Terminal Tres Cruces, Goes, Montevideo, Uruguay",'
            '"category":"amenity","type":"bus_station","osm_type":"way","osm_id":1,'
            '"lat":"-34.8938334","lon":"-56.1665762"},'
            '{"name":"Terminal Tres Cruces","display_name":"Terminal Tres Cruces, 1825, Bulevar General Artigas, Montevideo, Uruguay",'
            '"category":"amenity","type":"atm","osm_type":"node","osm_id":2,'
            '"lat":"-34.8939371","lon":"-56.1664894"}'
            ']';

        final terminalSource = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: MockClient((_) async => http.Response(response, 200)),
        );
        addTearDown(terminalSource.close);

        final terminalResults = await terminalSource.searchRemote(
          parser.parse('Terminal Tres Cruces'),
        );
        expect(terminalResults, hasLength(1));
        expect(terminalResults.single.title, 'Terminal Tres Cruces');
        expect(terminalResults.single.category, 'amenity:bus_station');

        final atmSource = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: MockClient(
            (_) async => http.Response(
              '[{"name":"Cajero","display_name":"Cajero, Montevideo, Uruguay",'
              '"category":"amenity","type":"atm","osm_type":"node","osm_id":3,'
              '"lat":"-34.8939371","lon":"-56.1664894"}]',
              200,
            ),
          ),
        );
        addTearDown(atmSource.close);

        final atmResults = await atmSource.searchRemote(parser.parse('Cajero'));
        expect(atmResults, hasLength(1));
        expect(atmResults.single.category, 'amenity:atm');
      },
    );

    test('normalizes structured neighborhood categories from Photon', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: MockClient(
          (_) async => http.Response(
            '['
            '{"id":"osm:relation:1","kind":"poi","title":"Parque Rodó",'
            '"category":"boundary:neighborhood","lat":-34.9141,"lon":-56.1677,'
            '"precision":"rooftopPoi","source":"openStreetMap"},'
            '{"id":"osm:way:2","kind":"poi","title":"Parque Rodó",'
            '"category":"leisure:park","lat":-34.9155,"lon":-56.1675,'
            '"precision":"rooftopPoi","source":"openStreetMap"},'
            '{"id":"osm:node:3","kind":"neighborhood","title":"Parque Rodó",'
            '"category":"place:suburb","lat":-34.9100,"lon":-56.1697,'
            '"precision":"streetSegment","source":"openStreetMap"}'
            ']',
            200,
          ),
        ),
      );
      addTearDown(source.close);

      final results = await source.searchRemote(parser.parse('Parque Rodo'));
      final boundary = results.singleWhere(
        (result) => result.category == 'boundary:neighborhood',
      );
      final suburb = results.singleWhere(
        (result) => result.category == 'place:suburb',
      );

      expect(boundary.kind, SearchEntityKind.neighborhood);
      expect(boundary.precision, GeoPrecision.approximateArea);
      expect(suburb.kind, SearchEntityKind.neighborhood);
      expect(suburb.precision, GeoPrecision.approximateArea);
    });

    test(
      'filters service POIs unless the query asks for that service',
      () async {
        final source = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: MockClient((request) async {
            final response = request.url.queryParameters['q'] == 'Teatro Solis'
                ? '['
                      '{"id":"bike","kind":"poi","title":"Teatro Solís",'
                      '"category":"amenity:bicycle_rental","lat":-34.9081,'
                      '"lon":-56.2000,"precision":"rooftopPoi"},'
                      '{"id":"theatre","kind":"poi","title":"Teatro Solís",'
                      '"category":"amenity:theatre","lat":-34.9078,'
                      '"lon":-56.2010,"precision":"rooftopPoi"}'
                      ']'
                : '['
                      '{"id":"parking","kind":"poi","title":"Punta Carretas Shopping",'
                      '"category":"amenity:parking","lat":-34.9233,'
                      '"lon":-56.1588,"precision":"rooftopPoi"},'
                      '{"id":"mall","kind":"poi","title":"Punta Carretas Shopping",'
                      '"category":"shop:mall","lat":-34.9239,'
                      '"lon":-56.1585,"precision":"rooftopPoi"}'
                      ']';
            return http.Response(response, 200);
          }),
        );
        addTearDown(source.close);

        final theatre = await source.searchRemote(parser.parse('Teatro Solis'));
        final shopping = await source.searchRemote(
          parser.parse('Shopping Punta Carretas'),
        );

        expect(theatre, hasLength(1));
        expect(theatre.single.category, 'amenity:theatre');
        expect(shopping, hasLength(1));
        expect(shopping.single.category, 'shop:mall');
      },
    );

    test('mantiene calle y número juntos en una dirección exacta', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'faramiñán 801');
        return http.Response(
          '[{"display_name":"Calle Faramiñán, 801, Montevideo, Uruguay",'
          '"address":{"road":"Calle Faramiñán","house_number":"801"},'
          '"lat":"-34.88","lon":"-56.18","type":"house"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(parser.parse('faramiñán 801'));

      expect(results, hasLength(1));
      expect(results.single.title, 'Calle Faramiñán 801');
      expect(results.single.precision, GeoPrecision.exactDoorNumber);
      expect(results.single.subtitle, contains('Montevideo'));
    });

    test('marca como aproximada una dirección sin house_number', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'faramiñán 801');
        return http.Response(
          '[{"display_name":"Faramiñán, Nuevo París, Montevideo, Uruguay",'
          '"address":{"road":"Faramiñán","suburb":"Nuevo París"},'
          '"lat":"-34.8412159","lon":"-56.2374153","type":"residential"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final result = (await source.searchRemote(parser.parse('faramiñán 801')))
          .single;

      expect(result.title, 'faramiñán 801');
      expect(result.precision, GeoPrecision.unconfirmedDoorNumber);
      expect(result.toTripEndpoint().isApproximate, isTrue);
    });

    test(
      'envía las dos calles de una intersección al geocodificador',
      () async {
        final client = MockClient((request) async {
          expect(request.url.queryParameters['q'], 'Faramiñan y Santa Lucía');
          return http.Response(
            '[{"display_name":"Faramiñan & Santa Lucía, Montevideo",'
            '"lat":"-34.86","lon":"-56.25","type":"junction"}]',
            200,
          );
        });
        final source = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: client,
        );
        addTearDown(source.close);

        final results = await source.searchRemote(
          parser.parse('Faramiñan y Santa Lucía'),
        );
        expect(results.single.kind, SearchEntityKind.intersection);
        expect(results.single.title, 'Faramiñan & Santa Lucía');
        expect(results.single.precision, GeoPrecision.intersectionPoint);
      },
    );

    test('descarta el cruce si el proveedor devolvió una calle', () async {
      final client = MockClient((request) async {
        return http.Response(
          '[{"display_name":"Av. Italia, Montevideo, Uruguay",'
          '"lat":"-34.88","lon":"-56.18","type":"residential"},'
          '{"display_name":"Avenida Italia & Ejido, Montevideo, Uruguay",'
          '"lat":"-34.89","lon":"-56.19","type":"residential"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(
        parser.parse('Av. Italia y Ejido'),
      );

      expect(results, isEmpty);
    });

    test('no confirma un cruce por repetir las calles solo en el título normalizado', () async {
      final client = MockClient((request) async {
        return http.Response(
          '[{"id":"intersection","kind":"intersection",'
          '"title":"Rivera esquina Soca","name":"Avenida Rivera",'
          '"street":"Avenida Rivera","subtitle":"Montevideo",'
          '"lat":-34.88,"lon":-56.18,'
          '"precision":"intersectionPoint","source":"openStreetMap"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(
        parser.parse('Rivera esquina Soca'),
      );
      expect(results, isEmpty);
    });

    test(
      'conserva nombre oficial, alias y dirección de un POI Photon',
      () async {
        final source = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: MockClient((_) async {
            return http.Response(
              '[{"id":"osm:relation:9001",'
              '"externalId":"osm:relation:9001","kind":"poi",'
              '"title":"Auditorio Nacional Adela Reta",'
              '"name":"Auditorio Nacional Adela Reta",'
              '"officialName":"Auditorio Nacional Adela Reta",'
              '"aliases":["SODRE"],"category":"amenity:theatre",'
              '"street":"Andes","subtitle":"Andes · Montevideo",'
              '"address":{"street":"Andes","city":"Montevideo"},'
              '"lat":-34.9037,"lon":-56.1882,'
              '"precision":"rooftopPoi","source":"openStreetMap"}]',
              200,
            );
          }),
        );
        addTearDown(source.close);

        final result = (await source.searchRemote(parser.parse('SODRE')))
            .single;

        expect(result.title, 'Auditorio Nacional Adela Reta');
        expect(result.aliases, contains('SODRE'));
        expect(result.category, 'amenity:theatre');
        expect(result.externalId, 'osm:relation:9001');
        expect(result.subtitle, 'Andes · Montevideo');
        expect(result.toTripEndpoint().category, 'poi');
        expect(result.toTripEndpoint().subtitle, 'Andes · Montevideo');
        expect(result.toTripEndpoint().precision, 'rooftopPoi');
      },
    );

    test(
      'descarta una intersección candidata que solo coincide con una calle',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '[{"display_name":"Avenida Italia, Montevideo, Uruguay",'
            '"lat":"-34.88","lon":"-56.18","type":"junction"}]',
            200,
          );
        });
        final source = RemoteGeocodingSource(
          endpoint: 'https://example.test/geocode',
          client: client,
        );
        addTearDown(source.close);

        final results = await source.searchRemote(
          parser.parse('Av. Italia esquina Ejido'),
        );

        expect(results, isEmpty);
      },
    );

    test('no considera que un nombre parcial sea la segunda calle', () async {
      final client = MockClient((request) async {
        return http.Response(
          '[{"display_name":"Soca, Montevideo, Uruguay",'
          '"lat":"-34.88","lon":"-56.18","type":"junction"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(
        parser.parse('Soca esquina Oca'),
      );

      expect(results, isEmpty);
    });

    test('no afirma un número que el proveedor no confirmó', () async {
      final client = MockClient((request) async {
        return http.Response(
          '[{"display_name":"Calle Faramiñán, Montevideo, Uruguay",'
          '"address":{"road":"Calle Faramiñán"},'
          '"lat":"-34.88","lon":"-56.18","type":"residential"}]',
          200,
        );
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.searchRemote(parser.parse('Faramiñán 801'));

      expect(results.single.title, 'Faramiñán 801');
      expect(results.single.precision, GeoPrecision.unconfirmedDoorNumber);
      expect(results.single.toTripEndpoint().isApproximate, isTrue);
    });

    test('rechaza endpoints http no locales', () async {
      final source = RemoteGeocodingSource(
        endpoint: 'http://insecure.test/geocode',
      );
      addTearDown(source.close);

      await expectLater(
        source.searchRemote(parser.parse('Montevideo')),
        throwsFormatException,
      );
    });

    test('aborta la petición cuando cambia la consulta', () async {
      final abortTrigger = Completer<void>();
      final requestStarted = Completer<void>();
      final client = _AbortableTestClient((request) async {
        requestStarted.complete();
        expect(request, isA<http.AbortableRequest>());
        final abortable = request as http.AbortableRequest;
        await abortable.abortTrigger;
        throw http.RequestAbortedException(request.url);
      });
      final source = RemoteGeocodingSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final pending = source.searchRemote(
        parser.parse('pocit'),
        abortTrigger: abortTrigger.future,
      );
      await requestStarted.future;
      abortTrigger.complete();

      await expectLater(pending, throwsA(isA<http.RequestAbortedException>()));
    });
  });
}
