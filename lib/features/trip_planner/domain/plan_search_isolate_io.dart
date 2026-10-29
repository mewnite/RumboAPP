import 'dart:isolate';

import 'trip_planner.dart';
import 'plan_search_cancellation.dart';

typedef _PlanSearchMessage = (PlanSearchPayload, SendPort);
typedef _PlanSearchOutcome = (List<TripPlan>?, String?, String?);

/// Ejecuta y permite cancelar la búsqueda en un isolate.
Future<List<TripPlan>> runPlanSearch(
  PlanSearchPayload payload, {
  PlanSearchCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled ?? false) return const [];

  final resultPort = ReceivePort();
  late final Isolate isolate;
  try {
    isolate = await Isolate.spawn<_PlanSearchMessage>(_runPlanSearch, (
      payload,
      resultPort.sendPort,
    ), onExit: resultPort.sendPort);
    cancellation?.attach(() => isolate.kill(priority: Isolate.immediate));

    final message = await resultPort.first;
    if (message == null) {
      if (cancellation?.isCancelled ?? false) return const [];
      throw StateError('La búsqueda de viajes terminó sin resultados.');
    }
    final outcome = message as _PlanSearchOutcome;
    if (outcome.$2 != null) {
      throw RemoteError(outcome.$2!, outcome.$3 ?? '');
    }
    return outcome.$1 ?? const [];
  } finally {
    cancellation?.detach();
    resultPort.close();
  }
}

void _runPlanSearch(_PlanSearchMessage message) {
  final (payload, resultPort) = message;
  try {
    Isolate.exit(resultPort, (searchPlansSync(payload), null, null));
  } on Object catch (error, stackTrace) {
    Isolate.exit(resultPort, (null, error.toString(), stackTrace.toString()));
  }
}
