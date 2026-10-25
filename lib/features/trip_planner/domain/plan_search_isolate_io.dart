import 'dart:isolate';

import 'trip_planner.dart';

/// Ejecuta la búsqueda en un isolate para no bloquear la interfaz.
Future<List<TripPlan>> runPlanSearch(PlanSearchPayload payload) =>
    Isolate.run(() => searchPlansSync(payload));
