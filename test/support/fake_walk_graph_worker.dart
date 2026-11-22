import 'package:rumbo/features/trip_planner/domain/plan_search_cancellation.dart';
import 'package:rumbo/features/trip_planner/domain/trip_planner.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph_worker.dart';

class FakeWalkGraphWorker implements WalkGraphWorker {
  const FakeWalkGraphWorker(this.graph);

  final WalkGraph? graph;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ping() async {}

  @override
  Future<TripPlan> refreshWalkingSegments(TripPlan plan) async =>
      refreshWalkingSegmentsSync(plan, walkGraph: graph);

  @override
  Future<List<TripPlan>> searchPlans(
    PlanSearchPayload payload, {
    PlanSearchCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return const [];
    return searchPlansSync(payload, walkGraph: graph);
  }

  @override
  Future<WalkPath?> shortestPath(
    double latitude,
    double longitude,
    double toLatitude,
    double toLongitude,
  ) async => graph?.shortestPath(latitude, longitude, toLatitude, toLongitude);
}
