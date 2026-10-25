import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_database.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_feed_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('imports the small bundled GTFS within a few seconds', () async {
    sqfliteFfiInit();
    final bytes = Uint8List.fromList(
      File('assets/sample_gtfs/sample_gtfs.zip').readAsBytesSync(),
    );
    final directory = await Directory.systemTemp.createTemp('rumbo-bench-');
    final zipPath = '${directory.path}${Platform.pathSeparator}sample.zip';
    await File(zipPath).writeAsBytes(bytes);
    final stopwatch = Stopwatch()..start();
    final feed = await GtfsZipSource('').parseFile(zipPath);
    final store = TransitDatabase(
      directoryProvider: () async => directory,
      factory: databaseFactoryFfi,
    );
    await store.replaceFeed(feed);
    stopwatch.stop();
    final database = await store.open();
    final importedCount = (await database.rawQuery(
      'SELECT COUNT(*) AS count FROM stop_times',
    )).single['count'];
    await database.close();
    // Printed by `flutter test --reporter expanded` for the implementation log.
    // ignore: avoid_print
    print(
      'GTFS sample streaming parse+SQLite import: '
      '${stopwatch.elapsedMilliseconds} ms '
      '(${bytes.length} bytes, ${feed.stopTimeCount} stop_times)',
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(importedCount, feed.stopTimeCount);
  });
}
