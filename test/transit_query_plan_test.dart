import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'read queries use indexes and the imported database is read-only',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rumbo-query-plan-',
      );
      final store = TransitDatabase(
        directoryProvider: () async => directory,
        factory: databaseFactoryFfi,
      );
      final db = await store.open();
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });

      final nearbyPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT id,name,lat,lon,code FROM stops '
        'WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
        [-35.0, -34.0, -58.0, -56.0],
      );
      final arrivalsPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT t.id AS trip_id, ps.stop_id, t.start_secs, '
        'ps.arrival_offset_secs, ps.departure_offset_secs '
        'FROM pattern_stops ps JOIN trips t ON t.pattern_id=ps.pattern_id '
        'WHERE ps.stop_id = ?',
        ['stop-1'],
      );
      final stopDetailPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM stops WHERE id = ? LIMIT 1',
        ['stop-1'],
      );
      String details(List<Map<String, Object?>> rows) =>
          rows.map((row) => row['detail']).join(' ');

      expect(details(nearbyPlan), contains('stops_lat_lon'));
      expect(details(arrivalsPlan), contains('pattern_stops_stop_id'));
      expect(details(arrivalsPlan), contains('trips_pattern_service_start'));
      expect(details(stopDetailPlan), contains('SEARCH stops'));
      expect(details(stopDetailPlan), contains('INDEX'));

      await expectLater(
        db.insert('stops', {
          'id': 'should-not-write',
          'name': 'Should not write',
          'lat': -34.9,
          'lon': -56.2,
        }),
        throwsA(isA<Exception>()),
      );
    },
  );
}
