import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/config/transit_config.dart';
import 'core/debug/performance_measurement.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final firstFrame = PerformanceMeasurement.start('startup.first_frame');
  _warmupBackend();
  runApp(const ProviderScope(child: RumboApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) => firstFrame.finish());
}

void _warmupBackend() {
  if (transitConfig.realtimeEndpoint.isEmpty) return;
  final uri = Uri.tryParse(transitConfig.realtimeEndpoint);
  if (uri == null || !uri.hasAuthority) return;
  final client = http.Client();
  final healthUri = uri.replace(path: '/health');
  final basePath = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  final warmupUri = uri.replace(
    path: '$basePath/buses',
    queryParameters: const {'format': 'geojson', 'lines': '1'},
  );
  client
      .get(healthUri)
      .timeout(const Duration(seconds: 15))
      .then((_) => client.get(
            warmupUri,
            headers: const {'Accept': 'application/geo+json'},
          ).timeout(const Duration(seconds: 30)))
      .whenComplete(client.close)
      .ignore();
}
