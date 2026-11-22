import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/walk_graph_seed_source.dart';
import '../domain/walk_graph_worker.dart';

final walkGraphProvider = FutureProvider<WalkGraphWorker?>((ref) async {
  Uint8List? seedBytes;
  try {
    seedBytes = await WalkGraphSeedSource().loadSeedBytes();
  } on FlutterError catch (error, stackTrace) {
    developer.log(
      'No se encontró la seed peatonal empaquetada.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
  }
  try {
    final worker = await createWalkGraphWorker(seedBytes);
    ref.onDispose(() => unawaited(worker.dispose()));
    return worker;
  } on RemoteError catch (error, stackTrace) {
    developer.log(
      'La seed peatonal empaquetada no es válida.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    final worker = await createWalkGraphWorker(null);
    ref.onDispose(() => unawaited(worker.dispose()));
    return worker;
  }
});
