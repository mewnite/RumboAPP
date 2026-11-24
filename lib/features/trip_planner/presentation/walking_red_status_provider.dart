import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/walk_graph_worker.dart';
import 'walk_graph_provider.dart';

const _walkingStatusTimeout = Duration(seconds: 15);

/// Estado de la red peatonal mostrado en Ajustes.
enum WalkingRedStatus { cargada, seedAusente, workerFallo, snapNulo }

class WalkingRedState {
  const WalkingRedState(this.status);

  final WalkingRedStatus status;
}

final walkingSnapNullProvider =
    NotifierProvider<WalkingSnapNullController, bool>(
      WalkingSnapNullController.new,
    );

class WalkingSnapNullController extends Notifier<bool> {
  @override
  bool build() => false;

  void setSnapNull(bool value) {
    state = value;
  }
}

/// Estado local de la red peatonal (sin consultas a red): si el worker
/// está levantado, si la seed empaquetada está presente y si el grafo
/// peatonal está cargado.
final walkingRedStatusProvider = FutureProvider<WalkingRedState>((ref) async {
  final snapNull = ref.watch(walkingSnapNullProvider);
  WalkGraphWorker? worker;
  try {
    worker = await ref
        .read(walkGraphProvider.future)
        .timeout(_walkingStatusTimeout);
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo iniciar el worker para el diagnóstico peatonal.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    return ref.read(walkGraphSeedAvailabilityProvider) ==
            WalkGraphSeedAvailability.absent
        ? const WalkingRedState(WalkingRedStatus.seedAusente)
        : const WalkingRedState(WalkingRedStatus.workerFallo);
  }
  final currentSeedAvailability = ref.read(walkGraphSeedAvailabilityProvider);
  if (currentSeedAvailability == WalkGraphSeedAvailability.absent) {
    return const WalkingRedState(WalkingRedStatus.seedAusente);
  }
  if (worker == null) {
    return const WalkingRedState(WalkingRedStatus.workerFallo);
  }
  bool graphLoaded;
  try {
    graphLoaded = await worker.graphLoaded().timeout(_walkingStatusTimeout);
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo consultar el estado del worker peatonal.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    return const WalkingRedState(WalkingRedStatus.workerFallo);
  }
  if (!graphLoaded) {
    return const WalkingRedState(WalkingRedStatus.workerFallo);
  }
  if (snapNull) {
    return const WalkingRedState(WalkingRedStatus.snapNulo);
  }
  return const WalkingRedState(WalkingRedStatus.cargada);
});
