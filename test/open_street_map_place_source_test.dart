import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/trip_planner/data/open_street_map_place_source.dart';

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

      expect(requestedUri.queryParameters, {'q': 'Shopping Nuevo Centro'});
      expect(results, hasLength(1));
      expect(results.single.name, 'Shopping Nuevo Centro');
      expect(results.single.latitude, closeTo(-34.8782, 0.00001));
      expect(results.single.longitude, closeTo(-56.1689, 0.00001));
    },
  );

  test(
    'keeps any typed door number when the provider returns only a road',
    () async {
      const query = 'Avenida Italia 2450';
      final client = MockClient((request) async {
        expect(request.url.queryParameters['q'], query);
        return http.Response(
          jsonEncode([
            {
              'name': 'Avenida Italia',
              'display_name': 'Avenida Italia, Montevideo, Uruguay',
              'address': {'road': 'Avenida Italia'},
              'type': 'residential',
              'lat': '-34.8900',
              'lon': '-56.1800',
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

      final results = await source.search(query);

      expect(results, hasLength(1));
      expect(results.single.name, query);
      expect(results.single.isApproximate, isTrue);
    },
  );

  test(
    'marks a numbered address exact only when its requested number matches',
    () async {
      const query = 'Av. Italia 2450';
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'name': 'Avenida Italia',
              'display_name': 'Avenida Italia, 2450, Montevideo, Uruguay',
              'address': {'road': 'Avenida Italia', 'house_number': '2450'},
              'type': 'house',
              'lat': '-34.8901',
              'lon': '-56.1801',
            },
            {
              'name': 'Avenida Italia',
              'address': {'road': 'Avenida Italia', 'house_number': '2452'},
              'type': 'house',
              'lat': '-34.8902',
              'lon': '-56.1802',
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

      final results = await source.search(query);

      expect(results, hasLength(1));
      expect(results.single.name, 'Avenida Italia 2450');
      expect(results.single.isApproximate, isFalse);
    },
  );

  test('resolves street intersections only when both streets match', () async {
    const query = '18 de Julio esquina Ejido';
    final client = MockClient((request) async {
      expect(request.url.queryParameters['q'], query);
      return http.Response(
        jsonEncode([
          {
            'name': '18 de Julio & Ejido',
            'display_name': '18 de Julio & Ejido, Montevideo, Uruguay',
            'type': 'junction',
            'lat': '-34.9050',
            'lon': '-56.1900',
          },
          {
            'name': '18 de Julio',
            'display_name': '18 de Julio, Montevideo, Uruguay',
            'type': 'residential',
            'lat': '-34.9051',
            'lon': '-56.1901',
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

    final results = await source.search(query);

    expect(results, hasLength(1));
    expect(results.single.name, '18 de Julio & Ejido');
    expect(results.single.isApproximate, isFalse);
  });

  test('does not return an unverified street as an intersection', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {
            'display_name': 'Avenida Italia & Ejido, Montevideo, Uruguay',
            'type': 'residential',
            'lat': '-34.9050',
            'lon': '-56.1900',
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

    final results = await source.search('Av. Italia x Ejido');

    expect(results, isEmpty);
  });
}
