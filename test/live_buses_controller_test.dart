import 'dart:async';

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
  Future<RealtimeSnapshot> fetch({Set<String>? lines}) async {
    calls++;
    if (fail) {
      throw const FormatException('offline');
    }
    return snapshot;
  }
}

class _PendingBusSource implements RealtimeBusSource {
  final Completer<RealtimeSnapshot> completer = Completer<RealtimeSnapshot>();

  @override
  Future<RealtimeSnapshot> fetch({Set<String>? lines}) => completer.future;
}

class _FailAfterSnapshotSource implements RealtimeBusSource {
  _FailAfterSnapshotSource(this.snapshot);

  final RealtimeSnapshot snapshot;
  var calls = 0;

  @override
  Future<RealtimeSnapshot> fetch({Set<String>? lines}) async {
    calls++;
    if (calls > 1) throw const FormatException('upstream unavailable');
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

  test('deduplicates buses by busCode keeping the most recent position', () {
    BusPosition bus(int busCode, int variantId, DateTime receivedAt) =>
        BusPosition(
          sourceId: 'src-$busCode-$variantId',
          companyCode: 1,
          busCode: busCode,
          variantId: variantId,
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
          receivedAt: receivedAt,
        );

    final state = LiveBusesState(
      positions: [
        // El 266 aparece con las variantes 883 y 888: debe mostrarse una vez.
        bus(266, 883, DateTime(2026, 6, 1, 8, 0)),
        bus(266, 888, DateTime(2026, 6, 1, 8, 1)),
        bus(266, 888, DateTime(2026, 6, 1, 8, 2)),
        bus(101, 1, DateTime(2026, 6, 1, 8, 3)),
      ],
      visibleBounds: const LiveBusesBounds(
        minLatitude: -35,
        maxLatitude: -34,
        minLongitude: -57,
        maxLongitude: -56,
      ),
    );

    final positions = state.filteredPositions();
    expect(positions, hasLength(2));
    expect(positions.where((p) => p.busCode == 266), hasLength(1));
    // La conservada es la más reciente.
    expect(
      positions.firstWhere((p) => p.busCode == 266).receivedAt,
      DateTime(2026, 6, 1, 8, 2),
    );
  });

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

  test('discard an in-flight response after live buses are disabled', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(liveBusesControllerProvider.notifier);
    final source = _PendingBusSource();
    notifier.attachSource(source, pollInterval: const Duration(seconds: 1));

    notifier.setEnabled(false);
    source.completer.complete(
      const RealtimeSnapshot(
        positions: [],
        discardedCount: 0,
        discardReasons: {},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(liveBusesControllerProvider);
    expect(state.positions, isEmpty);
    expect(state.lastUpdatedAt, isNull);
    expect(state.isPolling, isFalse);
  });
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

  test('retains buses and hides the banner until repeated failures', () async {
    final snapshot = RealtimeSnapshot(
      positions: [
        BusPosition(
          sourceId: 'bus1',
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
          receivedAt: DateTime(2026, 6, 1, 8),
        ),
      ],
      discardedCount: 0,
      discardReasons: const {},
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(liveBusesControllerProvider.notifier);
    final source = _FailAfterSnapshotSource(snapshot);
    notifier.attachSource(source, pollInterval: const Duration(hours: 1));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(liveBusesControllerProvider).positions, hasLength(1));

    await notifier.refreshNow();
    var state = container.read(liveBusesControllerProvider);
    expect(state.positions, hasLength(1));
    expect(state.consecutiveFailures, 1);
    expect(state.error, contains('upstream unavailable'));
    expect(state.shouldShowError, isFalse);

    await notifier.refreshNow();
    state = container.read(liveBusesControllerProvider);
    expect(state.positions, hasLength(1));
    expect(state.consecutiveFailures, 2);
    expect(state.shouldShowError, isTrue);
  });
}
