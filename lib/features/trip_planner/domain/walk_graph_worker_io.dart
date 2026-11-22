import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'plan_search_cancellation.dart';
import 'trip_planner.dart';
import 'walk_graph.dart';

typedef _WorkerInit = (SendPort, TransferableTypedData?);
typedef _WorkerCommand = (int, String, Object?, SendPort);
typedef _WorkerResponse = (int, Object?, String?, String?);

Future<WalkGraphWorker> createWalkGraphWorker(Uint8List? seedBytes) =>
    _PersistentWalkGraphWorker.start(seedBytes);

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

  Future<void> dispose();
}

class _PersistentWalkGraphWorker implements WalkGraphWorker {
  _PersistentWalkGraphWorker(this._seedBytes);

  final Uint8List? _seedBytes;
  final Map<int, _PendingRequest> _pending = {};
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  ReceivePort? _exitPort;
  Future<void>? _starting;
  int _nextRequestId = 0;
  bool _disposed = false;

  static Future<_PersistentWalkGraphWorker> start(Uint8List? seedBytes) async {
    final worker = _PersistentWalkGraphWorker(seedBytes);
    await worker._ensureStarted();
    return worker;
  }

  Future<void> _ensureStarted() {
    if (_commandPort != null) return Future<void>.value();
    return _starting ??= _spawn().whenComplete(() => _starting = null);
  }

  Future<void> _spawn() async {
    if (_disposed) throw StateError('El worker peatonal ya fue cerrado.');
    final readyPort = ReceivePort();
    final exitPort = ReceivePort();
    final responsePort = ReceivePort();
    final stopwatch = Stopwatch()..start();
    final transferable = _seedBytes == null
        ? null
        : TransferableTypedData.fromList([_seedBytes]);
    final isolate = await Isolate.spawn<_WorkerInit>(_runWalkGraphWorker, (
      readyPort.sendPort,
      transferable,
    ), onExit: exitPort.sendPort);
    final ready = await readyPort.first;
    readyPort.close();
    if (ready is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      exitPort.close();
      responsePort.close();
      final error = ready;
      if (error is (String, String)) {
        throw RemoteError(error.$1, error.$2);
      }
      throw StateError('El worker peatonal no inició correctamente.');
    }

    _isolate = isolate;
    _commandPort = ready;
    _responsePort = responsePort;
    _exitPort = exitPort;
    responsePort.listen(_handleResponse);
    exitPort.listen((_) {
      if (identical(_isolate, isolate) && !_disposed) {
        _failPending(StateError('El worker peatonal terminó inesperadamente.'));
        _clearWorkerPorts();
      }
    });
    stopwatch.stop();
    developer.log(
      '[performance] walk_graph_worker_ready=${stopwatch.elapsedMilliseconds}ms '
      'seed_bytes=${_seedBytes?.length ?? 0}',
      name: 'Rumbo',
    );
  }

  void _handleResponse(Object? message) {
    if (message is! _WorkerResponse) return;
    final pending = _pending.remove(message.$1);
    if (pending == null || pending.completer.isCompleted) return;
    if (message.$3 != null) {
      pending.completer.completeError(
        RemoteError(message.$3!, message.$4 ?? ''),
      );
    } else {
      pending.completer.complete(message.$2);
    }
  }

  Future<Object?> _send(String operation, Object? payload) async {
    await _ensureStarted();
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = _PendingRequest(completer);
    final stopwatch = Stopwatch()..start();
    _commandPort!.send((id, operation, payload, _responsePort!.sendPort));
    try {
      final result = await completer.future;
      stopwatch.stop();
      developer.log(
        '[performance] walk_graph_worker_$operation=${stopwatch.elapsedMilliseconds}ms',
        name: 'Rumbo',
      );
      return result;
    } finally {
      _pending.remove(id);
    }
  }

  void _cancelWorker() {
    _isolate?.kill(priority: Isolate.immediate);
    _failPending(const _WorkerCancelled());
    _clearWorkerPorts();
  }

  void _failPending(Object error) {
    for (final request in _pending.values) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _clearWorkerPorts() {
    _responsePort?.close();
    _exitPort?.close();
    _responsePort = null;
    _exitPort = null;
    _commandPort = null;
    _isolate = null;
  }

  @override
  Future<List<TripPlan>> searchPlans(
    PlanSearchPayload payload, {
    PlanSearchCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return const [];
    await _ensureStarted();
    if (cancellation?.isCancelled ?? false) return const [];
    cancellation?.attach(_cancelWorker);
    try {
      final result = await _send('search', payload);
      if (cancellation?.isCancelled ?? false) return const [];
      return result as List<TripPlan>;
    } on _WorkerCancelled {
      if (cancellation?.isCancelled ?? false) return const [];
      rethrow;
    } finally {
      cancellation?.detach();
    }
  }

  @override
  Future<TripPlan> refreshWalkingSegments(TripPlan plan) async =>
      await _send('refresh', plan) as TripPlan;

  @override
  Future<WalkPath?> shortestPath(
    double latitude,
    double longitude,
    double toLatitude,
    double toLongitude,
  ) async =>
      await _send('walk', (latitude, longitude, toLatitude, toLongitude))
          as WalkPath?;

  @override
  Future<void> ping() async {
    await _send('ping', null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _failPending(StateError('El worker peatonal fue cerrado.'));
    _clearWorkerPorts();
  }
}

class _PendingRequest {
  const _PendingRequest(this.completer);

  final Completer<Object?> completer;
}

class _WorkerCancelled implements Exception {
  const _WorkerCancelled();
}

void _runWalkGraphWorker(_WorkerInit init) {
  final (readyPort, transferable) = init;
  try {
    final graph = transferable == null
        ? null
        : WalkGraph.fromSeedBytes(transferable.materialize().asUint8List());
    final commands = ReceivePort();
    readyPort.send(commands.sendPort);
    commands.listen((message) {
      if (message is! _WorkerCommand) return;
      final (id, operation, payload, responsePort) = message;
      try {
        final result = switch (operation) {
          'search' => searchPlansSync(
            payload as PlanSearchPayload,
            walkGraph: graph,
          ),
          'refresh' => refreshWalkingSegmentsSync(
            payload as TripPlan,
            walkGraph: graph,
          ),
          'walk' => _runWalkCommand(graph, payload),
          'ping' => null,
          _ => throw ArgumentError.value(operation, 'operation'),
        };
        responsePort.send((id, result, null, null));
      } on Object catch (error, stackTrace) {
        responsePort.send((id, null, error.toString(), stackTrace.toString()));
      }
    });
  } on Object catch (error, stackTrace) {
    readyPort.send((error.toString(), stackTrace.toString()));
  }
}

WalkPath? _runWalkCommand(WalkGraph? graph, Object? payload) {
  final (latitude, longitude, toLatitude, toLongitude) =
      payload as (double, double, double, double);
  return graph?.shortestPath(latitude, longitude, toLatitude, toLongitude);
}
