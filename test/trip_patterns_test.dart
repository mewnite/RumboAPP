import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/data/gtfs_parser.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_feed_source.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List feedZip({
  required String trips,
  String stops = 'stop_id,stop_name,stop_lat,stop_lon\ns,Stop,-34.9,-56.1\n',
  String? variantMap,
  bool withShapes = false,
  bool duplicateRoutes = false,
  String stopTimes = 'trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt1,25:00:00,25:00:00,s,1\n',
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
  add('stop_times.txt', stopTimes);
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

void main() {
  test(
    'computePatternsFromTimes groups identical sequences under one pattern',
    () {
      final times = [
        const StopTime(
          tripId: 't1',
          stopId: 's1',
          arrivalSeconds: 3600,
          departureSeconds: 3600,
          sequence: 1,
        ),
        const StopTime(
          tripId: 't1',
          stopId: 's2',
          arrivalSeconds: 7200,
          departureSeconds: 7200,
          sequence: 2,
        ),
        const StopTime(
          tripId: 't2',
          stopId: 's1',
          arrivalSeconds: 3600,
          departureSeconds: 3600,
          sequence: 1,
        ),
        const StopTime(
          tripId: 't2',
          stopId: 's2',
          arrivalSeconds: 7200,
          departureSeconds: 7200,
          sequence: 2,
        ),
      ];
      final (patterns, tripPatternIds, _) = computePatternsFromTimes(times);
      expect(patterns, hasLength(1));
      expect(tripPatternIds['t1'], tripPatternIds['t2']);
      expect(patterns.first.stops, hasLength(2));
      expect(patterns.first.stops[0].departureOffsetSecs, 0);
      expect(patterns.first.stops[1].departureOffsetSecs, 3600);
    },
  );

  test(
    'computePatternsFromTimes gives distinct patterns for different sequences',
    () {
      final times = [
        const StopTime(
          tripId: 't1',
          stopId: 's1',
          arrivalSeconds: 3600,
          departureSeconds: 3600,
          sequence: 1,
        ),
        const StopTime(
          tripId: 't1',
          stopId: 's2',
          arrivalSeconds: 7200,
          departureSeconds: 7200,
          sequence: 2,
        ),
        const StopTime(
          tripId: 't2',
          stopId: 's1',
          arrivalSeconds: 3600,
          departureSeconds: 3600,
          sequence: 1,
        ),
        const StopTime(
          tripId: 't2',
          stopId: 's3',
          arrivalSeconds: 7200,
          departureSeconds: 7200,
          sequence: 2,
        ),
      ];
      final (patterns, tripPatternIds, _) = computePatternsFromTimes(times);
      expect(patterns, hasLength(2));
      expect(tripPatternIds['t1'], isNot(tripPatternIds['t2']));
    },
  );

  test(
    'computePatternsFromTimes computes offsets relative to first departure',
    () {
      final times = [
        const StopTime(
          tripId: 't1',
          stopId: 's1',
          arrivalSeconds: 90000,
          departureSeconds: 90000,
          sequence: 1,
        ),
        const StopTime(
          tripId: 't1',
          stopId: 's2',
          arrivalSeconds: 91800,
          departureSeconds: 91800,
          sequence: 2,
        ),
      ];
      final (patterns, _, tripStartSecs) = computePatternsFromTimes(times);
      expect(patterns.first.stops[0].arrivalOffsetSecs, 0);
      expect(patterns.first.stops[1].arrivalOffsetSecs, 1800);
      expect(tripStartSecs['t1'], 90000);
    },
  );

  test(
    'parser assigns pattern_id and start_secs to trips from sample GTFS',
    () {
      final parsed = parseGtfsZip(
        File('assets/sample_gtfs/sample_gtfs.zip').readAsBytesSync(),
      );
      expect(parsed.patterns, isNotEmpty);
      expect(parsed.patterns?.length, parsed.trips.length);
      for (final trip in parsed.trips) {
        expect(trip.patternId, isNotNull);
        expect(trip.patternId, isNotEmpty);
        expect(trip.startSecs, isNotNull);
      }
    },
  );

  test(
    'upcomingDepartures includes previous service day after midnight',
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
        patternId: 'p',
        startSecs: 90000,
      );
      final repo = FakeTransitRepository(
        stops: [const Stop(id: 's', name: 'Stop', latitude: 0, longitude: 0)],
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

  test(
    'SQLite import deduplicates repeated trip patterns before insert',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'rumbo-pattern-dedup-',
      );
      final feed = await GtfsZipSource('').parse(
        feedZip(
          trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\nr,w,t2,0,sh,701\n',
          stopTimes: 'trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt1,06:00:00,06:00:00,s,1\nt1,06:10:00,06:10:00,s2,2\nt2,06:15:00,06:15:00,s,1\nt2,06:25:00,06:25:00,s2,2\n',
        ),
        streamStopTimes: true,
      );
      expect(feed.patterns, hasLength(1));

      final store = TransitDatabase(
        directoryProvider: () async => directory,
        factory: databaseFactoryFfi,
      );
      await store.replaceFeed(feed);
      final database = await store.open();
      expect(
        (await database.rawQuery('SELECT COUNT(*) AS count FROM trip_patterns'))
            .single['count'],
        1,
      );
      expect(
        (await database.rawQuery('SELECT COUNT(*) AS count FROM pattern_stops'))
            .single['count'],
        2,
      );
      expect(
        (await database.rawQuery(
          'SELECT COUNT(DISTINCT pattern_id) AS count FROM trips',
        )).single['count'],
        1,
      );
      await database.close();
    },
  );

  test('SQLite import writes trip_patterns and pattern_stops instead of stop_times', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('rumbo-patterns-');
    final store = TransitDatabase(
      directoryProvider: () async => directory,
      factory: databaseFactoryFfi,
    );
    await store.replaceFeed(
      await GtfsZipSource('').parse(
        feedZip(
          trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\n',
        ),
        streamStopTimes: true,
      ),
      sourceName: 'Fixture local',
      etag: 'fixture-etag',
      downloadedAt: DateTime(2026, 1, 2),
    );
    final database = await store.open();
    expect(
      (await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='stop_times'",
      )),
      isEmpty,
    );
    final patternCount = (await database.rawQuery(
      'SELECT COUNT(*) AS count FROM trip_patterns',
    )).single['count'];
    expect(patternCount, greaterThan(0));
    final stopCount = (await database.rawQuery(
      'SELECT COUNT(*) AS count FROM pattern_stops',
    )).single['count'];
    expect(stopCount, greaterThan(0));
    final tripsWithPattern = (await database.rawQuery(
      'SELECT COUNT(*) AS count FROM trips WHERE pattern_id IS NOT NULL',
    )).single['count'];
    expect(tripsWithPattern, 1);
    await database.close();
  });

  test('migration from v5 schema with stop_times produces patterns', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('rumbo-migrate-');
    final v5Store = TransitDatabase(
      directoryProvider: () async => directory,
      factory: databaseFactoryFfi,
    );
    await v5Store.replaceFeed(
      await GtfsZipSource('').parse(
        feedZip(
          trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\n',
        ),
        streamStopTimes: true,
      ),
    );
    final v5Db = await v5Store.open();
    await v5Db.close();

    final v6Store = TransitDatabase(
      directoryProvider: () async => directory,
      factory: databaseFactoryFfi,
    );
    await v6Store.replaceFeed(
      await GtfsZipSource('').parse(
        feedZip(
          trips: 'route_id,service_id,trip_id,direction_id,shape_id,variant_id\nr,w,t1,0,sh,701\n',
        ),
        streamStopTimes: true,
      ),
    );
    final v6Db = await v6Store.open();
    final stopTables = await v6Db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='stop_times'",
    );
    expect(stopTables, isEmpty);
    final patternCount = (await v6Db.rawQuery(
      'SELECT COUNT(*) AS count FROM trip_patterns',
    )).single['count'];
    expect(patternCount, greaterThan(0));
    await v6Db.close();
  });
}
