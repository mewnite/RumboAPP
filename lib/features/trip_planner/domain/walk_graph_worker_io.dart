import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'plan_search_cancellation.dart';
import 'trip_planner.dart';
import 'walk_graph.dart';

typedef _WorkerInit = (SendPort, TransferableTypedData?, Duration);
typedef _WorkerCommand = (int, String, Object?, SendPort);
typedef _WorkerResponse = (int, Object?, String?, String?);

Future<WalkGraphWorker> createWalkGraphWorker(
  Uint8List? seedBytes, {
  Duration? startupTimeout,
  Duration? readyDelay,
}) => _PersistentWalkGraphWorker.start(
  seedBytes,
  startupTimeout: startupTimeout,
  readyDelay: readyDelay,
);

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

  /// True si el worker tiene cargado el grafo peatonal.
  Future<bool> graphLoaded();

  Future<void> dispose();
}

class _PersistentWalkGraphWorker implements WalkGraphWorker {
  static const _defaultStartupTimeout = Duration(seconds: 60);

  _PersistentWalkGraphWorker(
    this._seedBytes, {
    Duration? startupTimeout,
    Duration? readyDelay,
  }) : startupTimeout = startupTimeout ?? _defaultStartupTimeout,
       readyDelay = readyDelay ?? Duration.zero;

  final Uint8List? _seedBytes;

  /// Tope de espera para que el worker señale que está listo.
  final Duration startupTimeout;

  /// Retardo antes de señalar que el worker está listo (solo para pruebas).
  final Duration readyDelay;

  final Map<int, _PendingRequest> _pending = {};
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  ReceivePort? _exitPort;
  Future<void>? _starting;
  int _nextRequestId = 0;
  bool _disposed = false;

  static Future<_PersistentWalkGraphWorker> start(
    Uint8List? seedBytes, {
    Duration? startupTimeout,
    Duration? readyDelay,
  }) async {
    final worker = _PersistentWalkGraphWorker(
      seedBytes,
      startupTimeout: startupTimeout,
      readyDelay: readyDelay,
    );
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
    Isolate? isolate;
    void closeStartupPorts() {
      isolate?.kill(priority: Isolate.immediate);
      readyPort.close();
      exitPort.close();
      responsePort.close();
    }

    try {
      final stopwatch = Stopwatch()..start();
      final transferable = _seedBytes == null
          ? null
          : TransferableTypedData.fromList([_seedBytes]);
      final startedIsolate = await Isolate.spawn<_WorkerInit>(
        _runWalkGraphWorker,
        (readyPort.sendPort, transferable, readyDelay),
        onExit: exitPort.sendPort,
      );
      isolate = startedIsolate;
      final ready = await _waitForWorkerReady(readyPort);
      readyPort.close();
      if (ready is! SendPort) {
        final error = ready;
        if (error is (String, String)) {
          throw RemoteError(error.$1, error.$2);
        }
        throw StateError('El worker peatonal no inició correctamente.');
      }

      _isolate = startedIsolate;
      _commandPort = ready;
      _responsePort = responsePort;
      _exitPort = exitPort;
      responsePort.listen(_handleResponse);
      exitPort.listen((_) {
        if (identical(_isolate, startedIsolate) && !_disposed) {
          _failPending(
            StateError('El worker peatonal terminó inesperadamente.'),
          );
          _clearWorkerPorts();
        }
      });
      stopwatch.stop();
      developer.log(
        '[performance] walk_graph_worker_ready=${stopwatch.elapsedMilliseconds}ms '
        'seed_bytes=${_seedBytes?.length ?? 0}',
        name: 'Rumbo',
      );
    } on Object catch (error, stackTrace) {
      closeStartupPorts();
      developer.log(
        'No se pudo iniciar el worker peatonal.',
        name: 'Rumbo',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Espera el puerto ready del worker.
  ///
  /// Si el worker no señala que está listo dentro de [startupTimeout],
  /// la espera se da por terminada con un error.
  Future<Object?> _waitForWorkerReady(ReceivePort readyPort) async {
    final readyFuture = readyPort.first;
    final result = await Future.any<Object?>([
      readyFuture,
      Future<Object?>.delayed(startupTimeout)
          .then((_) => const _WorkerReadyTimeoutMarker()),
    ]);
    if (result is _WorkerReadyTimeoutMarker) {
      throw StateError(
        'El worker peatonal no señaló que está listo dentro de '
        '$startupTimeout.',
      );
    }
    return result;
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
  Future<bool> graphLoaded() async =>
      (await _send('graphLoaded', null)) as bool;

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

class _WorkerReadyTimeoutMarker {
  const _WorkerReadyTimeoutMarker();
}

void _runWalkGraphWorker(_WorkerInit init) {
  final (readyPort, transferable, readyDelay) = init;
  try {
    final graph = transferable == null
        ? null
        : WalkGraph.fromSeedBytes(transferable.materialize().asUint8List());
    final commands = ReceivePort();
    void signalReady() {
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
            'graphLoaded' => graph != null,
            _ => throw ArgumentError.value(operation, 'operation'),
          };
          responsePort.send((id, result, null, null));
        } on Object catch (error, stackTrace) {
          responsePort.send((
            id,
            null,
            error.toString(),
            stackTrace.toString(),
          ));
        }
      });
    }

    if (readyDelay > Duration.zero) {
      Future<void>(() async {
        await Future.delayed(readyDelay);
        signalReady();
      });
    } else {
      signalReady();
    }
  } on Object catch (error, stackTrace) {
    readyPort.send((error.toString(), stackTrace.toString()));
  }
}

WalkPath? _runWalkCommand(WalkGraph? graph, Object? payload) {
  final (latitude, longitude, toLatitude, toLongitude) =
      payload as (double, double, double, double);
  return graph?.shortestPath(latitude, longitude, toLatitude, toLongitude);
}
