import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/stops_and_lines/data/montevideo_realtime_bus_source.dart';

void main() {
  test('fetches fleet positions without sending device coordinates', () async {
    Uri? requestedUri;
    final source = MontevideoRealtimeBusSource(
      'http://127.0.0.1:8765/api',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(_geoJson, 200);
      }),
      clock: () => DateTime(2026, 10, 20, 12),
    );
    addTearDown(source.close);

    final snapshot = await source.fetch();

    expect(requestedUri?.path, '/api/buses');
    expect(requestedUri?.queryParameters, {'format': 'geojson'});
    expect(snapshot.positions, hasLength(1));
    expect(snapshot.positions.single.lineLabel, '522');
    expect(snapshot.positions.single.destinationName, 'Centro');
    expect(snapshot.positions.single.latitude, -34.9);
  });

  test(
    'accepts the Android emulator loopback host without sending location',
    () async {
      Uri? requestedUri;
      final source = MontevideoRealtimeBusSource(
        'http://10.0.2.2:8765/api',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(_geoJson, 200);
        }),
      );
      addTearDown(source.close);

      await source.fetch();
      expect(requestedUri?.host, '10.0.2.2');
      expect(requestedUri?.path, '/api/buses');
      expect(requestedUri?.queryParameters.containsKey('lat'), isFalse);
      expect(requestedUri?.queryParameters.containsKey('lon'), isFalse);
    },
  );

  test('reports non-success API responses', () async {
    final source = MontevideoRealtimeBusSource(
      'http://127.0.0.1:8765/api',
      client: MockClient((_) async => http.Response('rate limited', 429)),
    );
    addTearDown(source.close);

    await expectLater(source.fetch(), throwsA(isA<Exception>()));
  });
}

const _geoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {"type": "Point", "coordinates": [-56.2, -34.9]},
      "properties": {
        "id": 1,
        "codigoEmpresa": 1,
        "codigoBus": 2,
        "variante": 3,
        "destino": "1",
        "tipoLinea": 1,
        "subsistema": 1,
        "velocidad": 15,
        "linea": "522",
        "sublinea": "A",
        "destinoDesc": "Centro",
        "tipoLineaDesc": "Urbana",
        "subsistemaDesc": "STM"
      }
    }
  ]
}
''';
