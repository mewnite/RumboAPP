import 'trip_planner.dart';

/// Fallback para plataformas sin isolates (web).
Future<List<TripPlan>> runPlanSearch(PlanSearchPayload payload) async =>
    searchPlansSync(payload);
