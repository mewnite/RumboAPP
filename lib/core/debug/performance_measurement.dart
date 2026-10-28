import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class PerformanceMeasurement {
  PerformanceMeasurement._(this.name) : _stopwatch = Stopwatch()..start();

  final String name;
  final Stopwatch _stopwatch;

  static bool get enabled => kDebugMode || kProfileMode;

  static PerformanceMeasurement start(String name) {
    return PerformanceMeasurement._(name);
  }

  void finish({String details = ''}) {
    if (!enabled) return;
    final suffix = details.isEmpty ? '' : ' $details';
    final message =
        '[performance] $name ${_stopwatch.elapsedMilliseconds}ms$suffix';
    debugPrint(message);
    developer.Timeline.instantSync(
      'rumbo.$name',
      arguments: <String, Object?>{
        'elapsed_ms': _stopwatch.elapsedMilliseconds,
        if (details.isNotEmpty) 'details': details,
      },
    );
  }
}
