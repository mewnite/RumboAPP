import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_realtime_bus_source.dart';
import 'package:rumbo/features/stops_and_lines/data/gtfs_csv.dart';
import 'package:rumbo/features/stops_and_lines/data/gtfs_parser.dart';
import 'package:rumbo/features/stops_and_lines/data/stm_online_geojson_parser.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_arrivals_source.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_feed_source.dart';
import 'package:rumbo/features/stops_and_lines/data/sqflite_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ThrowingRealtimeBusSource implements RealtimeBusSource {
  @override
  Future<RealtimeSnapshot> fetch() async {
    throw const FormatException('offline');
  }
}

void main() {
  test('CSV supports BOM, quoted commas, CRLF and reordered columns', () {
    final csv = CsvTable.parse(
      utf8.decode(File('test/fixtures/gtfs_bom.csv').readAsBytesSync()),
    );
    expect(csv.records.single['stop_id'], 'S1');
    expect(csv.records.single['stop_name'], 'Plaza, Centro');
  });

  test(
    'streaming CSV file reader keeps quotes and UTF-8 across chunks',
    () async {
      final directory = await Directory.systemTemp.createTemp('rumbo-csv-');
      final file = File('${directory.path}${Platform.pathSeparator}rows.csv');
      final largeName = '${'x' * 65511}🚌';
      await file.writeAsString(
        '\uFEFFstop_name,stop_id\r\n"$largeName, ""Centro""",S1\r\n',
      );
      final table = CsvTable.fromFile(file);

      expect(table.records.single, {
        'stop_name': '$largeName, "Centro"',
        'stop_id': 'S1',
      });
      expect(table.invalidRowCount, 0);
      await directory.delete(recursive: true);
    },
  );

  test('CSV skips malformed rows and reports their count', () {
    final table = CsvTable.fromFile(
      File('test/fixtures/gtfs_invalid_rows.csv'),
    );
    expect(table.records.toList(), [
      {
        'stop_id': 'S1',
        'stop_name': 'Correcta',
        'stop_lat': '-34.9',
        'stop_lon': '-56.1',
      },
    ]);
    expect(table.invalidRowCount, 1);
  });

  test('GTFS times retain values beyond 24 hours', () {
    expect(parseGtfsTime('25:10:05'), 25 * 3600 + 10 * 60 + 5);
    expect(parseGtfsTime('24:61:00'), isNull);
  });

  test('conditional requests retain ETag and Last-Modified and handle 304', () {
    expect(conditionalFeedHeaders(etag: 'opaque-etag', lastModified: 'date'), {
      'If-None-Match': 'opaque-etag',
      'If-Modified-Since': 'date',
    });
    expect(isFeedNotModified(304), isTrue);
    expect(isFeedNotModified(200), isFalse);
  });

  test(
    'feed source allows the Android emulator local proxy over HTTP',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, '10.0.2.2');
        expect(request.url.path, '/gtfs/latest');
        return http.Response.bytes(const [1, 2, 3], 200);
      });
      final source = GtfsZipSource(
        'http://10.0.2.2:8765/gtfs/latest',
        client: client,
      );

      final download = await source.download();

      expect(download.bytes, const [1, 2, 3]);
    },
  );

  test('feed source rejects plain HTTP outside local development hosts', () {
    final source = GtfsZipSource('http://example.test/gtfs/latest');

    expect(source.download(), throwsFormatException);
  });

  test('feed expiry and offline errors preserve explicit states', () {
    expect(isFeedExpired(DateTime(2026, 1, 1), DateTime(2026, 1, 2)), isTrue);
    expect(isFeedExpired(DateTime(2026, 1, 3), DateTime(2026, 1, 2)), isFalse);
    expect(
      phaseForFeedError(const TransitFeedNetworkException('offline')),
      FeedUpdatePhase.offline,
    );
    expect(
      phaseForFeedError(const FormatException('invalid feed')),
      FeedUpdatePhase.errorWithOldData,
    );
  });

  test(
    'cached official GTFS metadata is available without an in-memory feed',
    () {
      final cached = FeedUpdateState(
        phase: FeedUpdatePhase.updated,
        status: const FeedStatus(stopCount: 4930, routeCount: 325),
      );
      expect(cached.feed, isNull);
      expect(hasOfficialTransitData(cached), isTrue);
      expect(
        hasOfficialTransitData(
          const FeedUpdateState(
            phase: FeedUpdatePhase.updated,
            status: FeedStatus(synthetic: true, stopCount: 18, routeCount: 3),
          ),
        ),
        isFalse,
      );
      expect(
        hasOfficialTransitData(
          const FeedUpdateState(
            phase: FeedUpdatePhase.updated,
            status: FeedStatus(stopCount: 0, routeCount: 3),
          ),
        ),
        isFalse,
      );
    },
  );

  test('trip data waits for an initial GTFS download and import', () async {
    final completion = Completer<FeedUpdateState>();
    final pending = waitForOfficialTransitData(
      const FeedUpdateState(
        phase: FeedUpdatePhase.processing,
        stage: 'procesando_archivos',
      ),
      () => completion.future,
    );
    var finished = false;
    unawaited(
      pending.then<void>((_) {
        finished = true;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);

    completion.complete(
      const FeedUpdateState(
        phase: FeedUpdatePhase.updated,
        status: FeedStatus(stopCount: 4930, routeCount: 325),
      ),
    );
    final result = await pending;

    expect(hasOfficialTransitData(result), isTrue);
  });

  test(
    'initial GTFS failure preserves its diagnostic for the planner',
    () async {
      final result = await waitForOfficialTransitData(
        const FeedUpdateState(
          phase: FeedUpdatePhase.downloading,
          stage: 'conectando',
        ),
        () async => const FeedUpdateState(
          phase: FeedUpdatePhase.offline,
          message: 'El proxy rechazó la descarga del feed.',
        ),
      );

      expect(result?.phase, FeedUpdatePhase.offline);
      expect(result?.message, 'El proxy rechazó la descarga del feed.');
      expect(hasOfficialTransitData(result), isFalse);
    },
  );

  test('missing or synthetic official feed retries despite a recent check', () {
    final now = DateTime(2026, 10, 24, 12);
    final recentCheck = now
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    expect(
      isTransitUpdateDue(
        currentStatus: const FeedStatus(synthetic: true, stopCount: 18),
        lastCheckMilliseconds: recentCheck,
        now: now,
        minimumInterval: const Duration(hours: 24),
      ),
      isTrue,
    );
    expect(
      isTransitUpdateDue(
        currentStatus: const FeedStatus(synthetic: false, stopCount: 4930),
        lastCheckMilliseconds: recentCheck,
        now: now,
        minimumInterval: const Duration(hours: 24),
      ),
      isFalse,
    );
  });

  test('calendar weekdays and date exceptions follow GTFS rules', () {
    final calendar = ServiceCalendar(
      serviceId: 'wk',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      weekdays: {1, 2, 3, 4, 5},
      addedDates: {DateTime(2026, 1, 3)},
      removedDates: {DateTime(2026, 1, 2)},
    );
    expect(calendar.activeOn(DateTime(2026, 1, 1)), isTrue);
    expect(calendar.activeOn(DateTime(2026, 1, 2)), isFalse);
    expect(calendar.activeOn(DateTime(2026, 1, 3)), isTrue);
    expect(calendar.activeOn(DateTime(2026, 1, 4)), isFalse);
  });

  test('nearby stops sorts by distance and respects radius', () async {
    final repo = FakeTransitRepository(
      stops: [
        const Stop(id: 'far', name: 'Far', latitude: 0, longitude: .02),
        const Stop(id: 'near', name: 'Near', latitude: 0, longitude: .001),
      ],
      routes: [],
      variants: [],
      trips: [],
      times: [],
      calendars: [],
    );
    expect((await repo.nearbyStops(0, 0, 300)).map((s) => s.id), ['near']);
    expect((await repo.nearbyStops(0, 0, 3000)).map((s) => s.id), [
      'near',
      'far',
    ]);
  });

  test(
    'upcoming departures includes the previous service day after midnight',
    () async {
      final calendar = ServiceCalendar(
        serviceId: 'daily',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        weekdays: {1},
      );
      const trip = Trip(
        id: 't',
        routeId: 'r',
        serviceId: 'daily',
        variantId: 'v',
      );
      final repo = FakeTransitRepository(
        stops: [],
        routes: [],
        variants: [],
        trips: [trip],
        times: [
          const StopTime(
            tripId: 't',
            stopId: 's',
            arrivalSeconds: 90000,
            departureSeconds: 90000,
            sequence: 1,
          ),
        ],
        calendars: [calendar],
      );
      final result = await repo.upcomingDepartures(
        's',
        DateTime(2026, 6, 2, 0, 5),
      );
      expect(result.single.departure, DateTime(2026, 6, 2, 1));
    },
  );

  test('upcoming departures sorts results and honors its limit', () async {
    final service = ServiceCalendar(
      serviceId: 'daily',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final trips = [
      for (var i = 0; i < 3; i++)
        Trip(id: 't$i', routeId: 'r', serviceId: 'daily', variantId: 'v'),
    ];
    final times = [
      const StopTime(
        tripId: 't0',
        stopId: 's',
        arrivalSeconds: 36000,
        departureSeconds: 36000,
        sequence: 1,
      ),
      const StopTime(
        tripId: 't1',
        stopId: 's',
        arrivalSeconds: 28800,
        departureSeconds: 28800,
        sequence: 1,
      ),
      const StopTime(
        tripId: 't2',
        stopId: 's',
        arrivalSeconds: 39600,
        departureSeconds: 39600,
        sequence: 1,
      ),
    ];
    final repo = FakeTransitRepository(
      stops: [],
      routes: [],
      variants: [],
      trips: trips,
      times: times,
      calendars: [service],
    );
    final departures = await repo.upcomingDepartures(
      's',
      DateTime(2026, 6, 1, 7),
      limit: 2,
    );
    expect(departures.map((departure) => departure.stopTime.departureSeconds), [
      28800,
      36000,
    ]);
  });

  test('projects a live bus along the shape, rejects passed stops, and defaults low speed', () {
    const stop = Stop(id: 's', name: 'Stop', latitude: 0, longitude: .01);
    const shape = Shape(
      id: 'line',
      points: [ShapePoint(0, 0, 1), ShapePoint(0, .02, 2)],
    );
    final slowBus = _testBus(longitude: .005, speedKmh: 0);
    final fastBus = _testBus(longitude: .005, speedKmh: 36);
    final passedBus = _testBus(longitude: .015, speedKmh: 18);

    expect(
      estimateBusArrivalMinutes(position: slowBus, stop: stop, shape: shape),
      2,
    );
    expect(
      estimateBusArrivalMinutes(position: fastBus, stop: stop, shape: shape),
      1,
    );
    expect(
      estimateBusArrivalMinutes(position: passedBus, stop: stop, shape: shape),
      isNull,
    );
  });

  test(
    'replaces one scheduled variant with live ETA and sorts mixed arrivals',
    () async {
      final service = ServiceCalendar(
        serviceId: 'daily',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        weekdays: {1, 2, 3, 4, 5, 6, 7},
      );
      const routeA = Route(id: 'r1', shortName: 'A', longName: 'A destino');
      const routeB = Route(id: 'r2', shortName: 'B', longName: 'B destino');
      const variantA = RouteVariant(
        id: 'v1',
        routeId: 'r1',
        directionId: '0',
        destination: 'A destino',
        shapeId: 'shape-a',
        externalVariantId: 42,
      );
      const variantB = RouteVariant(
        id: 'v2',
        routeId: 'r2',
        directionId: '0',
        destination: 'B destino',
        shapeId: 'shape-b',
        externalVariantId: 43,
      );
      final repository = FakeTransitRepository(
        stops: const [Stop(id: 's', name: 'Stop', latitude: 0, longitude: .01)],
        routes: const [routeA, routeB],
        variants: const [variantA, variantB],
        trips: const [
          Trip(id: 'a1', routeId: 'r1', serviceId: 'daily', variantId: 'v1'),
          Trip(id: 'b1', routeId: 'r2', serviceId: 'daily', variantId: 'v2'),
          Trip(id: 'a2', routeId: 'r1', serviceId: 'daily', variantId: 'v1'),
        ],
        times: const [
          StopTime(
            tripId: 'a1',
            stopId: 's',
            arrivalSeconds: 36000,
            departureSeconds: 36000,
            sequence: 1,
          ),
          StopTime(
            tripId: 'b1',
            stopId: 's',
            arrivalSeconds: 28800,
            departureSeconds: 28800,
            sequence: 1,
          ),
          StopTime(
            tripId: 'a2',
            stopId: 's',
            arrivalSeconds: 39600,
            departureSeconds: 39600,
            sequence: 1,
          ),
        ],
        calendars: [service],
      );
      repository
        ..shapes['shape-a'] = const Shape(
          id: 'shape-a',
          points: [ShapePoint(0, 0, 1), ShapePoint(0, .02, 2)],
        )
        ..shapes['shape-b'] = const Shape(
          id: 'shape-b',
          points: [ShapePoint(.01, 0, 1), ShapePoint(.01, .02, 2)],
        );
      final arrivals = await TransitArrivalsSource(
        repository,
        livePositions: [_testBus(longitude: .005, speedKmh: 18)],
      ).arrivalsForStop('s', DateTime(2026, 6, 1, 7));

      expect(arrivals.map((arrival) => arrival.routeLabel), ['A', 'B', 'A']);
      expect(arrivals.map((arrival) => arrival.isLive), [true, false, false]);
      expect(arrivals.map((arrival) => arrival.departureTime), [
        DateTime(2026, 6, 1, 7, 2),
        DateTime(2026, 6, 1, 8),
        DateTime(2026, 6, 1, 11),
      ]);
    },
  );

  test('arrivals source prefers the live match for the same variant and keeps it labeled live', () async {
    final service = ServiceCalendar(
      serviceId: 'daily',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    const route = Route(id: 'r1', shortName: 'D', longName: 'Diagonal');
    const variant = RouteVariant(
      id: 'r1:0:sh1',
      routeId: 'r1',
      directionId: '0',
      destination: 'Plaza Independencia',
      shapeId: 'sh1',
      externalVariantId: 42,
    );
    final repo = FakeTransitRepository(
      stops: const [
        Stop(id: 's', name: 'Stop', latitude: -34.9, longitude: -56.1),
      ],
      routes: const [route],
      variants: const [variant],
      trips: const [
        Trip(
          id: 't1',
          routeId: 'r1',
          serviceId: 'daily',
          variantId: 'r1:0:sh1',
          headsign: 'Plaza Independencia',
        ),
      ],
      times: const [
        StopTime(
          tripId: 't1',
          stopId: 's',
          arrivalSeconds: 36000,
          departureSeconds: 36000,
          sequence: 1,
        ),
      ],
      calendars: [service],
    );
    repo.shapes['sh1'] = const Shape(
      id: 'sh1',
      points: [
        ShapePoint(-34.905, -56.105, 1),
        ShapePoint(-34.895, -56.095, 2),
      ],
    );
    final snapshot = RealtimeSnapshot(
      positions: [
        BusPosition(
          sourceId: 'bus-1',
          companyCode: 1,
          busCode: 7,
          variantId: 42,
          lineLabel: 'D',
          sublineDescription: 'Subline',
          destinationCode: 'PI',
          destinationName: 'Plaza Independencia',
          lineTypeCode: 1,
          lineTypeName: 'Regular',
          subsystemCode: 1,
          subsystemName: 'STM',
          latitude: -34.901,
          longitude: -56.101,
          speedKmh: 18,
          receivedAt: DateTime(2026, 6, 1, 7, 0),
        ),
      ],
      discardedCount: 0,
      discardReasons: const {},
    );
    final source = TransitArrivalsSource(
      repo,
      liveSource: FakeRealtimeBusSource(snapshot),
    );
    final arrivals = await source.arrivalsForStop(
      's',
      DateTime(2026, 6, 1, 7, 0),
      limit: 5,
    );
    expect(arrivals, hasLength(1));
    expect(arrivals.single.isLive, isTrue);
    expect(arrivals.single.routeId, 'r1');
    expect(arrivals.single.variantId, 'r1:0:sh1');
  });

  test(
    'arrivals source falls back to scheduled data when the live source fails',
    () async {
      final service = ServiceCalendar(
        serviceId: 'daily',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        weekdays: {1, 2, 3, 4, 5, 6, 7},
      );
      final repo = FakeTransitRepository(
        stops: const [
          Stop(id: 's', name: 'Stop', latitude: -34.9, longitude: -56.1),
        ],
        routes: const [Route(id: 'r1', shortName: 'D', longName: 'Diagonal')],
        variants: const [],
        trips: const [
          Trip(
            id: 't1',
            routeId: 'r1',
            serviceId: 'daily',
            variantId: 'v1',
            headsign: 'Plaza',
          ),
        ],
        times: const [
          StopTime(
            tripId: 't1',
            stopId: 's',
            arrivalSeconds: 36000,
            departureSeconds: 36000,
            sequence: 1,
          ),
        ],
        calendars: [service],
      );
      final source = TransitArrivalsSource(
        repo,
        liveSource: _ThrowingRealtimeBusSource(),
      );
      final arrivals = await source.arrivalsForStop(
        's',
        DateTime(2026, 6, 1, 7, 0),
        limit: 5,
      );
      expect(arrivals, hasLength(1));
      expect(arrivals.single.isLive, isFalse);
      expect(arrivals.single.departureTime, DateTime(2026, 6, 1, 10, 0));
    },
  );

  test('GTFS parser derives variants and reads external variant_id', () {
    final parsed = parseGtfsZip(
      _feedZip(
        trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh1,701\nr,w,t2,1,sh2,702\n',
        withShapes: true,
      ),
    );
    expect(parsed.variants, hasLength(2));
    expect(parsed.variants.map((variant) => variant.directionId), ['0', '1']);
    expect(parsed.variants.map((variant) => variant.externalVariantId), [
      701,
      702,
    ]);
    expect(parsed.shapes, hasLength(2));
    expect(parsed.stopTimes.first.departureSeconds, 90000);
  });

  test('GTFS parser skips invalid data and summarizes omitted rows', () {
    final parsed = parseGtfsZip(
      _feedZip(
        stops: 'stop_id,stop_name,stop_lat,stop_lon\ngood,Good,-34.9,-56.1\nbad,Bad,not-a-coordinate,-56.1\nshort,Short,-34.9\n',
        trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\n',
      ),
    );
    expect(parsed.stops.map((stop) => stop.id), ['good']);
    expect(parsed.warningCount, 2);
    expect(
      parsed.warnings.any(
        (warning) => warning.contains('1 filas CSV inválidas'),
      ),
      isTrue,
    );
  });

  test('variant_map.csv can map trips or shapes to external ids', () {
    final parsed = parseGtfsZip(
      _feedZip(
        trips:
            'route_id,service_id,trip_id,direction_id,shape_id\nr,w,t,0,sh\n',
        variantMap: 'shape_id,external_variant_id\nsh,802\n',
      ),
    );
    expect(parsed.variants.single.externalVariantId, 802);
  });

  test('parser rejects corrupt zip and reports missing required files', () {
    expect(
      () => parseGtfsZip(
        File('test/fixtures/gtfs_corrupt.zip').readAsBytesSync(),
      ),
      throwsA(anything),
    );
    expect(
      () => parseGtfsZip(
        File('test/fixtures/gtfs_missing_required.zip').readAsBytesSync(),
      ),
      throwsFormatException,
    );
  });

  test(
    'bundled sample has synthetic lines, variants and an after-midnight trip',
    () {
      final parsed = parseGtfsZip(
        File('assets/sample_gtfs/sample_gtfs.zip').readAsBytesSync(),
      );
      expect(parsed.stops, hasLength(18));
      expect(parsed.routes, hasLength(3));
      expect(parsed.variants, hasLength(6));
      expect(
        parsed.variants.every((variant) => variant.externalVariantId != null),
        isTrue,
      );
      expect(
        parsed.stopTimes.any((time) => time.departureSeconds >= 24 * 3600),
        isTrue,
      );
    },
  );

  test(
    'SQLite import keeps the previous feed when the replacement fails',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp('rumbo-transit-');
      final store = TransitDatabase(
        directoryProvider: () async => directory,
        factory: databaseFactoryFfi,
      );
      await store.replaceFeed(
        await GtfsZipSource('').parse(
          _feedZip(
            trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\n',
          ),
          streamStopTimes: true,
        ),
        sourceName: 'Fixture local',
        etag: 'fixture-etag',
        downloadedAt: DateTime(2026, 1, 2),
      );
      var database = await store.open();
      expect((await database.query('stops')).single['name'], 'Stop');
      expect(
        (await database.query('variants')).single['external_variant_id'],
        701,
      );
      final metadata = (await database.query('feed_metadata')).single;
      expect(metadata['source'], 'Fixture local');
      expect(metadata['etag'], 'fixture-etag');
      expect(metadata['stop_count'], 1);
      expect(
        await database
            .rawQuery('SELECT COUNT(*) AS count FROM pattern_stops')
            .then((rows) => rows.single['count']),
        1,
      );
      final schedule = await SqfliteTransitRepository(() async => database)
          .scheduleForStops({'s'});
      expect(schedule.trips.map((trip) => trip.id), ['t1']);
      expect(schedule.stopTimes.map((time) => time.stopId), ['s']);
      expect(schedule.calendars, hasLength(1));
      final routesByStop = await SqfliteTransitRepository(() async => database)
          .routesForStops({'s', 'missing'});
      expect(routesByStop['s']?.map((route) => route.shortName), ['R']);
      expect(routesByStop['missing'], isEmpty);
      expect(
        (await SqfliteTransitRepository(() async => database)
                .searchStops('sto'))
            .map((stop) => stop.name),
        ['Stop'],
      );
      expect(
        await SqfliteTransitRepository(() async => database).searchStops('%'),
        isEmpty,
      );
      await database.close();

      final badFeed = await GtfsZipSource('').parse(
        _feedZip(
          trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t,0,sh,701\n',
        ),
        streamStopTimes: true,
      );
      final spool = File(badFeed.stopTimesFilePath!);
      final partialRows = List.generate(
        501,
        (index) => jsonEncode(['t', 's', 3600, 3600, index + 1]),
      ).join('\n');
      await spool.writeAsString('$partialRows\ninvalid-json\n');
      expect(() => store.replaceFeed(badFeed), throwsA(anything));
      database = await store.open();
      expect((await database.query('stops')).single['name'], 'Stop');
      expect((await database.query('routes')).length, 1);
      expect(
        await database
            .rawQuery('SELECT COUNT(*) AS count FROM pattern_stops')
            .then((rows) => rows.single['count']),
        1,
      );
      await database.close();
    },
  );

  test('STM GeoJSON parser validates, deduplicates by raw id and keeps stopped buses', () {
    final json = File('test/fixtures/stm_online_sample.json')
        .readAsStringSync();
    final receivedAt = DateTime(2026, 10, 23, 12);
    final snapshot = parseStmOnlineGeoJson(json, receivedAt);
    expect(snapshot.positions, hasLength(5));
    expect(snapshot.discardedCount, 5);
    expect(snapshot.duplicateCount, 1);
    expect(snapshot.discardReasons['fuera_de_uruguay'], 1);
    expect(snapshot.discardReasons['coordenadas_fuera_de_rango'], 1);
    expect(snapshot.discardReasons['id_duplicado'], 1);
    final stopped = snapshot.positions.singleWhere(
      (position) => position.busCode == 2,
    );
    expect(stopped.speedKmh, 0);
    expect(stopped.receivedAt, receivedAt);
    final repeated = snapshot.positions.singleWhere(
      (position) => position.sourceId == 'repeat-id',
    );
    expect(repeated.variantId, 107);
    expect(repeated.lineLabel, 'R3');
    expect(repeated.rawExtras['frecuencia'], 65535);
    expect(repeated.rawExtras['version'], 'demo');
    expect(
      snapshot.positions.any((position) => position.lineLabel == '14AB'),
      isTrue,
    );
  });

  test(
    'RealtimeMatcher joins known variants and preserves unknown variants',
    () async {
      final json = File('test/fixtures/stm_online_sample.json')
          .readAsStringSync();
      final snapshot = parseStmOnlineGeoJson(json, DateTime(2026));
      final fetchedSnapshot = await FakeRealtimeBusSource(snapshot).fetch();
      final repo = FakeTransitRepository(
        stops: [],
        routes: const [Route(id: 'route-1', shortName: 'R1')],
        variants: const [
          RouteVariant(
            id: 'v-101',
            routeId: 'route-1',
            directionId: '0',
            destination: 'Demo',
            externalVariantId: 101,
          ),
        ],
        trips: [],
        times: [],
        calendars: [],
      );
      final matches = await RealtimeMatcher(repo).match(fetchedSnapshot);
      final known = matches.singleWhere(
        (match) => match.position.variantId == 101,
      );
      final unknown = matches.singleWhere(
        (match) => match.position.variantId == 999999,
      );
      expect(known.route?.id, 'route-1');
      expect(known.variant?.externalVariantId, 101);
      expect(unknown.position.sourceId, 'unknown-variant');
      expect(unknown.route, isNull);
    },
  );
}

BusPosition _testBus({
  required double longitude,
  double latitude = 0,
  double speedKmh = 18,
  int variantId = 42,
  DateTime? receivedAt,
}) => BusPosition(
  sourceId: 'bus-test',
  companyCode: 1,
  busCode: 1,
  variantId: variantId,
  lineLabel: 'A',
  sublineDescription: 'A',
  destinationCode: 'D',
  destinationName: 'Destino',
  lineTypeCode: 1,
  lineTypeName: 'Regular',
  subsystemCode: 1,
  subsystemName: 'STM',
  latitude: latitude,
  longitude: longitude,
  speedKmh: speedKmh,
  receivedAt: receivedAt ?? DateTime(2026, 6, 1, 7),
);

Uint8List _feedZip({
  required String trips,
  String stops = 'stop_id,stop_name,stop_lat,stop_lon\ns,Stop,-34.9,-56.1\n',
  String? variantMap,
  bool withShapes = false,
  bool duplicateRoutes = false,
}) {
  final archive = Archive();
  void add(String name, String body) =>
      archive.addFile(ArchiveFile.string(name, body));
  add('stops.txt', stops);
  add(
    'routes.txt',
    duplicateRoutes
        ? 'route_id,route_short_name,route_type\nr,R,3\nr,Duplicate,3\n'
        : 'route_id,route_short_name,route_type\nr,R,3\n',
  );
  add('trips.txt', trips);
  add(
    'stop_times.txt',
    'trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt1,25:00:00,25:00:00,s,1\n',
  );
  add(
    'calendar.txt',
    'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nw,1,1,1,1,1,0,0,20260101,20271231\n',
  );
  if (withShapes) {
    add(
      'shapes.txt',
      'shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nsh1,-34.9,-56.1,1\nsh2,-34.8,-56.2,1\n',
    );
  }
  if (variantMap != null) {
    add('variant_map.csv', variantMap);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
