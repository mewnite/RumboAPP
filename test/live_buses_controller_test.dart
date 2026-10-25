import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/presentation/live_buses_controller.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_repository.dart';

class _TestBusSource implements RealtimeBusSource {
  _TestBusSource(this.snapshot, {this.fail = false});

  final RealtimeSnapshot snapshot;
  final bool fail;
  int calls = 0;

  @override
  Future<RealtimeSnapshot> fetch() async {
    calls++;
    if (fail) {
      throw const FormatException('offline');
    }
    return snapshot;
  }
}

void main() {
  test(
    'never returns more than 60 buses even if the configured limit is higher',
    () {
      final positions = List.generate(
        61,
        (index) => BusPosition(
          sourceId: '$index',
          companyCode: 1,
          busCode: index,
          variantId: 1,
          lineLabel: 'A',
          sublineDescription: 'A',
          destinationCode: 'N',
          destinationName: 'Norte',
          lineTypeCode: 1,
          lineTypeName: 'Regular',
          subsystemCode: 1,
          subsystemName: 'STM',
          latitude: -34.9,
          longitude: -56.1,
          speedKmh: 20,
          receivedAt: DateTime(2026, 6, 1, 8, 0),
        ),
      );
      final state = LiveBusesState(
        positions: positions,
        selectedLines: const {'A'},
        visibleBounds: const LiveBusesBounds(
          minLatitude: -35,
          maxLatitude: -34,
          minLongitude: -57,
          maxLongitude: -56,
        ),
        maxMarkers: 1000,
      );

      expect(state.filteredPositions(), hasLength(60));
    },
  );

  test(
    'filters by selected line and visible bounds while capping markers',
    () async {
      final snapshot = RealtimeSnapshot(
        positions: [
          BusPosition(
            sourceId: '1',
            companyCode: 1,
            busCode: 1,
            variantId: 1,
            lineLabel: 'A',
            sublineDescription: 'A',
            destinationCode: 'N',
            destinationName: 'Norte',
            lineTypeCode: 1,
            lineTypeName: 'Regular',
            subsystemCode: 1,
            subsystemName: 'STM',
            latitude: -34.9,
            longitude: -56.1,
            speedKmh: 20,
            receivedAt: DateTime(2026, 6, 1, 8, 0),
          ),
          BusPosition(
            sourceId: '2',
            companyCode: 1,
            busCode: 2,
            variantId: 2,
            lineLabel: 'B',
            sublineDescription: 'B',
            destinationCode: 'S',
            destinationName: 'Sur',
            lineTypeCode: 1,
            lineTypeName: 'Regular',
            subsystemCode: 1,
            subsystemName: 'STM',
            latitude: -34.91,
            longitude: -56.2,
            speedKmh: 16,
            receivedAt: DateTime(2026, 6, 1, 8, 1),
          ),
          BusPosition(
            sourceId: '3',
            companyCode: 1,
            busCode: 3,
            variantId: 3,
            lineLabel: 'A',
            sublineDescription: 'A',
            destinationCode: 'N',
            destinationName: 'Norte',
            lineTypeCode: 1,
            lineTypeName: 'Regular',
            subsystemCode: 1,
            subsystemName: 'STM',
            latitude: -34.92,
            longitude: -56.15,
            speedKmh: 18,
            receivedAt: DateTime(2026, 6, 1, 8, 2),
          ),
          BusPosition(
            sourceId: '4',
            companyCode: 1,
            busCode: 4,
            variantId: 4,
            lineLabel: 'A',
            sublineDescription: 'A',
            destinationCode: 'N',
            destinationName: 'Norte',
            lineTypeCode: 1,
            lineTypeName: 'Regular',
            subsystemCode: 1,
            subsystemName: 'STM',
            latitude: -34.92,
            longitude: -56.3,
            speedKmh: 18,
            receivedAt: DateTime(2026, 6, 1, 8, 3),
          ),
        ],
        discardedCount: 0,
        discardReasons: const {},
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(liveBusesControllerProvider.notifier);
      notifier.attachSource(
        _TestBusSource(snapshot),
        pollInterval: const Duration(milliseconds: 50),
        maxMarkers: 2,
      );
      await notifier.refreshNow();
      notifier.setSelectedLines({'A'});
      notifier.setVisibleBounds(
        const LiveBusesBounds(
          minLatitude: -34.93,
          maxLatitude: -34.89,
          minLongitude: -56.25,
          maxLongitude: -56.05,
        ),
      );

      final filtered = container
          .read(liveBusesControllerProvider)
          .filteredPositions();
      expect(filtered.map((bus) => bus.lineLabel).toList(), ['A', 'A']);
      expect(filtered.map((bus) => bus.sourceId), ['3', '1']);
      expect(
        container
            .read(liveBusesControllerProvider)
            .copyWith(maxMarkers: 1)
            .filteredPositions(),
        hasLength(1),
      );
      notifier
        ..setSelectedLines(const {})
        ..setSelectedVariantIds({2});
      expect(
        container
            .read(liveBusesControllerProvider)
            .filteredPositions()
            .single
            .lineLabel,
        'B',
      );
    },
  );

  test('pauses, resumes and backs off after a failed refresh', () async {
    final snapshot = RealtimeSnapshot(
      positions: [
        BusPosition(
          sourceId: '1',
          companyCode: 1,
          busCode: 1,
          variantId: 1,
          lineLabel: 'A',
          sublineDescription: 'A',
          destinationCode: 'N',
          destinationName: 'Norte',
          lineTypeCode: 1,
          lineTypeName: 'Regular',
          subsystemCode: 1,
          subsystemName: 'STM',
          latitude: -34.9,
          longitude: -56.1,
          speedKmh: 20,
          receivedAt: DateTime(2026, 6, 1, 8, 0),
        ),
      ],
      discardedCount: 0,
      discardReasons: const {},
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(liveBusesControllerProvider.notifier);
    final failingSource = _TestBusSource(snapshot, fail: true);
    notifier.attachSource(
      failingSource,
      pollInterval: const Duration(milliseconds: 2),
      maxMarkers: 5,
    );
    notifier.pausePolling();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(container.read(liveBusesControllerProvider).error, isNotNull);
    expect(
      container.read(liveBusesControllerProvider).retryDelay,
      const Duration(milliseconds: 4),
    );
    expect(failingSource.calls, 1);
    expect(container.read(liveBusesControllerProvider).isPolling, isFalse);

    notifier.resumePolling();
    expect(container.read(liveBusesControllerProvider).isPolling, isTrue);
    expect(failingSource.calls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(failingSource.calls, greaterThan(1));
    notifier.pausePolling();

    final recoveredSource = _TestBusSource(snapshot);
    notifier.attachSource(
      recoveredSource,
      pollInterval: const Duration(seconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(container.read(liveBusesControllerProvider).positions, hasLength(1));
    expect(container.read(liveBusesControllerProvider).error, isNull);
  });
}
