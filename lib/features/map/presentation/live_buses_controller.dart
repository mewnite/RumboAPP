import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';

class LiveBusesBounds {
  const LiveBusesBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  bool contains(BusPosition position) =>
      position.latitude >= minLatitude &&
      position.latitude <= maxLatitude &&
      position.longitude >= minLongitude &&
      position.longitude <= maxLongitude;
}

class LiveBusesState {
  const LiveBusesState({
    this.positions = const [],
    this.selectedLines = const {},
    this.selectedVariantIds = const {},
    this.visibleBounds,
    this.maxMarkers = 60,
    this.isLoading = false,
    this.isPolling = false,
    this.error,
    this.retryDelay = const Duration(seconds: 15),
    this.lastUpdatedAt,
  });

  final List<BusPosition> positions;
  final Set<String> selectedLines;
  final Set<int> selectedVariantIds;
  final LiveBusesBounds? visibleBounds;
  final int maxMarkers;
  final bool isLoading;
  final bool isPolling;
  final String? error;
  final Duration retryDelay;
  final DateTime? lastUpdatedAt;

  bool get isStale =>
      lastUpdatedAt != null &&
      DateTime.now().difference(lastUpdatedAt!) > const Duration(seconds: 60);

  LiveBusesState copyWith({
    List<BusPosition>? positions,
    Set<String>? selectedLines,
    Set<int>? selectedVariantIds,
    LiveBusesBounds? visibleBounds,
    int? maxMarkers,
    bool? isLoading,
    bool? isPolling,
    String? error,
    Duration? retryDelay,
    DateTime? lastUpdatedAt,
  }) {
    return LiveBusesState(
      positions: positions ?? this.positions,
      selectedLines: selectedLines ?? this.selectedLines,
      selectedVariantIds: selectedVariantIds ?? this.selectedVariantIds,
      visibleBounds: visibleBounds ?? this.visibleBounds,
      maxMarkers: maxMarkers ?? this.maxMarkers,
      isLoading: isLoading ?? this.isLoading,
      isPolling: isPolling ?? this.isPolling,
      error: error,
      retryDelay: retryDelay ?? this.retryDelay,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  List<BusPosition> filteredPositions({
    Set<String>? selectedLines,
    Set<int>? selectedVariantIds,
  }) {
    final lines = selectedLines ?? this.selectedLines;
    final variants = selectedVariantIds ?? this.selectedVariantIds;
    if (visibleBounds == null || (lines.isEmpty && variants.isEmpty)) {
      return const [];
    }
    Iterable<BusPosition> candidates = positions;
    if (lines.isNotEmpty || variants.isNotEmpty) {
      candidates = candidates.where(
        (position) =>
            lines.contains(position.lineLabel) ||
            variants.contains(position.variantId),
      );
    }
    if (visibleBounds != null) {
      candidates = candidates.where(visibleBounds!.contains);
    }
    final sorted = candidates.toList(growable: false)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return sorted.take(maxMarkers.clamp(0, 60)).toList(growable: false);
  }
}

final liveBusesControllerProvider =
    NotifierProvider<LiveBusesController, LiveBusesState>(
      LiveBusesController.new,
    );

class LiveBusesController extends Notifier<LiveBusesState> {
  LiveBusesController();

  RealtimeBusSource? _source;
  Timer? _pollTimer;
  Duration _baseDelay = const Duration(seconds: 15);
  DateTime Function() _clock = DateTime.now;

  @override
  LiveBusesState build() {
    ref.onDispose(disposeController);
    return const LiveBusesState();
  }

  void attachSource(
    RealtimeBusSource source, {
    Duration pollInterval = const Duration(seconds: 15),
    int maxMarkers = 20,
    DateTime Function()? clock,
  }) {
    _source = source;
    _baseDelay = pollInterval;
    _clock = clock ?? DateTime.now;
    state = state.copyWith(
      maxMarkers: maxMarkers.clamp(0, 60),
      isPolling: true,
      retryDelay: pollInterval,
    );
    unawaited(refreshNow());
  }

  void setSelectedLines(Set<String> lines) {
    state = state.copyWith(selectedLines: lines);
  }

  void setSelectedVariantIds(Set<int> variantIds) {
    state = state.copyWith(selectedVariantIds: variantIds);
  }

  void setVisibleBounds(LiveBusesBounds? bounds) {
    state = state.copyWith(visibleBounds: bounds);
  }

  void pausePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = state.copyWith(isPolling: false);
  }

  void resumePolling() {
    if (_source == null) return;
    if (state.isPolling) return;
    state = state.copyWith(isPolling: true);
    _scheduleNextPoll();
  }

  Future<void> refreshNow() async {
    if (_source == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final snapshot = await _source!.fetch();
      final shouldContinuePolling = state.isPolling;
      state = state.copyWith(
        positions: snapshot.positions,
        isLoading: false,
        error: null,
        isPolling: shouldContinuePolling,
        retryDelay: _baseDelay,
        lastUpdatedAt: _clock(),
      );
      if (shouldContinuePolling) _scheduleNextPoll();
    } on Exception catch (error) {
      final shouldContinuePolling = state.isPolling;
      final nextDelay = _nextBackoffDelay();
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
        isPolling: shouldContinuePolling,
        retryDelay: nextDelay,
      );
      if (shouldContinuePolling) _scheduleNextPoll(after: nextDelay);
    }
  }

  void disposeController() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _scheduleNextPoll({Duration? after}) {
    _pollTimer?.cancel();
    if (_source == null || !state.isPolling) return;
    final delay = after ?? state.retryDelay;
    _pollTimer = Timer(delay, () {
      if (!ref.mounted) return;
      unawaited(refreshNow());
    });
  }

  Duration _nextBackoffDelay() {
    final current = state.retryDelay;
    final next = current * 2;
    const cap = Duration(seconds: 60);
    final adjusted = next > cap ? cap : next;
    return adjusted;
  }
}
