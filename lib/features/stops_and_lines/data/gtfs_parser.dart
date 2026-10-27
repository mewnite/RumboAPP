import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../domain/transit_models.dart';
import 'gtfs_csv.dart';

class GtfsParseResult {
  const GtfsParseResult({
    required this.stops,
    required this.routes,
    required this.variants,
    required this.trips,
    required this.stopTimes,
    required this.stopTimeCount,
    this.stopTimesFilePath,
    required this.shapes,
    required this.calendars,
    this.calendarExceptions = const [],
    required this.feedInfo,
    required this.warningCount,
    required this.warnings,
    this.patterns = const [],
    this.tripPatternIds = const {},
  });
  final List<Stop> stops;
  final List<Route> routes;
  final List<RouteVariant> variants;
  final List<Trip> trips;
  final List<StopTime> stopTimes;
  final int stopTimeCount;
  final String? stopTimesFilePath;
  final List<Shape> shapes;
  final List<Calendar> calendars;
  final List calendarExceptions;
  final GtfsFeedInfo feedInfo;
  final int warningCount;
  final List<String> warnings;
  final List<TripPattern>? patterns;
  final Map<String, String> tripPatternIds;
}

GtfsParseResult parseGtfsZip(Uint8List bytes) {
  return _parseGtfsZip(bytes);
}

/// Parses in an isolate and writes valid stop-time rows to a temporary JSONL
/// file instead of returning millions of Dart objects across the isolate port.
GtfsParseResult parseGtfsZipToFile(Map<String, Object> input) {
  final bytes = input['bytes']! as Uint8List;
  final path = input['path']! as String;
  return _parseGtfsZip(bytes, stopTimesFilePath: path);
}

/// Parses a downloaded ZIP from disk in an isolate. The large stop_times table
/// is decompressed to disk and read in bounded chunks, then serialized as
/// JSONL for the transactional SQLite importer.
GtfsParseResult parseGtfsZipFileToFile(Map<String, Object> input) {
  final zipPath = input['zipPath']! as String;
  final stopTimesPath = input['stopTimesPath']! as String;
  final spoolPath = input['spoolPath']! as String;
  final archiveInput = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(archiveInput, verify: true);
    final files = <String, String>{};
    var foundStopTimes = false;
    try {
      for (final item in archive.files) {
        final basename = item.name.split('/').last;
        if (!item.isFile ||
            !(basename.endsWith('.txt') || basename == 'variant_map.csv')) {
          continue;
        }
        if (basename == 'stop_times.txt') {
          final output = OutputFileStream(stopTimesPath);
          try {
            item.writeContent(output, freeMemory: true);
          } finally {
            output.closeSync();
          }
          foundStopTimes = true;
        } else {
          files[basename] = utf8.decode(item.content, allowMalformed: true);
        }
      }
      if (!foundStopTimes) files.remove('stop_times.txt');
      return _parseGtfsFiles(
        files,
        stopTimesFilePath: spoolPath,
        stopTimesCsvPath: foundStopTimes ? stopTimesPath : null,
      );
    } finally {
      for (final item in archive.files) {
        item.closeSync();
      }
    }
  } finally {
    archiveInput.closeSync();
  }
}

GtfsParseResult _parseGtfsZip(Uint8List bytes, {String? stopTimesFilePath}) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final files = <String, String>{};
  for (final item in archive.files) {
    final basename = item.name.split('/').last;
    if (item.isFile &&
        (basename.endsWith('.txt') || basename == 'variant_map.csv')) {
      files[basename] = utf8.decode(
        item.content as List<int>,
        allowMalformed: true,
      );
    }
  }
  return _parseGtfsFiles(files, stopTimesFilePath: stopTimesFilePath);
}

