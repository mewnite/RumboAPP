import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/transit_database.dart';

const _transitDiagnosticsTimeout = Duration(seconds: 15);

class TransitLocalStatus {
  const TransitLocalStatus({
    required this.database,
    required this.lastCheckMilliseconds,
  });

  final TransitDatabaseDiagnostics database;
  final int? lastCheckMilliseconds;
}

final transitLocalStatusProvider = FutureProvider<TransitLocalStatus>((
  ref,
) async {
  try {
    return await _loadTransitLocalStatus().timeout(_transitDiagnosticsTimeout);
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo cargar el diagnóstico local de tránsito.',
      name: 'Rumbo',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
});

Future<TransitLocalStatus> _loadTransitLocalStatus() async {
  final database = await TransitDatabase().diagnostics();
  final preferences = await SharedPreferences.getInstance();
  return TransitLocalStatus(
    database: database,
    lastCheckMilliseconds: preferences.getInt('transit_last_check_ms'),
  );
}
