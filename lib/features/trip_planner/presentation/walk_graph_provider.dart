import "dart:async";
import "dart:isolate";
import "dart:developer" as developer;

import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/config/transit_config.dart";
import "../data/walk_network_source.dart";
import "../domain/walk_graph.dart";

/// Red peatonal real — cargada al inicio; no se bloquea la planificación si
/// existe una red válida en caché (descarga en segundo plano).
final walkGraphProvider = FutureProvider<WalkGraph?>((ref) async {
  final source = WalkNetworkSource(endpoint: transitConfig.walkNetworkEndpoint);
  final cached = await source.readCached();
  if (cached != null) {
    final stopwatch = Stopwatch()..start();
    final graph = await Isolate.run<WalkGraph?>(
      () => WalkNetworkSource.buildGraph(cached),
    );
    stopwatch.stop();
    developer.log(
      '[performance] walk_network_cached_graph_build=${stopwatch.elapsedMilliseconds}ms',
      name: 'Rumbo',
    );
    if (graph != null) {
      unawaited(_refresh(source));
      return graph;
    }
  }
  // Fetch + jsonDecode del JSON grande (el build del grafo mide ~0.7s —
  // razonable para el hilo de UI; la búsqueda Dijkstra ya corre en un
  // isolate — `runPlanSearch`).
  final data = await source.fetch();
  if (data != null) {
    final stopwatch = Stopwatch()..start();
    final graph = await Isolate.run<WalkGraph?>(
      () => WalkNetworkSource.buildGraph(data),
    );
    stopwatch.stop();
    developer.log(
      '[performance] walk_network_fetch_graph_build=${stopwatch.elapsedMilliseconds}ms',
      name: 'Rumbo',
    );
    if (graph != null) {
      unawaited(source.writeCached(data));
      return graph;
    }
  }
  return null;
});

Future<void> _refresh(WalkNetworkSource source) async {
  try {
    final fetched = await source.fetch();
    if (fetched != null) {
      await source.writeCached(fetched);
    }
  } on Exception {
    // Conservar la última red válida.
  }
}
