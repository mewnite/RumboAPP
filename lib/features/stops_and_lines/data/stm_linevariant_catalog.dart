import '../domain/transit_models.dart';
import 'gtfs_parser.dart';

class StmLineVariant {
  const StmLineVariant({
    required this.id,
    required this.line,
    required this.destination,
  });

  final int id;
  final String line;
  final String destination;
}

class StmLineVariantCatalog {
  const StmLineVariantCatalog(this.variants);

  factory StmLineVariantCatalog.fromJson(Object? value) {
    if (value is! List<Object?>) {
      throw const FormatException('El catálogo STM no es una lista JSON.');
    }
    return StmLineVariantCatalog(
      value
          .map((row) {
            if (row is! Map<String, Object?> ||
                row['lineVariantId'] is! num ||
                row['line'] is! String) {
              throw const FormatException(
                'Variante del catálogo STM inválida.',
              );
            }
            final id = (row['lineVariantId']! as num).toInt();
            if (id < 0 ||
                (row['lineVariantId']! as num) != id ||
                (row['line']! as String).trim().isEmpty) {
              throw const FormatException('Identificador STM inválido.');
            }
            final destination = row['destination'];
            return StmLineVariant(
              id: id,
              line: row['line']! as String,
              destination: destination is String ? destination : '',
            );
          })
          .toList(growable: false),
    );
  }

  final List<StmLineVariant> variants;
}

class StmVariantLinkResult {
  const StmVariantLinkResult({
    required this.feed,
    required this.explicitMatches,
    required this.shapeIdMatches,
    required this.destinationMatches,
    required this.preservedMatches,
    required this.ambiguousCount,
    required this.unmatchedCount,
  });

  final GtfsParseResult feed;
  final int explicitMatches;
  final int shapeIdMatches;
  final int destinationMatches;
  final int preservedMatches;
  final int ambiguousCount;
  final int unmatchedCount;

  int get linkedCount =>
      explicitMatches + shapeIdMatches + destinationMatches + preservedMatches;
}

StmVariantLinkResult linkGtfsVariants(
  GtfsParseResult feed,
  StmLineVariantCatalog catalog, {
  Map<String, int> preservedIds = const {},
}) {
  final routesById = {for (final route in feed.routes) route.id: route};
  final variantsById = <int, List<StmLineVariant>>{};
  final variantsByLineAndDestination = <String, Set<int>>{};
  for (final item in catalog.variants) {
    variantsById.putIfAbsent(item.id, () => []).add(item);
    final key = _lineDestinationKey(item.line, item.destination);
    if (key.isNotEmpty) {
      variantsByLineAndDestination.putIfAbsent(key, () => <int>{}).add(item.id);
    }
  }

  bool belongsToLine(int id, String line) =>
      variantsById[id]?.any(
        (candidate) =>
            normalizeTransitLabel(candidate.line) ==
            normalizeTransitLabel(line),
      ) ??
      false;

  var shapeIdMatches = 0;
  var explicitMatches = 0;
  var destinationMatches = 0;
  var preservedMatches = 0;
  var ambiguousCount = 0;
  var unmatchedCount = 0;
  final linkedVariants = <RouteVariant>[];

  for (final variant in feed.variants) {
    final line = routesById[variant.routeId]?.shortName ?? '';
    int? externalId;
    var matchSource = '';

    final explicitId = variant.externalVariantId;
    if (explicitId != null && belongsToLine(explicitId, line)) {
      externalId = explicitId;
      matchSource = 'explicit';
    }

    final shapeId = int.tryParse(variant.shapeId ?? '');
    if (externalId == null && shapeId != null && belongsToLine(shapeId, line)) {
      externalId = shapeId;
      matchSource = 'shape';
    }

    final preservedId = preservedIds[variant.id];
    if (externalId == null &&
        preservedId != null &&
        (catalog.variants.isEmpty || belongsToLine(preservedId, line))) {
      externalId = preservedId;
      matchSource = 'preserved';
    }

    if (externalId == null &&
        line.isNotEmpty &&
        variant.destination.isNotEmpty) {
      final candidates =
          variantsByLineAndDestination[_lineDestinationKey(
            line,
            variant.destination,
          )] ??
          const <int>{};
      if (candidates.length == 1) {
        externalId = candidates.single;
        matchSource = 'destination';
      } else if (candidates.length > 1) {
        ambiguousCount++;
      }
    }

    if (externalId == null && catalog.variants.isEmpty) {
      final existingId = variant.externalVariantId;
      if (existingId != null) {
        externalId = existingId;
        matchSource = 'preserved';
      }
    }

    if (externalId == null) {
      unmatchedCount++;
    } else {
      switch (matchSource) {
        case 'explicit':
          explicitMatches++;
        case 'shape':
          shapeIdMatches++;
        case 'destination':
          destinationMatches++;
        case 'preserved':
          preservedMatches++;
      }
    }

    linkedVariants.add(
      RouteVariant(
        id: variant.id,
        routeId: variant.routeId,
        directionId: variant.directionId,
        destination: variant.destination,
        shapeId: variant.shapeId,
        externalVariantId: externalId,
      ),
    );
  }

  final warnings = feed.warnings
      .where(
        (warning) =>
            !warning.contains('sin externalVariantId; cruce con tiempo real'),
      )
      .toList(growable: true);
  for (final variant in linkedVariants) {
    if (variant.externalVariantId == null) {
      warnings.add(
        'Variante ${variant.id}: no se pudo enlazar con el catálogo STM.',
      );
    }
  }

  return StmVariantLinkResult(
    feed: GtfsParseResult(
      stops: feed.stops,
      routes: feed.routes,
      variants: linkedVariants,
      trips: feed.trips,
      stopTimes: feed.stopTimes,
      stopTimeCount: feed.stopTimeCount,
      stopTimesFilePath: feed.stopTimesFilePath,
      shapes: feed.shapes,
      calendars: feed.calendars,
      calendarExceptions: feed.calendarExceptions,
      feedInfo: feed.feedInfo,
      warningCount: warnings.length,
      warnings: warnings,
      patterns: feed.patterns,
      tripPatternIds: feed.tripPatternIds,
    ),
    explicitMatches: explicitMatches,
    shapeIdMatches: shapeIdMatches,
    destinationMatches: destinationMatches,
    preservedMatches: preservedMatches,
    ambiguousCount: ambiguousCount,
    unmatchedCount: unmatchedCount,
  );
}

String normalizeTransitLabel(String value) {
  var normalized = value.toLowerCase();
  const accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
  };
  for (final entry in accents.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _lineDestinationKey(String line, String destination) {
  final normalizedLine = normalizeTransitLabel(line);
  final normalizedDestination = normalizeTransitLabel(destination);
  if (normalizedLine.isEmpty || normalizedDestination.isEmpty) return '';
  return '$normalizedLine|$normalizedDestination';
}
