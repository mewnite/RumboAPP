import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:rumbo/features/trip_planner/data/open_street_map_place_source.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'search resolves a named Montevideo destination through the proxy',
    () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode([
            {
              'name': 'Shopping Nuevo Centro',
              'display_name': 'Shopping Nuevo Centro, Avenida Luis Alberto de Herrera, Montevideo, Uruguay',
              'lat': '-34.8782',
              'lon': '-56.1689',
            },
          ]),
          200,
        );
      });
      final source = OpenStreetMapPlaceSource(
        endpoint: 'http://127.0.0.1:8765/geocode',
        client: client,
      );
      addTearDown(source.close);

      final results = await source.search('Shopping Nuevo Centro');

      expect(requestedUri.queryParameters['q'], 'Shopping Nuevo Centro');
      expect(requestedUri.queryParameters['countrycodes'], 'uy');
      expect(results, hasLength(1));
      expect(results.single.name, 'Shopping Nuevo Centro');
      expect(results.single.latitude, closeTo(-34.8782, 0.00001));
      expect(results.single.longitude, closeTo(-56.1689, 0.00001));
    },
  );
}
