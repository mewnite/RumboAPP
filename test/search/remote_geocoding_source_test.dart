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
        expect(results.single.title, 'Faramiñan y Santa Lucía');
        expect(results.single.precision, GeoPrecision.intersectionPoint);
      },
    );

    test(
      'marca el cruce como aproximado si el proveedor devolvió una calle',
      () async {
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

        expect(results.single.kind, SearchEntityKind.intersection);
        expect(results.single.title, 'Av. Italia y Ejido');
        expect(results.single.latitude, closeTo(-34.89, 0.00001));
        expect(results.single.precision, GeoPrecision.approximateIntersection);
        expect(results.single.toTripEndpoint().isApproximate, isTrue);
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
