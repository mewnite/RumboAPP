import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/stops_and_lines/data/montevideo_upcoming_bus_source.dart';

void main() {
  test(
    'requests the selected stop and line and parses the captured response',
    () async {
      final fixture = File(
        'test/fixtures/upcomingbuses_stop_3628_line_163_2026-11-22.json',
      ).readAsStringSync();
      late Uri requestedUri;
      final source = MontevideoUpcomingBusSource(
        'https://example.test/api',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(fixture, 200);
        }),
      );
      addTearDown(source.close);

      final arrivals = await source.upcomingForStop(
        stopId: '3628',
        lines: const {'163'},
        amountPerLine: 5,
      );

      expect(requestedUri.path, '/api/busstops/3628/upcomingbuses');
      expect(requestedUri.queryParameters, {
        'lines': '163',
        'amountperline': '5',
      });
      expect(arrivals, hasLength(1));
      expect(arrivals.single.busId, 584);
      expect(arrivals.single.lineVariantId, 4309);
      expect(arrivals.single.etaSeconds, 1575);
      expect(arrivals.single.latitude, -34.871574);
      expect(arrivals.single.longitude, -56.233017);
    },
  );

  test(
    'matches the captured arrival to the same live-bus identity and position',
    () async {
      final arrival = jsonDecode(
        File('test/fixtures/upcomingbuses_stop_3628_line_163_2026-11-22.json')
            .readAsStringSync(),
      ) as List<dynamic>;
      final geoJson = jsonDecode(
        File('test/fixtures/live_bus_584_linevariant_4309_2026-11-22.geojson')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final upcoming = arrival.single as Map<String, dynamic>;
      final feature =
          (geoJson['features'] as List<dynamic>).single as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>;
      final busCoordinates =
          (feature['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      final officialCoordinates =
          (upcoming['location'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      final meanLatitude =
          ((busCoordinates[1] as num) + (officialCoordinates[1] as num)) /
          2 *
          math.pi /
          180;
      final deltaX =
          ((busCoordinates[0] as num) - (officialCoordinates[0] as num)) *
          111320 *
          math.cos(meanLatitude);
      final deltaY =
          ((busCoordinates[1] as num) - (officialCoordinates[1] as num)) *
          111133;

      expect(properties['busId'], upcoming['busId']);
      expect(properties['lineVariantId'], upcoming['lineVariantId']);
      expect(properties['line'], upcoming['line']);
      expect(properties['speed'], 43);
      expect(math.sqrt(deltaX * deltaX + deltaY * deltaY), lessThan(500));
      expect(upcoming['eta'], 1575);
      expect(upcoming['distance'], 8714);
      expect(upcoming['position'], 26);
    },
  );

  test(
    'accepts an empty official response for fallback to the next source',
    () async {
      final source = MontevideoUpcomingBusSource(
        'https://example.test/api',
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      addTearDown(source.close);

      expect(
        await source.upcomingForStop(stopId: '1', lines: const {'522'}),
        isEmpty,
      );
    },
  );

  test(
    'surfaces HTTP failures instead of treating them as empty arrivals',
    () async {
      final source = MontevideoUpcomingBusSource(
        'https://example.test/api',
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      addTearDown(source.close);

      await expectLater(
        source.upcomingForStop(stopId: '1', lines: const {'522'}),
        throwsA(isA<HttpException>()),
      );
    },
  );

  test('times out a stalled official request', () async {
    final pending = Completer<http.Response>();
    final source = MontevideoUpcomingBusSource(
      'https://example.test/api',
      client: MockClient((_) => pending.future),
      requestTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(source.close);

    await expectLater(
      source.upcomingForStop(stopId: '1', lines: const {'522'}),
      throwsA(isA<TimeoutException>()),
    );
  });
}
