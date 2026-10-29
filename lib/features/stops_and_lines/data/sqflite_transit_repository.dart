import 'dart:isolate';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../../core/debug/performance_measurement.dart';
import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

class SqfliteTransitRepository implements TransitRepository {
  const SqfliteTransitRepository(this._database);
  final Future<Database> Function() _database;

  @override
  Future<List<Stop>> nearbyStops(
    double latitude,
    double longitude,
    double radiusMeters,
  ) async {
    final measurement = PerformanceMeasurement.start('transit.nearby_stops');
    final db = await _database();
    final latitudeDelta = radiusMeters / 111320;
    final longitudeDelta =
        radiusMeters /
        (111320 * math.cos(latitude * math.pi / 180).abs().clamp(.01, 1));
    final rows = await db.query(
      'stops',
      where: 'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      whereArgs: [
        latitude - latitudeDelta,
        latitude + latitudeDelta,
        longitude - longitudeDelta,
        longitude + longitudeDelta,
      ],
    );
    final candidates =
        rows
            .map(_stop)
            .map(
              (stop) => (
                stop: stop,
                distance: _distance(
                  latitude,
                  longitude,
                  stop.latitude,
                  stop.longitude,
                ),
              ),
            )
            .where((item) => item.distance <= radiusMeters)
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
    final result = candidates.map((item) => item.stop).toList(growable: false);
    measurement.finish(details: 'results=${result.length}');
    return result;
  }

  @override
  Future<List<Stop>> searchStops(String query, {int limit = 25}) async {
    final normalizedQuery = query
        .trim()
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    if (normalizedQuery.isEmpty || limit <= 0) return const [];
    final rows = await (await _database()).query(
      'stops',
      where: "name LIKE ? ESCAPE '\\'",
      whereArgs: ['%$normalizedQuery%'],
      orderBy: 'name COLLATE NOCASE',
      limit: limit.clamp(1, 100),
    );
    return rows.map(_stop).toList(growable: false);
  }

  @override
  Future<Stop?> stopById(String id) async {
    final rows = await (await _database()).query(
      'stops',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _stop(rows.single);
  }

  @override
  Future<List<Route>> routesForStop(String stopId) async {
    final rows = await (await _database()).rawQuery(
      'SELECT DISTINCT r.* FROM routes r '
      'JOIN trips t ON t.route_id = r.id '
      'JOIN pattern_stops ps ON ps.pattern_id = t.pattern_id '
      'WHERE ps.stop_id = ?',
      [stopId],
    );
    return rows.map(_route).toList(growable: false);
  }

  @override
  Future<Map<String, List<Route>>> routesForStops(Set<String> stopIds) async {
    if (stopIds.isEmpty) return const {};
    final db = await _database();
    final routesByStop = <String, Map<String, Route>>{};
    for (final chunk in _chunks(stopIds)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT DISTINCT ps.stop_id, r.id, r.short_name, r.long_name, '
        'r.color, r.text_color FROM routes r '
        'JOIN trips t ON t.route_id = r.id '
        'JOIN pattern_stops ps ON ps.pattern_id = t.pattern_id '
        'WHERE ps.stop_id IN ($placeholders) '
        'ORDER BY ps.stop_id, r.short_name',
        chunk.toList(),
      );
      for (final row in rows) {
        final stopId = row['stop_id'] as String;
        final route = _route(row);
        routesByStop.putIfAbsent(stopId, () => <String, Route>{})[route.id] =
            route;
      }
    }
    return {
      for (final stopId in stopIds)
        stopId:
            routesByStop[stopId]?.values.toList(growable: false) ??
            const <Route>[],
    };
  }

  @override
  Future<Route?> routeById(String id) async {
    final rows = await (await _database()).query(
      'routes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _route(rows.single);
  }

  @override
  Future<List<RouteVariant>> variantsForRoute(String routeId) async {
    final rows = await (await _database()).query(
      'variants',
      where: 'route_id = ?',
      whereArgs: [routeId],
    );
    return rows.map(_variant).toList(growable: false);
  }

  @override
  Future<RouteVariant?> variantByExternalId(int externalVariantId) async {
    final rows = await (await _database()).query(
      'variants',
      where: 'external_variant_id = ?',
      whereArgs: [externalVariantId],
      limit: 1,
    );
    return rows.isEmpty ? null : _variant(rows.single);
  }

  @override
  Future<Shape?> shapeForVariant(String variantId) async {
    final db = await _database();
    final variants = await db.query(
      'variants',
      columns: ['shape_id'],
      where: 'id = ?',
      whereArgs: [variantId],
      limit: 1,
    );
    final id = variants.firstOrNull?['shape_id'] as String?;
    if (id == null || id.isEmpty) return null;
    final rows = await db.query(
      'shapes',
      where: 'shape_id = ?',
      whereArgs: [id],
      orderBy: 'sequence ASC',
    );
    return Shape(
      id: id,
      points: rows
          .map(
            (row) => ShapePoint(
              (row['lat'] as num).toDouble(),
              (row['lon'] as num).toDouble(),
              row['sequence'] as int,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<List<Stop>> stopsForVariant(String variantId) async {
    final db = await _database();
    final patternRows = await db.rawQuery(
      'SELECT t.pattern_id, COUNT(*) as cnt '
      'FROM trips t '
      'WHERE t.variant_id = ? AND t.pattern_id IS NOT NULL '
      'GROUP BY t.pattern_id '
      'ORDER BY cnt DESC '
      'LIMIT 1',
      [variantId],
    );
    if (patternRows.isEmpty) return const [];
    final patternId = patternRows.first['pattern_id'] as String;

    final rows = await db.rawQuery(
      'SELECT s.id, s.name, s.lat, s.lon, s.code FROM pattern_stops ps '
      'JOIN stops s ON s.id = ps.stop_id '
      'WHERE ps.pattern_id = ? '
      'ORDER BY ps.ordinal ASC',
      [patternId],
    );
    return rows.map(_stop).toList(growable: false);
  }

  @override
  Future<List<DateTime>> upcomingDeparturesForVariant(
    String variantId,
    DateTime now, {
    int limit = 10,
  }) async {
    final db = await _database();
    final rows = await db.query(
      'trips',
      columns: ['id', 'service_id', 'start_secs'],
      where: 'variant_id = ? AND start_secs IS NOT NULL',
      whereArgs: [variantId],
      orderBy: 'start_secs ASC',
    );
    if (rows.isEmpty) return const [];

    final calendars = await db.query('calendars');
    final calendarById = <String, ServiceCalendar>{};
    for (final row in calendars) {
      final service = row['service_id'] as String;
      final exceptionRows = await db.query(
        'calendar_exceptions',
        where: 'service_id = ?',
        whereArgs: [service],
      );
      final additions = <DateTime>{}, removals = <DateTime>{};
      for (final exception in exceptionRows) {
        final value = DateTime.parse(exception['date'] as String);
        (exception['type'] == 1 ? additions : removals).add(
          DateTime(value.year, value.month, value.day),
        );
      }
      calendarById[service] = ServiceCalendar(
        serviceId: service,
        startDate: DateTime.parse(row['start_date'] as String),
        endDate: DateTime.parse(row['end_date'] as String),
        weekdays: (row['weekdays'] as String)
            .split(',')
            .where((day) => day.isNotEmpty)
            .map(int.parse)
            .toSet(),
        addedDates: additions,
        removedDates: removals,
      );
    }

    final serviceDay = DateTime(now.year, now.month, now.day);
    final departures = <DateTime>{};
    for (final row in rows) {
      final service = calendarById[row['service_id'] as String];
      if (service == null) continue;
      final startSecs = row['start_secs'] as int?;
      if (startSecs == null) continue;
      for (var offset = -1; offset <= 0; offset++) {
        final day = serviceDay.add(Duration(days: offset));
        if (!service.activeOn(day)) continue;
        final dep = day.add(Duration(seconds: startSecs));
        if (!dep.isBefore(now)) {
          departures.add(dep);
        }
      }
    }
    final sorted = departures.toList()..sort();
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<List<UpcomingDeparture>> upcomingDepartures(
    String stopId,
    DateTime now, {
    int limit = 10,
  }) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT t.id AS trip_id, ps.stop_id, t.start_secs, '
      'ps.arrival_offset_secs, ps.departure_offset_secs, ps.ordinal AS sequence, '
      't.route_id, t.service_id, t.variant_id, t.headsign '
      'FROM pattern_stops ps '
      'JOIN trips t ON t.pattern_id = ps.pattern_id '
      'WHERE ps.stop_id = ?',
      [stopId],
    );
    final calendars = await db.query('calendars');
    final calendarById = <String, ServiceCalendar>{};
    for (final row in calendars) {
      final service = row['service_id'] as String;
      final exceptionRows = await db.query(
        'calendar_exceptions',
        where: 'service_id = ?',
        whereArgs: [service],
      );
      final additions = <DateTime>{}, removals = <DateTime>{};
      for (final exception in exceptionRows) {
        final value = DateTime.parse(exception['date'] as String);
        (exception['type'] == 1 ? additions : removals).add(
          DateTime(value.year, value.month, value.day),
        );
      }
      calendarById[service] = ServiceCalendar(
        serviceId: service,
        startDate: DateTime.parse(row['start_date'] as String),
        endDate: DateTime.parse(row['end_date'] as String),
        weekdays: (row['weekdays'] as String)
            .split(',')
            .where((day) => day.isNotEmpty)
            .map(int.parse)
            .toSet(),
        addedDates: additions,
        removedDates: removals,
      );
    }
    final serviceDay = DateTime(now.year, now.month, now.day);
    final results = <UpcomingDeparture>[];
    for (final row in rows) {
      final service = calendarById[row['service_id'] as String];
      if (service == null) continue;
      final startSecs = row['start_secs'] as int?;
      final departureOffset = row['departure_offset_secs'] as int?;
      if (startSecs == null || departureOffset == null) continue;
      final trip = Trip(
        id: row['trip_id'] as String,
        routeId: row['route_id'] as String,
        serviceId: row['service_id'] as String,
        variantId: row['variant_id'] as String,
        headsign: row['headsign'] as String? ?? '',
      );
      final time = StopTime(
        tripId: trip.id,
        stopId: row['stop_id'] as String,
        arrivalSeconds: startSecs + (row['arrival_offset_secs'] as int),
        departureSeconds: startSecs + departureOffset,
        sequence: row['sequence'] as int,
      );
      for (var offset = -1; offset <= 0; offset++) {
        final day = serviceDay.add(Duration(days: offset));
        if (!service.activeOn(day)) continue;
        final departure = day.add(Duration(seconds: time.departureSeconds));
        if (!departure.isBefore(now)) {
          results.add(
            UpcomingDeparture(trip: trip, stopTime: time, departure: departure),
          );
        }
      }
    }
    results.sort((a, b) => a.departure.compareTo(b.departure));
    return results.take(limit).toList(growable: false);
  }

  @override
  Future<TransitScheduleData> scheduleForStops(
    Set<String> stopIds, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    if (stopIds.isEmpty) return const TransitScheduleData();
    if (windowStart != null &&
        windowEnd != null &&
        windowEnd.isBefore(windowStart)) {
      return const TransitScheduleData();
    }
    final db = await _database();
    final tripIds = <String>{};
    final earliestTripStart = windowStart?.subtract(const Duration(hours: 6));
    final scheduleDays = <DateTime>[];
    if (earliestTripStart != null && windowEnd != null) {
      final firstServiceDay = DateTime(
        earliestTripStart.year,
        earliestTripStart.month,
        earliestTripStart.day,
      ).subtract(const Duration(days: 1));
      final lastServiceDay = DateTime(
        windowEnd.year,
        windowEnd.month,
        windowEnd.day,
      );
      for (
        var day = firstServiceDay;
        !day.isAfter(lastServiceDay);
        day = day.add(const Duration(days: 1))
      ) {
        scheduleDays.add(day);
      }
    }
    for (final chunk in _chunks(stopIds)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      final List<Map<String, Object?>> rows;
      if (earliestTripStart == null || windowEnd == null) {
        rows = await db.rawQuery(
          'SELECT DISTINCT t.id FROM pattern_stops ps '
          'JOIN trips t ON t.pattern_id = ps.pattern_id '
          'WHERE ps.stop_id IN ($placeholders)',
          chunk.toList(),
        );
      } else {
        final dayClauses = <String>[];
        final arguments = <Object?>[...chunk];
        for (final day in scheduleDays) {
          final startSeconds = math.max(
            0,
            earliestTripStart.difference(day).inSeconds,
          );
          final endSeconds = windowEnd.difference(day).inSeconds;
          if (endSeconds < startSeconds) continue;
          final date = _dateKey(day);
          dayClauses.add(
            '''(t.start_secs BETWEEN ? AND ? AND
            ((substr(c.start_date,1,10) <= ? AND
            substr(c.end_date,1,10) >= ? AND
            instr(',' || c.weekdays || ',', ?) > 0) OR
            EXISTS (SELECT 1 FROM calendar_exceptions add_date
            WHERE add_date.service_id = t.service_id
            AND substr(add_date.date,1,10) = ? AND add_date.type = 1))
            AND NOT EXISTS (SELECT 1 FROM calendar_exceptions remove_date
            WHERE remove_date.service_id = t.service_id
            AND substr(remove_date.date,1,10) = ? AND remove_date.type = 2))''',
          );
          arguments.addAll([
            startSeconds,
            endSeconds,
            date,
            date,
            ',${day.weekday},',
            date,
            date,
          ]);
        }
        if (dayClauses.isEmpty) continue;
        rows = await db.rawQuery(
          'SELECT DISTINCT t.id FROM pattern_stops ps '
          'JOIN trips t ON t.pattern_id = ps.pattern_id '
          'JOIN calendars c ON c.service_id = t.service_id '
          'WHERE ps.stop_id IN ($placeholders) '
          'AND (${dayClauses.join(' OR ')})',
          arguments,
        );
      }
      tripIds.addAll(rows.map((row) => row['id'] as String));
    }
    if (tripIds.isEmpty) return const TransitScheduleData();

    final tripRows = await _queryByIds(db, 'trips', 'id', tripIds);
    final serviceIds = tripRows
        .map((row) => row['service_id'] as String)
        .toSet();
    final routeIds = tripRows.map((row) => row['route_id'] as String).toSet();
    final variantIds = tripRows
        .map((row) => row['variant_id'] as String)
        .toSet();

    final stopTimeRows = <Map<String, Object?>>[];
    for (final chunk in _chunks(tripIds)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      stopTimeRows.addAll(
        await db.rawQuery(
          'SELECT t.id AS trip_id, ps.stop_id, t.start_secs, '
          'ps.arrival_offset_secs, ps.departure_offset_secs, ps.ordinal AS sequence '
          'FROM pattern_stops ps '
          'JOIN trips t ON t.pattern_id = ps.pattern_id '
          'WHERE t.id IN ($placeholders)',
          chunk.toList(),
        ),
      );
    }
    final calendarRows = await _queryByIds(
      db,
      'calendars',
      'service_id',
      serviceIds,
    );
    final exceptionRows = await _queryByIds(
      db,
      'calendar_exceptions',
      'service_id',
      serviceIds,
    );
    final includedStopIds = stopTimeRows
        .map((row) => row['stop_id'] as String)
        .toSet();
    final stops = await _queryByIds(db, 'stops', 'id', includedStopIds);
    final routes = await _queryByIds(db, 'routes', 'id', routeIds);
    final variants = await _queryByIds(db, 'variants', 'id', variantIds);

    final mappingRows = (
      tripRows: tripRows,
      stopTimeRows: stopTimeRows,
      calendarRows: calendarRows,
      exceptionRows: exceptionRows,
      stops: stops,
      routes: routes,
      variants: variants,
    );
    return Isolate.run(() => _mapTransitScheduleRows(mappingRows));
  }

  @override
  Future<FeedStatus> feedStatus() async {
    final rows = await (await _database()).query('feed_metadata', limit: 1);
    if (rows.isEmpty) return const FeedStatus();
    final row = rows.single;
    final validUntil = row['valid_until'] == null
        ? null
        : DateTime.tryParse(row['valid_until'] as String);
    return FeedStatus(
      source: row['source'] as String? ?? '',
      version: row['version'] as String? ?? '',
      downloadedAt: DateTime.tryParse(row['downloaded_at'] as String? ?? ''),
      validUntil: validUntil,
      etag: row['etag'] as String?,
      stopCount: row['stop_count'] as int? ?? 0,
      routeCount: row['route_count'] as int? ?? 0,
      variantCount: row['variant_count'] as int? ?? 0,
      tripCount: row['trip_count'] as int? ?? 0,
      stopTimeCount: row['stop_time_count'] as int? ?? 0,
      shapePointCount: row['shape_point_count'] as int? ?? 0,
      calendarCount: row['calendar_count'] as int? ?? 0,
      synthetic: row['synthetic'] == 1,
      warningCount: row['warning_count'] as int? ?? 0,
      stale: isFeedExpired(validUntil, DateTime.now()),
    );
  }
}

TransitScheduleData _mapTransitScheduleRows(
  ({
    List<Map<String, Object?>> tripRows,
    List<Map<String, Object?>> stopTimeRows,
    List<Map<String, Object?>> calendarRows,
    List<Map<String, Object?>> exceptionRows,
    List<Map<String, Object?>> stops,
    List<Map<String, Object?>> routes,
    List<Map<String, Object?>> variants,
  })
  rows,
) {
  final trips = rows.tripRows
      .map(
        (row) => Trip(
          id: row['id'] as String,
          routeId: row['route_id'] as String,
          serviceId: row['service_id'] as String,
          variantId: row['variant_id'] as String,
          headsign: row['headsign'] as String? ?? '',
          patternId: row['pattern_id'] as String?,
          startSecs: row['start_secs'] as int?,
        ),
      )
      .toList(growable: false);
  final stopTimes = rows.stopTimeRows
      .map(
        (row) => StopTime(
          tripId: row['trip_id'] as String,
          stopId: row['stop_id'] as String,
          arrivalSeconds:
              (row['start_secs'] as int) + (row['arrival_offset_secs'] as int),
          departureSeconds:
              (row['start_secs'] as int) +
              (row['departure_offset_secs'] as int),
          sequence: row['sequence'] as int,
        ),
      )
      .toList(growable: false);
  final exceptionsByService = <String, List<Map<String, Object?>>>{};
  for (final row in rows.exceptionRows) {
    exceptionsByService
        .putIfAbsent(row['service_id'] as String, () => [])
        .add(row);
  }
  final calendars = rows.calendarRows
      .map((row) {
        final serviceId = row['service_id'] as String;
        final additions = <DateTime>{};
        final removals = <DateTime>{};
        for (final exception in exceptionsByService[serviceId] ?? const []) {
          final date = DateTime.parse(exception['date'] as String);
          (exception['type'] == 1 ? additions : removals).add(
            DateTime(date.year, date.month, date.day),
          );
        }
        return ServiceCalendar(
          serviceId: serviceId,
          startDate: DateTime.parse(row['start_date'] as String),
          endDate: DateTime.parse(row['end_date'] as String),
          weekdays: (row['weekdays'] as String)
              .split(',')
              .where((day) => day.isNotEmpty)
              .map(int.parse)
              .toSet(),
          addedDates: additions,
          removedDates: removals,
        );
      })
      .toList(growable: false);

  return TransitScheduleData(
    stops: rows.stops.map(_stop).toList(growable: false),
    routes: rows.routes.map(_route).toList(growable: false),
    variants: rows.variants.map(_variant).toList(growable: false),
    trips: trips,
    stopTimes: stopTimes,
    calendars: calendars,
  );
}

Future<List<Map<String, Object?>>> _queryByIds(
  DatabaseExecutor db,
  String table,
  String column,
  Iterable<String> ids,
) async {
  final rows = <Map<String, Object?>>[];
  for (final chunk in _chunks(ids)) {
    if (chunk.isEmpty) continue;
    final placeholders = List.filled(chunk.length, '?').join(',');
    rows.addAll(
      await db.rawQuery(
        'SELECT * FROM $table WHERE $column IN ($placeholders)',
        chunk.toList(),
      ),
    );
  }
  return rows;
}

Iterable<List<String>> _chunks(
  Iterable<String> values, [
  int size = 400,
]) sync* {
  var chunk = <String>[];
  for (final value in values) {
    chunk.add(value);
    if (chunk.length == size) {
      yield chunk;
      chunk = <String>[];
    }
  }
  if (chunk.isNotEmpty) yield chunk;
}

String _dateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Stop _stop(Map<String, Object?> row) => Stop(
  id: row['id'] as String,
  name: row['name'] as String,
  latitude: (row['lat'] as num).toDouble(),
  longitude: (row['lon'] as num).toDouble(),
  code: row['code'] as String? ?? '',
);
Route _route(Map<String, Object?> row) => Route(
  id: row['id'] as String,
  shortName: row['short_name'] as String? ?? '',
  longName: row['long_name'] as String? ?? '',
  color: row['color'] as String? ?? '',
  textColor: row['text_color'] as String? ?? '',
);
RouteVariant _variant(Map<String, Object?> row) => RouteVariant(
  id: row['id'] as String,
  routeId: row['route_id'] as String,
  directionId: row['direction_id'] as String? ?? '',
  destination: row['destination'] as String? ?? '',
  shapeId: row['shape_id'] as String?,
  externalVariantId: row['external_variant_id'] as int?,
);
double _distance(double a, double b, double c, double d) {
  final p1 = a * math.pi / 180,
      p2 = c * math.pi / 180,
      dp = (c - a) * math.pi / 180,
      dl = (d - b) * math.pi / 180;
  final h =
      math.pow(math.sin(dp / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 12742000 * math.asin(math.sqrt(h));
}
