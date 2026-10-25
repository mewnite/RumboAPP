import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/core/widgets/line_chip.dart';
import 'package:rumbo/features/map/presentation/live_bus_chip.dart';
import 'package:rumbo/features/map/presentation/live_buses_controller.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

void main() {
  final now = DateTime(2026, 10, 25, 12);

  BusPosition bus({
    required String id,
    required String line,
    required int variantId,
    required double latitude,
    required double longitude,
    DateTime? receivedAt,
  }) => BusPosition(
    sourceId: id,
    companyCode: 1,
    busCode: int.parse(id),
    variantId: variantId,
    lineLabel: line,
    sublineDescription: line,
    destinationCode: 'N',
    destinationName: 'Norte',
    lineTypeCode: 1,
    lineTypeName: 'Regular',
    subsystemCode: 1,
    subsystemName: 'STM',
    latitude: latitude,
    longitude: longitude,
    speedKmh: 20,
    receivedAt: receivedAt ?? now,
  );

  test(
    'the live layer only draws selected visible buses and respects the cap',
    () {
      final state = LiveBusesState(
        positions: [
          bus(
            id: '1',
            line: 'A',
            variantId: 1,
            latitude: -34.90,
            longitude: -56.16,
          ),
          bus(
            id: '2',
            line: 'B',
            variantId: 2,
            latitude: -34.90,
            longitude: -56.16,
          ),
          bus(
            id: '3',
            line: 'A',
            variantId: 1,
            latitude: -35.50,
            longitude: -56.16,
          ),
          for (var index = 0; index < 70; index++)
            bus(
              id: '${index + 10}',
              line: 'A',
              variantId: 1,
              latitude: -34.91,
              longitude: -56.17,
              receivedAt: now.subtract(Duration(seconds: index)),
            ),
        ],
        selectedLines: const {'A'},
        selectedVariantIds: const {1},
        visibleBounds: const LiveBusesBounds(
          minLatitude: -35,
          maxLatitude: -34,
          minLongitude: -57,
          maxLongitude: -56,
        ),
        maxMarkers: 60,
      );

      final visible = state.filteredPositions();
      expect(visible, hasLength(60));
      expect(visible.every((position) => position.lineLabel == 'A'), isTrue);
      expect(visible.any((position) => position.sourceId == '2'), isFalse);
      expect(visible.any((position) => position.sourceId == '3'), isFalse);
    },
  );

  testWidgets('stale and unmatched buses use a faded compact chip', (
    tester,
  ) async {
    final fresh = bus(
      id: '1',
      line: 'A',
      variantId: 10,
      latitude: -34.9,
      longitude: -56.1,
    );
    final stale = bus(
      id: '2',
      line: 'A',
      variantId: 10,
      latitude: -34.9,
      longitude: -56.1,
      receivedAt: now.subtract(const Duration(seconds: 90)),
    );
    final unmatched = bus(
      id: '3',
      line: 'A',
      variantId: 99,
      latitude: -34.9,
      longitude: -56.1,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              LiveBusChip(
                key: const ValueKey('fresh'),
                bus: fresh,
                matchedVariantIds: const {10},
                now: now,
              ),
              LiveBusChip(
                key: const ValueKey('stale'),
                bus: stale,
                matchedVariantIds: const {10},
                now: now,
              ),
              LiveBusChip(
                key: const ValueKey('unmatched'),
                bus: unmatched,
                matchedVariantIds: const {10},
                now: now,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    expect(tester.widget<Opacity>(find.byType(Opacity).at(1)).opacity, 0.5);
    expect(tester.widget<Opacity>(find.byType(Opacity).at(2)).opacity, 0.5);
    expect(
      tester
          .widgetList<LineChip>(find.byType(LineChip))
          .every((chip) => chip.compact),
      isTrue,
    );
  });
}
