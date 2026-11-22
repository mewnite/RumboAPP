import 'dart:isolate';
import 'dart:developer' as developer;

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
  final totalWatch = Stopwatch()..start();
  final spawnWatch = Stopwatch()..start();
  late final Isolate isolate;
  try {
    isolate = await Isolate.spawn<_PlanSearchMessage>(_runPlanSearch, (
      payload,
      resultPort.sendPort,
    ), onExit: resultPort.sendPort);
    spawnWatch.stop();
    developer.log(
      '[performance] plan_search_isolate_spawn='
      '${spawnWatch.elapsedMilliseconds}ms',
      name: 'Rumbo',
    );
    cancellation?.attach(() => isolate.kill(priority: Isolate.immediate));

    final message = await resultPort.first;
    totalWatch.stop();
    developer.log(
      '[performance] plan_search_isolate_total='
      '${totalWatch.elapsedMilliseconds}ms',
      name: 'Rumbo',
    );
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
