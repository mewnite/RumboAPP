import 'trip_planner.dart';
import 'plan_search_cancellation.dart';

/// Fallback para plataformas sin isolates (web).
Future<List<TripPlan>> runPlanSearch(
  PlanSearchPayload payload, {
  PlanSearchCancellation? cancellation,
}) async =>
    cancellation?.isCancelled ?? false ? const [] : searchPlansSync(payload);
