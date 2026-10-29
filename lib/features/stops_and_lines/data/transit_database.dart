import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/debug/performance_measurement.dart';
import '../domain/transit_models.dart';
import 'gtfs_parser.dart';

/// Writes a complete feed into a temporary database and swaps files only after
/// the transaction commits, leaving the previous database usable on failure.
class TransitDatabase {
  TransitDatabase({
    Future<Directory> Function()? directoryProvider,
    DatabaseFactory? factory,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _factory = factory ?? databaseFactory;

  final Future<Directory> Function() _directoryProvider;
  final DatabaseFactory _factory;

  Future<Database> open() async {
    final dir = await _directoryProvider();
    final path = p.join(dir.path, 'rumbo_transit.db');
    if (await File(path).exists()) {
      final existing = await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version = Sqflite.firstIntValue(
        await existing.rawQuery('PRAGMA user_version'),
      );
      if (version == _databaseVersion) {
        await _logDatabaseMetrics(path);
        return existing;
      }
      await existing.close();
    }

    final writable = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, _) => _schema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE variants ADD COLUMN external_variant_id INTEGER',
            );
            await db.execute(
              'CREATE INDEX variants_external_id ON variants(external_variant_id)',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN variant_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN trip_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN stop_time_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN shape_point_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN calendar_count INTEGER DEFAULT 0',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE feed_metadata ADD COLUMN synthetic INTEGER DEFAULT 0',
            );
          }
          if (oldVersion < 5) {
            await db.execute('DROP TABLE IF EXISTS stop_times');
            await db.execute('DROP TABLE IF EXISTS trips');
            await db.execute('DROP TABLE IF EXISTS trip_patterns');
            await db.execute('DROP TABLE IF EXISTS pattern_stops');
            await _schema(db);
          }
          if (oldVersion < 6) {
            await db.execute('DROP TABLE IF EXISTS stop_times');
            if (!await _columnExists(db, 'trips', 'pattern_id')) {
              await db.execute('ALTER TABLE trips ADD COLUMN pattern_id TEXT');
            }
            if (!await _columnExists(db, 'trips', 'start_secs')) {
              await db.execute(
                'ALTER TABLE trips ADD COLUMN start_secs INTEGER',
              );
            }
            await db.execute(
              'CREATE INDEX IF NOT EXISTS trips_pattern_service_start ON trips(pattern_id, service_id, start_secs)',
            );
            await db.execute(
              'CREATE TABLE IF NOT EXISTS trip_patterns(pattern_id TEXT PRIMARY KEY)',
            );
            await db.execute(
              'CREATE TABLE IF NOT EXISTS pattern_stops(pattern_id TEXT,ordinal INTEGER,stop_id TEXT,arrival_offset_secs INTEGER,departure_offset_secs INTEGER,PRIMARY KEY(pattern_id,ordinal))',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS pattern_stops_stop_id ON pattern_stops(stop_id)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS pattern_stops_pattern_ordinal ON pattern_stops(pattern_id,ordinal)',
            );
          }
        },
      ),
    );
    await writable.close();
    final readOnly = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await _logDatabaseMetrics(path);
    return readOnly;
  }

  Future<void> _logDatabaseMetrics(String path) async {
    if (!PerformanceMeasurement.enabled) return;
    final file = File(path);
    if (await file.exists()) {
      debugPrint('[performance] database.size ${await file.length()}bytes');
    }
    debugPrint('[performance] memory.rss ${ProcessInfo.currentRss}bytes');
  }

  Future<bool> hasUsableFeed(Database db) async {
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM stops) AS stops,
        (SELECT COUNT(*) FROM routes) AS routes,
        (SELECT COUNT(*) FROM trips) AS trips,
        (SELECT COUNT(*) FROM trip_patterns) AS patterns,
        (SELECT COUNT(*) FROM pattern_stops) AS pattern_stops
    ''');
    final row = rows.single;
    return (row['stops'] as int? ?? 0) > 0 &&
        (row['routes'] as int? ?? 0) > 0 &&
        (row['trips'] as int? ?? 0) > 0 &&
        (row['patterns'] as int? ?? 0) > 0 &&
        (row['pattern_stops'] as int? ?? 0) > 0;
  }

  Future<void> replaceFeed(
    GtfsParseResult feed, {
    String sourceName = 'Datos sintéticos de prueba',
    String? etag,
    DateTime? downloadedAt,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _directoryProvider();
    final live = p.join(dir.path, 'rumbo_transit.db'),
        temp = p.join(dir.path, 'rumbo_transit.new.db'),
        backup = p.join(dir.path, 'rumbo_transit.previous.db');
    await _factory.deleteDatabase(temp);
    final db = await _factory.openDatabase(
      temp,
      options: OpenDatabaseOptions(
        // Keep the replacement database at the same schema version as the
        // live database. Opening a v5 replacement as v6 runs the legacy
        // migration and can remove the pattern tables just imported.
        version: _databaseVersion,
        onCreate: (db, _) => _schema(db),
      ),
    );
    var databaseClosed = false;
    try {
      // This is a disposable build database. The previous live database stays
      // untouched until the completed file is atomically swapped into place,
      // so disabling SQLite's per-page journal here avoids redundant I/O while
      // retaining crash safety for the data already in use.
      await db.execute('PRAGMA journal_mode=OFF');
      await db.execute('PRAGMA synchronous=OFF');
      await db.transaction((txn) async {
        var batch = txn.batch();
        var pendingRows = 0;
        final totalRows =
            feed.stops.length +
            feed.routes.length +
            feed.variants.length +
            feed.trips.length +
            (feed.patterns ?? const <TripPattern>[]).fold<int>(
              0,
              (count, pattern) => count + 1 + pattern.stops.length,
            ) +
            feed.shapes.fold<int>(
              0,
              (count, shape) => count + shape.points.length,
            ) +
            feed.calendars.length +
            feed.calendars.fold<int>(
              0,
              (count, calendar) =>
                  count +
                  calendar.addedDates.length +
                  calendar.removedDates.length,
            ) +
            1;
        var insertedRows = 0;
        var lastReportedProgress = 0.0;

        Future<void> commitBatch() async {
          if (pendingRows == 0) return;
          await batch.commit(noResult: true);
          batch = txn.batch();
          pendingRows = 0;
        }

        Future<void> insertRows(
          String table,
          Iterable<Map<String, Object?>> rows,
        ) async {
          for (final values in rows) {
            batch.insert(table, values);
            pendingRows++;
            insertedRows++;
            final progress = insertedRows / totalRows;
            if (progress - lastReportedProgress >= .01) {
              lastReportedProgress = progress;
              onProgress?.call(progress.clamp(0.0, 1.0));
            }
            if (pendingRows >= _importBatchSize) await commitBatch();
          }
        }

        await insertRows(
          'stops',
          feed.stops.map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'lat': s.latitude,
              'lon': s.longitude,
              'code': s.code,
            },
          ),
        );
        await insertRows(
          'routes',
          feed.routes.map(
            (r) => {
              'id': r.id,
              'short_name': r.shortName,
              'long_name': r.longName,
              'color': r.color,
              'text_color': r.textColor,
            },
          ),
        );
        await insertRows(
          'variants',
          feed.variants.map(
            (v) => {
              'id': v.id,
              'route_id': v.routeId,
              'direction_id': v.directionId,
              'destination': v.destination,
              'shape_id': v.shapeId,
              'external_variant_id': v.externalVariantId,
            },
          ),
        );
        await insertRows(
          'trips',
          feed.trips.map(
            (t) => {
              'id': t.id,
              'route_id': t.routeId,
              'service_id': t.serviceId,
              'variant_id': t.variantId,
              'headsign': t.headsign,
              'pattern_id': t.patternId,
              'start_secs': t.startSecs,
            },
          ),
        );
        late final List<TripPattern> patternsToWrite;
        // The GTFS parser already groups rows into patterns as it streams the
        // file. Prefer that compact result; rereading every stop_time into a
        // second in-memory list made the first launch needlessly slow.
        if (feed.patterns?.isNotEmpty == true) {
          patternsToWrite = feed.patterns!;
        } else if (feed.stopTimesFilePath != null) {
          final spoolTimes = <StopTime>[];
          final lines = File(feed.stopTimesFilePath!)
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter());
          await for (final line in lines) {
            if (line.isEmpty) continue;
            final row = jsonDecode(line) as List<Object?>;
            spoolTimes.add(
              StopTime(
                tripId: row[0] as String,
                stopId: row[1] as String,
                arrivalSeconds: row[2] as int,
                departureSeconds: row[3] as int,
                sequence: row[4] as int,
              ),
            );
          }
          final computed = computePatternsFromTimes(spoolTimes);
          patternsToWrite = computed.$1.toList(growable: false);
          for (var i = 0; i < feed.trips.length; i++) {
            final t = feed.trips[i];
            feed.trips[i] = Trip(
              id: t.id,
              routeId: t.routeId,
              serviceId: t.serviceId,
              variantId: t.variantId,
              headsign: t.headsign,
              patternId: computed.$2[t.id],
              startSecs: computed.$3[t.id],
            );
          }
        } else {
          final computed = computePatternsFromTimes(feed.stopTimes);
          patternsToWrite = computed.$1.toList(growable: false);
          for (var i = 0; i < feed.trips.length; i++) {
            final t = feed.trips[i];
            feed.trips[i] = Trip(
              id: t.id,
              routeId: t.routeId,
              serviceId: t.serviceId,
              variantId: t.variantId,
              headsign: t.headsign,
              patternId: computed.$2[t.id],
              startSecs: computed.$3[t.id],
            );
          }
        }

        await insertRows(
          'trip_patterns',
          patternsToWrite.map((pattern) => {'pattern_id': pattern.id}),
        );
        await insertRows(
          'pattern_stops',
          patternsToWrite.expand(
            (pattern) => pattern.stops.map(
              (point) => {
                'pattern_id': pattern.id,
                'ordinal': point.ordinal,
                'stop_id': point.stopId,
                'arrival_offset_secs': point.arrivalOffsetSecs,
                'departure_offset_secs': point.departureOffsetSecs,
              },
            ),
          ),
        );
        await insertRows(
          'shapes',
          feed.shapes.expand(
            (shape) => shape.points.map(
              (point) => {
                'shape_id': shape.id,
                'lat': point.latitude,
                'lon': point.longitude,
                'sequence': point.sequence,
              },
            ),
          ),
        );
        await insertRows(
          'calendars',
          feed.calendars.map(
            (c) => {
              'service_id': c.serviceId,
              'start_date': c.startDate.toIso8601String(),
              'end_date': c.endDate.toIso8601String(),
              'weekdays': c.weekdays.join(','),
            },
          ),
        );
        await insertRows(
          'calendar_exceptions',
          feed.calendars.expand(
            (calendar) => [
              ...calendar.addedDates.map(
                (date) => {
                  'service_id': calendar.serviceId,
                  'date': date.toIso8601String(),
                  'type': 1,
                },
              ),
              ...calendar.removedDates.map(
                (date) => {
                  'service_id': calendar.serviceId,
                  'date': date.toIso8601String(),
                  'type': 2,
                },
              ),
            ],
          ),
        );
        await insertRows('feed_metadata', [
          {
            'source': sourceName,
            'version': feed.feedInfo.version,
            'downloaded_at': (downloadedAt ?? DateTime.now()).toIso8601String(),
            'etag': etag,
            'valid_until': (feed.feedInfo.endDate ?? _latestEndDate(feed))
                ?.toIso8601String(),
            'stop_count': feed.stops.length,
            'route_count': feed.routes.length,
            'variant_count': feed.variants.length,
            'trip_count': feed.trips.length,
            'stop_time_count': feed.stopTimeCount,
            'shape_point_count': feed.shapes.fold<int>(
              0,
              (total, shape) => total + shape.points.length,
            ),
            'calendar_count': feed.calendars.length,
            'warning_count': feed.warningCount,
            'synthetic': feed.feedInfo.synthetic ? 1 : 0,
          },
        ]);
        await commitBatch();
      });
      await db.close();
      databaseClosed = true;
      final liveFile = File(live),
          backupFile = File(backup),
          tempFile = File(temp);
      if (await backupFile.exists()) await backupFile.delete();
      if (await liveFile.exists()) await liveFile.rename(backup);
      try {
        await tempFile.rename(live);
      } catch (_) {
        if (await backupFile.exists()) await backupFile.rename(live);
        rethrow;
      }
      if (await backupFile.exists()) {
        try {
          await backupFile.delete();
        } on FileSystemException {
          // The completed database is already live; a stale backup is safe.
        }
      }
      if (feed.stopTimesFilePath != null) {
        final spool = File(feed.stopTimesFilePath!);
        if (await spool.exists()) {
          try {
            await spool.delete();
          } on FileSystemException {
            // Temporary cleanup should not turn a committed feed into an error.
          }
        }
      }
    } catch (error, stackTrace) {
      if (!databaseClosed) {
        try {
          await db.close();
        } catch (_) {
          // Preserve the import error; a failure to close is secondary.
        }
      }
      try {
        await _factory.deleteDatabase(temp);
      } catch (_) {
        // The failed import remains discarded even if cleanup fails.
      }
      if (feed.stopTimesFilePath != null) {
        final spool = File(feed.stopTimesFilePath!);
        if (await spool.exists()) {
          try {
            await spool.delete();
          } on FileSystemException {
            // Keep the import error as the reported cause.
          }
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

const _importBatchSize = 500;
const _databaseVersion = 6;

Future<bool> _columnExists(
  DatabaseExecutor db,
  String table,
  String column,
) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.any((row) => row['name'] == column);
}

DateTime? _latestEndDate(GtfsParseResult feed) {
  if (feed.calendars.isEmpty) return null;
  return feed.calendars
      .map((calendar) => calendar.endDate)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

Future<void> _schema(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE stops(id TEXT PRIMARY KEY,name TEXT NOT NULL,lat REAL NOT NULL,lon REAL NOT NULL,code TEXT)',
  );
  await db.execute('CREATE INDEX stops_lat_lon ON stops(lat,lon)');
  await db.execute(
    'CREATE TABLE routes(id TEXT PRIMARY KEY,short_name TEXT,long_name TEXT,color TEXT,text_color TEXT)',
  );
  await db.execute(
    'CREATE TABLE variants(id TEXT PRIMARY KEY,route_id TEXT,direction_id TEXT,destination TEXT,shape_id TEXT,external_variant_id INTEGER)',
  );
  await db.execute('CREATE INDEX variants_route ON variants(route_id)');
  await db.execute(
    'CREATE INDEX variants_external_id ON variants(external_variant_id)',
  );
  await db.execute('CREATE TABLE trip_patterns(pattern_id TEXT PRIMARY KEY)');
  await db.execute(
    'CREATE TABLE pattern_stops(pattern_id TEXT,ordinal INTEGER,stop_id TEXT,arrival_offset_secs INTEGER,departure_offset_secs INTEGER,PRIMARY KEY(pattern_id,ordinal))',
  );
  await db.execute(
    'CREATE INDEX pattern_stops_stop_id ON pattern_stops(stop_id)',
  );
  await db.execute(
    'CREATE INDEX pattern_stops_pattern_ordinal ON pattern_stops(pattern_id,ordinal)',
  );
  await db.execute(
    'CREATE TABLE trips(id TEXT PRIMARY KEY,route_id TEXT,service_id TEXT,variant_id TEXT,headsign TEXT,pattern_id TEXT,start_secs INTEGER)',
  );
  await db.execute('CREATE INDEX trips_route ON trips(route_id)');
  await db.execute(
    'CREATE INDEX trips_pattern_service_start ON trips(pattern_id,service_id,start_secs)',
  );
  await db.execute(
    'CREATE TABLE shapes(shape_id TEXT,lat REAL,lon REAL,sequence INTEGER)',
  );
  await db.execute(
    'CREATE INDEX shapes_id_sequence ON shapes(shape_id,sequence)',
  );
  await db.execute(
    'CREATE TABLE calendars(service_id TEXT PRIMARY KEY,start_date TEXT,end_date TEXT,weekdays TEXT)',
  );
  await db.execute(
    'CREATE TABLE calendar_exceptions(service_id TEXT,date TEXT,type INTEGER)',
  );
  await db.execute(
    'CREATE TABLE feed_metadata(source TEXT,version TEXT,downloaded_at TEXT,etag TEXT,valid_until TEXT,stop_count INTEGER,route_count INTEGER,variant_count INTEGER,trip_count INTEGER,stop_time_count INTEGER,shape_point_count INTEGER,calendar_count INTEGER,warning_count INTEGER,synthetic INTEGER)',
  );
}
