import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/trip_planner/data/open_street_map_place_source.dart';

void main() {
  test(
    'searches places only through the configured endpoint and caches results',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.host, 'example.test');
        expect(request.url.queryParameters['q'], 'Nuevo Centro Shopping');
        expect(request.url.queryParameters['countrycodes'], 'uy');
        expect(request.url.queryParameters['format'], 'jsonv2');
        expect(request.headers['user-agent'], contains('RumboAPP'));
        return http.Response(
          '[{"display_name":"Nuevo Centro Shopping, Montevideo","lat":"-34.85","lon":"-56.17"},'
          '{"display_name":"Fuera de Uruguay","lat":"-32.0","lon":"-60.0"}]',
          200,
        );
      });
      final source = OpenStreetMapPlaceSource(
        endpoint: 'https://example.test/geocode',
        client: client,
      );
      addTearDown(source.close);

      final first = await source.search('Nuevo Centro Shopping');
      final second = await source.search('nuevo centro shopping');

      expect(first, hasLength(1));
      expect(first.single.name, 'Nuevo Centro Shopping, Montevideo');
      expect(first.single.latitude, -34.85);
      expect(first.single.longitude, -56.17);
      expect(second, first);
      expect(requests, 1);
    },
  );

  test('rejects insecure non-local endpoints and short queries', () async {
    final source = OpenStreetMapPlaceSource(
      endpoint: 'http://example.test/geocode',
    );
    addTearDown(source.close);

    await expectLater(source.search('Montevideo'), throwsFormatException);

    final secureSource = OpenStreetMapPlaceSource(
      endpoint: 'https://example.test/geocode',
    );
    addTearDown(secureSource.close);
    await expectLater(secureSource.search('UY'), throwsArgumentError);
  });
}
