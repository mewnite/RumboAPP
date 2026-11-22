// Builds the bundled transit seed database (assets/transit_db/rumbo_transit_seed.db)
// from the official GTFS feed.
//
// Run with:  dart run tool/build_seed_db.dart
//
// Mirrors TransitDatabase.replaceFeed() with the compact surrogate schema
// (pattern ids stored as INTEGER), so the seed has the same size as the app DB.
import "dart:io";

import "package:http/http.dart" as http;
import "package:path/path.dart" as p;
import "package:rumbo/core/config/transit_config.dart";
import "package:rumbo/features/stops_and_lines/data/gtfs_parser.dart";
import "package:rumbo/features/stops_and_lines/data/montevideo_linevariant_catalog_source.dart";
import "package:rumbo/features/stops_and_lines/data/stm_linevariant_catalog.dart";
import "package:sqlite3/sqlite3.dart";

import "feed_seed_freshness.dart";

const _schema = [
  "CREATE TABLE stops(id TEXT PRIMARY KEY,name TEXT NOT NULL,lat REAL NOT NULL,lon REAL NOT NULL,code TEXT)",
  "CREATE INDEX stops_lat_lon ON stops(lat,lon)",
  "CREATE TABLE routes(id TEXT PRIMARY KEY,short_name TEXT,long_name TEXT,color TEXT,text_color TEXT)",
  "CREATE TABLE variants(id TEXT PRIMARY KEY,route_id TEXT,direction_id TEXT,destination TEXT,shape_id TEXT,external_variant_id INTEGER)",
  "CREATE INDEX variants_route ON variants(route_id)",
  "CREATE INDEX variants_external_id ON variants(external_variant_id)",
  "CREATE TABLE trip_patterns(id INTEGER PRIMARY KEY AUTOINCREMENT)",
  "CREATE TABLE pattern_stops(pattern_id INTEGER,ordinal INTEGER,stop_id TEXT,arrival_offset_secs INTEGER,departure_offset_secs INTEGER,PRIMARY KEY(pattern_id,ordinal))",
  "CREATE INDEX pattern_stops_stop_id ON pattern_stops(stop_id)",
  "CREATE INDEX pattern_stops_pattern_ordinal ON pattern_stops(pattern_id,ordinal)",
  "CREATE TABLE trips(id TEXT PRIMARY KEY,route_id TEXT,service_id TEXT,variant_id TEXT,headsign TEXT,pattern_id INTEGER,start_secs INTEGER)",
  "CREATE INDEX trips_route ON trips(route_id)",
  "CREATE INDEX trips_pattern_service_start ON trips(pattern_id,service_id,start_secs)",
  "CREATE INDEX trips_variant_start ON trips(variant_id,start_secs)",
  "CREATE INDEX trips_service ON trips(service_id)",
  "CREATE TABLE shapes(shape_id TEXT,lat REAL,lon REAL,sequence INTEGER)",
  "CREATE INDEX shapes_id_sequence ON shapes(shape_id,sequence)",
  "CREATE TABLE calendars(service_id TEXT PRIMARY KEY,start_date TEXT,end_date TEXT,weekdays TEXT)",
  "CREATE TABLE calendar_exceptions(service_id TEXT,date TEXT,type INTEGER)",
  "CREATE INDEX calendar_exceptions_service_date_type ON calendar_exceptions(service_id,date,type)",
  "CREATE TABLE feed_metadata(source TEXT,version TEXT,downloaded_at TEXT,etag TEXT,valid_until TEXT,stop_count INTEGER,route_count INTEGER,variant_count INTEGER,trip_count INTEGER,stop_time_count INTEGER,shape_point_count INTEGER,calendar_count INTEGER,warning_count INTEGER,synthetic INTEGER)",
];

