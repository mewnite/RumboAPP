import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class PerformanceMeasurement {
  PerformanceMeasurement._(this.name, this._enabled)
    : _stopwatch = Stopwatch() {
    if (_enabled) _stopwatch.start();
  }

  final String name;
  final bool _enabled;
  final Stopwatch _stopwatch;
  bool _finished = false;

  static bool get enabled => kDebugMode || kProfileMode;

  static PerformanceMeasurement start(String name) {
    return PerformanceMeasurement._(name, enabled);
  }

  void finish({String details = ''}) {
    if (!_enabled || _finished) return;
    _finished = true;
    _stopwatch.stop();
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
