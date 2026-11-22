import "dart:async";

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
    final graph = WalkNetworkSource.buildGraph(cached);
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
    final graph = WalkNetworkSource.buildGraph(data);
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