Future<void> main() async {
  if (transitConfig.url.isEmpty) {
    stderr.writeln(
      "transitConfig.url is empty; set RUMBO_API_BASE_URL to the GTFS proxy.",
    );
    exitCode = 1;
    return;
  }
  final client = http.Client();
  try {
    final request = http.Request("GET", Uri.parse(transitConfig.url))
      ..headers["User-Agent"] = "Rumbo/1.0 (app de transporte)";
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln("GTFS download failed: HTTP ${response.statusCode}");
      exitCode = 1;
      return;
    }
    final zipPath = p.join(
      Directory.systemTemp.path,
      "rumbo-build_seed_gtfs.zip",
    );
    final spoolPath = p.join(
      Directory.systemTemp.path,
      "rumbo-build_seed_stop_times.jsonl",
    );
    await File(zipPath).writeAsBytes(response.bodyBytes, flush: true);
    var parsed = parseGtfsZipFileToFile({
      "zipPath": zipPath,
      "stopTimesPath": spoolPath,
    });
    final spool = File(spoolPath);
    if (spool.existsSync()) spool.deleteSync();
    final zip = File(zipPath);
    if (zip.existsSync()) zip.deleteSync();
    final feedEndDate = parsed.feedInfo.endDate;
    if (feedEndDate == null ||
        !hasSevenDaysOfFeedValidityLeft(feedEndDate, today: DateTime.now())) {
      stderr.writeln(
        "GTFS feed_end_date is missing or less than 7 days away: "
        "${feedEndDate?.toIso8601String() ?? 'missing'}",
      );
      exitCode = 1;
      return;
    }
    stdout.writeln("seed_feed_version=${parsed.feedInfo.version}");
    stdout.writeln("seed_feed_end_date=${feedEndDate.toIso8601String()}");

    final catalogSource = MontevideoLineVariantCatalogSource(
      transitConfig.realtimeEndpoint,
    );
    try {
      final catalog = await catalogSource.fetch();
      final links = linkGtfsVariants(parsed, catalog);
      parsed = links.feed;
      stdout.writeln(
        "seed_variant_links=${links.linkedCount}/${parsed.variants.length} "
        "shape_id=${links.shapeIdMatches} "
        "destination=${links.destinationMatches} "
        "unmatched=${links.unmatchedCount}",
      );
    } finally {
      catalogSource.close();
    }

    final outDir = Directory("build/rumbo_transit_seed");
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);
    final outPath = p.join(outDir.path, "rumbo_transit.db");
    final db = sqlite3.open(outPath);
    try {
      db.execute("PRAGMA journal_mode=OFF");
      db.execute("PRAGMA synchronous=OFF");
      // Match the app DB version so TransitDatabase.open() accepts the seed
      // without running migrations. _databaseVersion == 7.
      db.execute("PRAGMA user_version = 7");
      for (final sql in _schema) {
        db.execute(sql);
      }

      for (final stop in parsed.stops) {
        db.execute("INSERT INTO stops VALUES (?,?,?,?,?)", [
          stop.id,
          stop.name,
          stop.latitude,
          stop.longitude,
          stop.code,
        ]);
      }
      for (final route in parsed.routes) {
        db.execute("INSERT INTO routes VALUES (?,?,?,?,?)", [
          route.id,
          route.shortName,
          route.longName,
          route.color,
          route.textColor,
        ]);
      }
      for (final variant in parsed.variants) {
        db.execute("INSERT INTO variants VALUES (?,?,?,?,?,?)", [
          variant.id,
          variant.routeId,
          variant.directionId,
          variant.destination,
          variant.shapeId,
          variant.externalVariantId,
        ]);
      }

      final patternsToWrite = parsed.patterns!;
      final patternIdToSurrogate = {
        for (var i = 0; i < patternsToWrite.length; i++)
          patternsToWrite[i].id: i + 1,
      };
      for (final trip in parsed.trips) {
        db.execute("INSERT INTO trips VALUES (?,?,?,?,?,?,?)", [
          trip.id,
          trip.routeId,
          trip.serviceId,
          trip.variantId,
          trip.headsign,
          patternIdToSurrogate[trip.patternId],
          trip.startSecs,
        ]);
      }
      for (final pattern in patternsToWrite) {
        db.execute("INSERT INTO trip_patterns(id) VALUES (?)", [
          patternIdToSurrogate[pattern.id],
        ]);
      }
      for (final pattern in patternsToWrite) {
        for (final point in pattern.stops) {
          db.execute("INSERT INTO pattern_stops VALUES (?,?,?,?,?)", [
            patternIdToSurrogate[pattern.id],
            point.ordinal,
            point.stopId,
            point.arrivalOffsetSecs,
            point.departureOffsetSecs,
          ]);
        }
      }
      for (final shape in parsed.shapes) {
        for (final point in shape.points) {
          db.execute("INSERT INTO shapes VALUES (?,?,?,?)", [
            shape.id,
            point.latitude,
            point.longitude,
            point.sequence,
          ]);
        }
      }
      for (final calendar in parsed.calendars) {
        db.execute("INSERT INTO calendars VALUES (?,?,?,?)", [
          calendar.serviceId,
          calendar.startDate.toIso8601String(),
          calendar.endDate.toIso8601String(),
          calendar.weekdays.join(","),
        ]);
      }
      for (final calendar in parsed.calendars) {
        for (final date in calendar.addedDates) {
          db.execute("INSERT INTO calendar_exceptions VALUES (?,?,?)", [
            calendar.serviceId,
            date.toIso8601String(),
            1,
          ]);
        }
        for (final date in calendar.removedDates) {
          db.execute("INSERT INTO calendar_exceptions VALUES (?,?,?)", [
            calendar.serviceId,
            date.toIso8601String(),
            2,
          ]);
        }
      }
      final validUntil =
          parsed.feedInfo.endDate ??
          (parsed.calendars.isEmpty
              ? null
              : parsed.calendars
                    .map((calendar) => calendar.endDate)
                    .reduce((a, b) => a.isAfter(b) ? a : b));
      db.execute(
        "INSERT INTO feed_metadata VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          transitConfig.sourceName,
          parsed.feedInfo.version,
          DateTime.now().toIso8601String(),
          response.headers["etag"],
          validUntil?.toIso8601String(),
          parsed.stops.length,
          parsed.routes.length,
          parsed.variants.length,
          parsed.trips.length,
          parsed.stopTimeCount,
          parsed.shapes.fold<int>(
            0,
            (count, shape) => count + shape.points.length,
          ),
          parsed.calendars.length,
          parsed.warningCount,
          parsed.feedInfo.synthetic ? 1 : 0,
        ],
      );
      db.close();
    } catch (error) {
      try {
        db.close();
      } on Object {
        // Ignore close failures; the failed seed must not be promoted.
      }
      stderr.writeln("seed_build_failed=$error");
      exitCode = 1;
      return;
    }
    final seed = File(outPath);
    final target = File("assets/transit_db/rumbo_transit_seed.db");
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(seed.readAsBytesSync());
    stdout.writeln("seed_db_bytes=${target.lengthSync()}");
    stdout.writeln("seed_db_mb=${target.lengthSync() / 1048576}");
  } finally {
    client.close();
  }
}
