import 'dart:typed_data';

import 'trip_planner.dart';
import 'plan_search_cancellation.dart';
import 'walk_graph.dart';

abstract interface class WalkGraphWorker {
  Future<List<TripPlan>> searchPlans(
    PlanSearchPayload payload, {
    PlanSearchCancellation? cancellation,
  });

  Future<TripPlan> refreshWalkingSegments(TripPlan plan);

  Future<WalkPath?> shortestPath(
    double latitude,
    double longitude,
    double toLatitude,
    double toLongitude,
  );

  Future<void> ping();

  Future<bool> graphLoaded();

  Future<void> dispose();
}

Future<WalkGraphWorker> createWalkGraphWorker(Uint8List? seedBytes) async =>
    _WalkGraphWorkerStub(
      seedBytes == null ? null : WalkGraph.fromSeedBytes(seedBytes),
    );

class _WalkGraphWorkerStub implements WalkGraphWorker {
  _WalkGraphWorkerStub(this._graph);

  final WalkGraph? _graph;

  @override
  Future<void> dispose() async {}

  @override
  Future<TripPlan> refreshWalkingSegments(TripPlan plan) async =>
      refreshWalkingSegmentsSync(plan, walkGraph: _graph);

  @override
  Future<WalkPath?> shortestPath(
    double latitude,
    double longitude,
    double toLatitude,
    double toLongitude,
  ) async => _graph?.shortestPath(latitude, longitude, toLatitude, toLongitude);

  @override
  Future<void> ping() async {}

  @override
  Future<bool> graphLoaded() async => _graph != null;

  @override
  Future<List<TripPlan>> searchPlans(
    PlanSearchPayload payload, {
    PlanSearchCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return const [];
    return searchPlansSync(payload, walkGraph: _graph);
  }
}
