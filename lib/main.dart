import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/debug/performance_measurement.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final firstFrame = PerformanceMeasurement.start('startup.first_frame');
  runApp(const ProviderScope(child: RumboApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) => firstFrame.finish());
}
