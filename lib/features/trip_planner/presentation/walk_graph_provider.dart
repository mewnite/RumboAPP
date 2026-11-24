import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/walk_graph_seed_source.dart';
import '../domain/walk_graph_worker.dart';

const _walkGraphProviderTimeout = Duration(seconds: 15);

enum WalkGraphSeedAvailability { unknown, available, absent }

final walkGraphSeedAvailabilityProvider =
    NotifierProvider<
      WalkGraphSeedAvailabilityController,
      WalkGraphSeedAvailability
    >(WalkGraphSeedAvailabilityController.new);

class WalkGraphSeedAvailabilityController
    extends Notifier<WalkGraphSeedAvailability> {
  @override
  WalkGraphSeedAvailability build() => WalkGraphSeedAvailability.unknown;

  void setAvailability(WalkGraphSeedAvailability availability) {
    state = availability;
  }
}

final walkGraphProvider = FutureProvider<WalkGraphWorker?>((ref) async {
  Uint8List? seedBytes;
  ref
      .read(walkGraphSeedAvailabilityProvider.notifier)
      .setAvailability(WalkGraphSeedAvailability.unknown);
  try {
    seedBytes = await WalkGraphSeedSource().loadSeedBytes().timeout(
      _walkGraphProviderTimeout,
    );
    ref
        .read(walkGraphSeedAvailabilityProvider.notifier)
        .setAvailability(WalkGraphSeedAvailability.available);
  } on FlutterError catch (error, stackTrace) {
    ref
        .read(walkGraphSeedAvailabilityProvider.notifier)
        .setAvailability(WalkGraphSeedAvailability.absent);
    developer.log(
      'No se encontró la seed peatonal empaquetada.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo leer la seed peatonal empaquetada.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
  try {
    // El timeout de arranque del worker es no fatal: si el worker tarda
    // más de lo esperado en quedarse listo, la espera sigue hasta que
    // termine de arrancar (véase _waitForWorkerReady en walk_graph_worker_io).
    final worker = await createWalkGraphWorker(seedBytes);
    ref.onDispose(() => unawaited(worker.dispose()));
    return worker;
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo preparar el worker peatonal.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
});
