import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_feed_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('diagnostics report a missing database without creating one', () async {
    final directory = await Directory.systemTemp.createTemp(
      'rumbo-diagnostics-',
    );
    final store = TransitDatabase(
      directoryProvider: () async => directory,
      factory: databaseFactoryFfi,
    );

    final diagnostics = await store.diagnostics();

    expect(diagnostics.fileSizeBytes, 0);
    expect(diagnostics.schemaVersion, 0);
    expect(diagnostics.variantCount, 0);
    expect(diagnostics.variantsWithExternalId, 0);
    expect(
      File('${directory.path}${Platform.pathSeparator}rumbo_transit.db')
          .existsSync(),
      isFalse,
    );
    await directory.delete(recursive: true);
  });

  test(
    'installSeed replaces an empty DB and the app accepts it as usable',
    () async {
      final directory = await Directory.systemTemp.createTemp('rumbo-seed-');
      final store = TransitDatabase(
        directoryProvider: () async => directory,
        factory: databaseFactoryFfi,
      );
      final parsed = await GtfsZipSource('').parse(
        _feedZip(
          trips:
              'route_id,service_id,trip_id,direction_id,shape_id,variant_id\n'
              'r,w,t1,0,sh,701\n',
        ),
        streamStopTimes: true,
      );
      await store.replaceFeed(parsed, sourceName: 'Seed test');
      final seedBytes = File(
        '${directory.path}${Platform.pathSeparator}rumbo_transit.db',
      ).readAsBytesSync();
      expect(seedBytes, isNotEmpty);

      final targetDir = await Directory.systemTemp.createTemp(
        'rumbo-seed-target-',
      );
      final target = TransitDatabase(
        directoryProvider: () async => targetDir,
        factory: databaseFactoryFfi,
      );
      final progress = <double>[];
      expect(
        await target.installSeed(seedBytes, onProgress: progress.add),
        isTrue,
      );
      expect(progress, contains(1.0));

      final database = await target.open();
      expect(await target.hasUsableFeed(database), isTrue);
      expect(
        (await database.rawQuery('PRAGMA user_version')).single.values.first,
        7,
      );
      expect((await database.query('stops')), isNotEmpty);
      await database.close();
      final diagnostics = await target.diagnostics();
      expect(diagnostics.fileSizeBytes, seedBytes.length);
      expect(diagnostics.schemaVersion, 7);
      expect(diagnostics.variantCount, 1);
      expect(diagnostics.variantsWithExternalId, 1);

      await directory.delete(recursive: true);
      await targetDir.delete(recursive: true);
    },
  );

  test(
    'installSeed rejects a corrupt seed and keeps the live database',
    () async {
      final targetDir = await Directory.systemTemp.createTemp(
        'rumbo-seed-bad-',
      );
      final target = TransitDatabase(
        directoryProvider: () async => targetDir,
        factory: databaseFactoryFfi,
      );
      expect(await target.installSeed(Uint8List.fromList([1, 2, 3])), isFalse);
      final database = await target.open();
      expect(await target.hasUsableFeed(database), isFalse);
      await database.close();
      await targetDir.delete(recursive: true);
    },
  );
}

Uint8List _feedZip({
  required String trips,
  String stops = 'stop_id,stop_name,stop_lat,stop_lon\ns,Stop,-34.9,-56.1\n',
}) {
  final archive = Archive();
  void add(String name, String body) =>
      archive.addFile(ArchiveFile.string(name, body));
  add('stops.txt', stops);
  add('routes.txt', 'route_id,route_short_name,route_type\nr,R,3\n');
  add('trips.txt', trips);
  add(
    'stop_times.txt',
    'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
        't1,25:00:00,25:00:00,s,1\n',
  );
  add(
    'calendar.txt',
    'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,'
        'start_date,end_date\n'
        'w,1,1,1,1,1,0,0,20260101,20271231\n',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
