import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/gtfs_parser.dart';
import 'package:rumbo/features/stops_and_lines/data/stm_linevariant_catalog.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('links all installed GTFS variants to the captured STM catalog', () {
    final catalog = StmLineVariantCatalog.fromJson(
      jsonDecode(
        File('test/fixtures/stm_linevariants_2026-11-22.json')
            .readAsStringSync(),
      ),
    );
    final db = sqlite3.open(
      'assets/transit_db/rumbo_transit_seed.db',
      mode: OpenMode.readOnly,
    );
    addTearDown(db.close);
    final routes = db
        .select('SELECT id, short_name FROM routes')
        .map(
          (row) => Route(
            id: row['id'] as String,
            shortName: row['short_name'] as String? ?? '',
          ),
        )
        .toList(growable: false);
    final variants = db
        .select(
          'SELECT id, route_id, direction_id, destination, shape_id, '
          'external_variant_id FROM variants',
        )
        .map(
          (row) => RouteVariant(
            id: row['id'] as String,
            routeId: row['route_id'] as String,
            directionId: row['direction_id'] as String? ?? '',
            destination: row['destination'] as String? ?? '',
            shapeId: row['shape_id'] as String?,
            externalVariantId: row['external_variant_id'] as int?,
          ),
        )
        .toList(growable: false);
    final feed = _feed(
      routes: routes,
      variants: variants,
      warnings: [
        for (final variant in variants)
          'Variante ${variant.id}: sin externalVariantId; cruce con tiempo real no disponible.',
      ],
    );

    final result = linkGtfsVariants(feed, catalog);

    expect(catalog.variants, hasLength(2148));
    expect(variants, hasLength(1086));
    expect(result.shapeIdMatches, 1086);
    expect(result.destinationMatches, 0);
    expect(result.unmatchedCount, 0);
    expect(result.linkedCount, 1086);
    expect(result.feed.warningCount, 0);
    expect(
      result.feed.variants.every(
        (variant) =>
            variant.externalVariantId == int.tryParse(variant.shapeId ?? ''),
      ),
      isTrue,
    );
  });

  test(
    'uses a unique line-and-destination match when shape ID is not linked',
    () {
      final result = linkGtfsVariants(
        _feed(
          routes: const [Route(id: 'route', shortName: 'Línea A')],
          variants: const [
            RouteVariant(
              id: 'variant',
              routeId: 'route',
              directionId: '0',
              destination: 'Parque Rodó',
              shapeId: 'shape-without-id',
            ),
          ],
        ),
        const StmLineVariantCatalog([
          StmLineVariant(id: 700, line: 'linea a', destination: 'Parque Rodo'),
        ]),
      );

      expect(result.destinationMatches, 1);
      expect(result.feed.variants.single.externalVariantId, 700);
      expect(result.unmatchedCount, 0);
    },
  );

  test('does not guess when line-and-destination is ambiguous', () {
    final result = linkGtfsVariants(
      _feed(
        routes: const [Route(id: 'route', shortName: 'A')],
        variants: const [
          RouteVariant(
            id: 'variant',
            routeId: 'route',
            directionId: '0',
            destination: 'Centro',
            shapeId: 'unknown',
          ),
        ],
      ),
      const StmLineVariantCatalog([
        StmLineVariant(id: 1, line: 'A', destination: 'Centro'),
        StmLineVariant(id: 2, line: 'A', destination: 'Centro'),
      ]),
    );

    expect(result.ambiguousCount, 1);
    expect(result.unmatchedCount, 1);
    expect(result.feed.variants.single.externalVariantId, isNull);
  });
}

GtfsParseResult _feed({
  List<Route> routes = const [],
  List<RouteVariant> variants = const [],
  List<String> warnings = const [],
}) => GtfsParseResult(
  stops: const [],
  routes: routes,
  variants: variants,
  trips: const [],
  stopTimes: const [],
  stopTimeCount: 0,
  shapes: const [],
  calendars: const [],
  feedInfo: const FeedInfo(),
  warningCount: warnings.length,
  warnings: warnings,
);
