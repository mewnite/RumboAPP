import 'dart:async';

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
          expect(request.url.queryParameters['q'], 'avenida italia 2450');
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