GtfsParseResult _parseGtfsFiles(
  Map<String, String> files, {
  String? stopTimesFilePath,
  String? stopTimesCsvPath,
}) {
  const required = ['stops.txt', 'routes.txt', 'trips.txt', 'stop_times.txt'];
  final absent = required
      .where(
        (f) => f == 'stop_times.txt'
            ? stopTimesCsvPath == null && !files.containsKey(f)
            : !files.containsKey(f),
      )
      .toList();
  if (absent.isNotEmpty) {
    throw FormatException('Faltan archivos requeridos: ${absent.join(', ')}');
  }
  if (!files.containsKey('calendar.txt') &&
      !files.containsKey('calendar_dates.txt')) {
    throw const FormatException('Falta calendar.txt o calendar_dates.txt');
  }
  var warnings = <String>[];
  final tables = <String, CsvTable>{
    for (final entry in files.entries) entry.key: CsvTable.parse(entry.value),
  };
  if (stopTimesCsvPath != null) {
    tables['stop_times.txt'] = CsvTable.fromFile(File(stopTimesCsvPath));
  }
  Iterable<Map<String, String>> rows(String name) =>
      tables[name]?.records ?? const <Map<String, String>>[];
  String v(Map<String, String> r, String k) => r[k] ?? '';
  double? d(String s) => double.tryParse(s);
  int? n(String s) => int.tryParse(s);
  DateTime? date(String s) => s.length == 8
      ? DateTime.tryParse(
          '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}',
        )
      : null;
  final stops = <Stop>[];
  for (final r in rows('stops.txt')) {
    final lat = d(v(r, 'stop_lat')), lon = d(v(r, 'stop_lon'));
    if (v(r, 'stop_id').isEmpty ||
        v(r, 'stop_name').isEmpty ||
        lat == null ||
        lon == null) {
      warnings.add('stops.txt: fila inválida omitida');
      continue;
    }
    stops.add(
      Stop(
        id: v(r, 'stop_id'),
        name: v(r, 'stop_name'),
        latitude: lat,
        longitude: lon,
        code: v(r, 'stop_code'),
        description: v(r, 'stop_desc'),
      ),
    );
  }
  final routes = <Route>[];
  for (final r in rows('routes.txt')) {
    if (v(r, 'route_id').isEmpty) {
      warnings.add('routes.txt: fila inválida omitida');
      continue;
    }
    routes.add(
      Route(
        id: v(r, 'route_id'),
        shortName: v(r, 'route_short_name'),
        longName: v(r, 'route_long_name'),
        color: v(r, 'route_color'),
        textColor: v(r, 'route_text_color'),
      ),
    );
  }
  final shapesById = <String, List<ShapePoint>>{};
  for (final r in rows('shapes.txt')) {
    final lat = d(v(r, 'shape_pt_lat')),
        lon = d(v(r, 'shape_pt_lon')),
        seq = n(v(r, 'shape_pt_sequence'));
    if (v(r, 'shape_id').isEmpty || lat == null || lon == null || seq == null) {
      warnings.add('shapes.txt: fila inválida omitida');
      continue;
    }
    shapesById
        .putIfAbsent(v(r, 'shape_id'), () => [])
        .add(ShapePoint(lat, lon, seq));
  }
  final shapes = shapesById.entries
      .map(
        (e) => Shape(
          id: e.key,
          points: e.value..sort((a, b) => a.sequence.compareTo(b.sequence)),
        ),
      )
      .toList();
  final trips = <Trip>[];
  final tripById = <String, Trip>{};
  final variants = <RouteVariant>[];
  final variantByKey = <String, String>{};
  final tripVariantMap = <String, int>{};
  final shapeVariantMap = <String, int>{};
  for (final r in rows('variant_map.csv')) {
    final external = n(v(r, 'external_variant_id'));
    if (external == null ||
        (v(r, 'trip_id').isEmpty && v(r, 'shape_id').isEmpty)) {
      warnings.add('variant_map.csv: fila inválida omitida');
      continue;
    }
    if (v(r, 'trip_id').isNotEmpty) tripVariantMap[v(r, 'trip_id')] = external;
    if (v(r, 'shape_id').isNotEmpty) {
      shapeVariantMap[v(r, 'shape_id')] = external;
    }
  }
  final variantIndexes = <String, int>{};
  for (final r in rows('trips.txt')) {
    final id = v(r, 'trip_id'),
        route = v(r, 'route_id'),
        service = v(r, 'service_id');
    if (id.isEmpty || route.isEmpty || service.isEmpty) {
      warnings.add('trips.txt: fila inválida omitida');
      continue;
    }
    final direction = v(r, 'direction_id'), shape = v(r, 'shape_id');
    final key = '$route|$direction|$shape';
    final external =
        n(v(r, 'variant_id')) ?? tripVariantMap[id] ?? shapeVariantMap[shape];
    final variant = variantByKey.putIfAbsent(key, () {
      final value = '$route:$direction:${shape.isEmpty ? 'sin-shape' : shape}';
      variants.add(
        RouteVariant(
          id: value,
          routeId: route,
          directionId: direction,
          destination: v(r, 'trip_headsign'),
          shapeId: shape.isEmpty ? null : shape,
          externalVariantId: external,
        ),
      );
      variantIndexes[value] = variants.length - 1;
      return value;
    });
    final variantIndex = variantIndexes[variant]!;
    if (variants[variantIndex].externalVariantId == null && external != null) {
      final previous = variants[variantIndex];
      variants[variantIndex] = RouteVariant(
        id: previous.id,
        routeId: previous.routeId,
        directionId: previous.directionId,
        destination: previous.destination,
        shapeId: previous.shapeId,
        externalVariantId: external,
      );
    }
    final trip = Trip(
      id: id,
      routeId: route,
      serviceId: service,
      variantId: variant,
      headsign: v(r, 'trip_headsign'),
    );
    tripById[id] = trip;
    trips.add(trip);
  }
  for (final variant in variants) {
    if (variant.externalVariantId == null) {
      warnings.add(
        'Variante ${variant.id}: sin externalVariantId; cruce con tiempo real no disponible.',
      );
    }
  }
  final calendarsById = <String, ServiceCalendar>{};
  for (final r in rows('calendar.txt')) {
    final start = date(v(r, 'start_date')), end = date(v(r, 'end_date'));
    if (v(r, 'service_id').isEmpty || start == null || end == null) {
      warnings.add('calendar.txt: fila inválida omitida');
      continue;
    }
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final days = <int>{};
    for (var i = 0; i < names.length; i++) {
      if (v(r, names[i]) == '1') days.add(i + 1);
    }
    calendarsById[v(r, 'service_id')] = ServiceCalendar(
      serviceId: v(r, 'service_id'),
      startDate: start,
      endDate: end,
      weekdays: days,
    );
  }
  final added = <String, Set<DateTime>>{}, removed = <String, Set<DateTime>>{};
  for (final r in rows('calendar_dates.txt')) {
    final dt = date(v(r, 'date')), id = v(r, 'service_id');
    if (dt == null || id.isEmpty) {
      warnings.add('calendar_dates.txt: fila inválida omitida');
      continue;
    }
    final target = v(r, 'exception_type') == '1'
        ? added
        : v(r, 'exception_type') == '2'
        ? removed
        : null;
    if (target == null) {
      warnings.add('calendar_dates.txt: excepción inválida omitida');
      continue;
    }
    target.putIfAbsent(id, () => {}).add(dt);
  }
  final all = (calendarsById.keys.toSet()
    ..addAll(added.keys)
    ..addAll(removed.keys));
  final calendars = <ServiceCalendar>[];
  for (final id in all) {
    final base = calendarsById[id];
    calendars.add(
      ServiceCalendar(
        serviceId: id,
        startDate: base?.startDate ?? DateTime(1900),
        endDate: base?.endDate ?? DateTime(9999),
        weekdays: base?.weekdays ?? {},
        addedDates: added[id] ?? {},
        removedDates: removed[id] ?? {},
      ),
    );
  }
  final times = <StopTime>[];
  var timeCount = 0;
  final patterns = <TripPattern>{};
  final tripPatternIds = <String, String>{};
  final tripStartSecs = <String, int>{};
  final spool = stopTimesFilePath == null
      ? null
      : File(stopTimesFilePath).openSync(mode: FileMode.writeOnly);
  try {
    var currentTripId = '';
    final currentStops = <StopTime>[];
    final closedTrips = <String>{};
    var unordered = false;

    void emitPattern() {
      if (currentTripId.isEmpty || currentStops.isEmpty) return;
      currentStops.sort((a, b) => a.sequence.compareTo(b.sequence));
      final firstDeparture = currentStops.first.departureSeconds;
      final patternStops = <TripPatternStop>[];
      for (var i = 0; i < currentStops.length; i++) {
        final time = currentStops[i];
        patternStops.add(
          TripPatternStop(
            ordinal: i + 1,
            stopId: time.stopId,
            arrivalOffsetSecs: time.arrivalSeconds - firstDeparture,
            departureOffsetSecs: time.departureSeconds - firstDeparture,
          ),
        );
      }
      final patternKey = patternStops
          .map(
            (ps) =>
                '${ps.stopId}:${ps.arrivalOffsetSecs}:${ps.departureOffsetSecs}',
          )
          .join('|');
      final patternId = sha256.convert(utf8.encode(patternKey)).toString();
      patterns.add(TripPattern(id: patternId, stops: patternStops));
      tripPatternIds[currentTripId] = patternId;
      tripStartSecs[currentTripId] = firstDeparture;
      closedTrips.add(currentTripId);
    }

    for (final r in rows('stop_times.txt')) {
      final arr = parseGtfsTime(v(r, 'arrival_time')),
          dep = parseGtfsTime(v(r, 'departure_time')),
          seq = n(v(r, 'stop_sequence'));
      if (v(r, 'trip_id').isEmpty ||
          v(r, 'stop_id').isEmpty ||
          arr == null ||
          dep == null ||
          seq == null) {
        warnings.add('stop_times.txt: fila inválida omitida');
        continue;
      }
      final tripId = v(r, 'trip_id');
      if (currentTripId.isNotEmpty && tripId != currentTripId) {
        if (closedTrips.contains(tripId)) {
          unordered = true;
        }
        emitPattern();
        currentStops.clear();
      }
      currentTripId = tripId;
      currentStops.add(
        StopTime(
          tripId: tripId,
          stopId: v(r, 'stop_id'),
          arrivalSeconds: arr,
          departureSeconds: dep,
          sequence: seq,
        ),
      );
      timeCount++;
      if (spool == null) {
        times.add(currentStops.last);
      } else {
        spool.writeStringSync(
          '${jsonEncode([tripId, v(r, 'stop_id'), arr, dep, seq])}\n',
        );
      }
    }
    emitPattern();

    if (unordered) {
      warnings.add(
        'stop_times.txt: no ordenado por viaje; se recomienda tabla temporal para agrupar sin mantener todo en memoria.',
      );
    }
  } finally {
    spool?.flushSync();
    spool?.closeSync();
  }

  final updatedTrips = <Trip>[];
  for (final t in trips) {
    updatedTrips.add(
      Trip(
        id: t.id,
        routeId: t.routeId,
        serviceId: t.serviceId,
        variantId: t.variantId,
        headsign: t.headsign,
        patternId: tripPatternIds[t.id],
        startSecs: tripStartSecs[t.id],
      ),
    );
  }

  FeedInfo info = const FeedInfo();
  final infoRows = rows('feed_info.txt');
  if (infoRows.isNotEmpty) {
    final r = infoRows.first;
    info = FeedInfo(
      publisherName: v(r, 'feed_publisher_name'),
      publisherUrl: v(r, 'feed_publisher_url'),
      version: v(r, 'feed_version'),
      startDate: date(v(r, 'feed_start_date')),
      endDate: date(v(r, 'feed_end_date')),
      language: v(r, 'feed_lang'),
      synthetic: v(r, 'feed_publisher_name').contains('sintético'),
    );
  }
  if (info.endDate == null && calendars.isNotEmpty) {
    final latestDate = calendars
        .map((calendar) => calendar.endDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    info = GtfsFeedInfo(
      publisherName: info.publisherName,
      publisherUrl: info.publisherUrl,
      version: info.version,
      startDate: info.startDate,
      endDate: latestDate,
      language: info.language,
      synthetic: info.synthetic,
    );
  }
  for (final entry in tables.entries) {
    if (entry.value.invalidRowCount > 0) {
      warnings.add(
        '${entry.key}: ${entry.value.invalidRowCount} filas CSV inválidas omitidas.',
      );
    }
  }
  return GtfsParseResult(
    stops: stops,
    routes: routes,
    variants: variants,
    trips: updatedTrips,
    stopTimes: times,
    stopTimeCount: timeCount,
    stopTimesFilePath: stopTimesFilePath,
    shapes: shapes,
    calendars: calendars,
    calendarExceptions: const [],
    feedInfo: info,
    warningCount: warnings.length,
    warnings: warnings,
    patterns: patterns.toList(growable: false),
    tripPatternIds: tripPatternIds,
  );
}

/// Computa patrones de viaje a partir de un iterable de [StopTime] sin
/// mantener todos los horarios en memoria: agrupa viaje por viaje y emite el
/// patrón al cerrar cada uno. Si los tiempos no vienen ordenados por viaje,
/// se detecta el desorden y se documenta (ver [GtfsParseResult.warnings]).
///
/// Devuelve los patrones, el mapeo trip_id -> pattern_id y el mapeo
/// trip_id -> start_secs (desfase del primer horario del viaje).
(Iterable<TripPattern>, Map<String, String>, Map<String, int>)
computePatternsFromTimes(Iterable<StopTime> times) {
  final patterns = <TripPattern>[];
  final tripPatternIds = <String, String>{};
  final tripStartSecs = <String, int>{};
  final closedTrips = <String>{};
  var currentTripId = '';
  final currentStops = <StopTime>[];
  var unordered = false;

  void emitPattern() {
    if (currentTripId.isEmpty || currentStops.isEmpty) return;
    currentStops.sort((a, b) => a.sequence.compareTo(b.sequence));
    final firstDeparture = currentStops.first.departureSeconds;
    final patternStops = <TripPatternStop>[];
    for (var i = 0; i < currentStops.length; i++) {
      final time = currentStops[i];
      patternStops.add(
        TripPatternStop(
          ordinal: i + 1,
          stopId: time.stopId,
          arrivalOffsetSecs: time.arrivalSeconds - firstDeparture,
          departureOffsetSecs: time.departureSeconds - firstDeparture,
        ),
      );
    }
    final patternKey = patternStops
        .map(
          (ps) =>
              '${ps.stopId}:${ps.arrivalOffsetSecs}:${ps.departureOffsetSecs}',
        )
        .join('|');
    final patternId = sha256.convert(utf8.encode(patternKey)).toString();
    patterns.add(TripPattern(id: patternId, stops: patternStops));
    tripPatternIds[currentTripId] = patternId;
    tripStartSecs[currentTripId] = firstDeparture;
    closedTrips.add(currentTripId);
  }

  for (final time in times) {
    if (currentTripId.isNotEmpty && time.tripId != currentTripId) {
      if (closedTrips.contains(time.tripId)) {
        unordered = true;
      }
      emitPattern();
      currentStops.clear();
    }
    currentTripId = time.tripId;
    currentStops.add(time);
  }
  emitPattern();

  if (unordered) {
    // El llamador puede decidir usar una tabla temporal si lo necesita.
  }

  return (patterns, tripPatternIds, tripStartSecs);
}
