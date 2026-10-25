import 'package:flutter/foundation.dart';

const double transitMinimumLatitude = -35.2;
const double transitMaximumLatitude = -30.0;
const double transitMinimumLongitude = -58.5;
const double transitMaximumLongitude = -53.0;

const _montevideoApiBaseUrl = String.fromEnvironment(
  'RUMBO_API_BASE_URL',
  defaultValue: '',
);
final _localProxyUrl = defaultTargetPlatform == TargetPlatform.android
    ? 'http://10.0.2.2:8765'
    : 'http://127.0.0.1:8765';
final _effectiveApiBaseUrl = kDebugMode
    ? (_montevideoApiBaseUrl == '' ? _localProxyUrl : _montevideoApiBaseUrl)
    : _montevideoApiBaseUrl;

/// Configuration for the static transit feed. Empty URL means bundled demo data.
class TransitConfig {
  const TransitConfig({
    this.url = '',
    this.sourceName = 'Datos sintéticos de prueba',
    this.attribution = 'Datos sintéticos de prueba; no representan el STM.',
    this.license =
        'Sin licencia para uso como datos reales; solo demostración.',
    this.minimumCheckInterval = const Duration(hours: 24),
    this.realtimeEndpoint = '',
    this.placeSearchEndpoint = '',
    this.minimumLatitude = transitMinimumLatitude,
    this.maximumLatitude = transitMaximumLatitude,
    this.minimumLongitude = transitMinimumLongitude,
    this.maximumLongitude = transitMaximumLongitude,
  });

  final String url;
  final String sourceName;
  final String attribution;
  final String license;
  final Duration minimumCheckInterval;

  /// Base path for the realtime API proxy; empty disables live polling.
  final String realtimeEndpoint;
  final String placeSearchEndpoint;
  final double minimumLatitude,
      maximumLatitude,
      minimumLongitude,
      maximumLongitude;
}

final transitConfig = TransitConfig(
  url: _effectiveApiBaseUrl == '' ? '' : '$_effectiveApiBaseUrl/gtfs/latest',
  sourceName: _effectiveApiBaseUrl == ''
      ? 'Datos sintéticos de prueba'
      : 'GTFS oficial STM (API de Montevideo)',
  attribution: _effectiveApiBaseUrl == ''
      ? 'Datos sintéticos de prueba; no representan el STM.'
      : 'Fuente: STM / Intendencia de Montevideo.',
  realtimeEndpoint: _effectiveApiBaseUrl == ''
      ? ''
      : '$_effectiveApiBaseUrl/api',
  placeSearchEndpoint: _effectiveApiBaseUrl == ''
      ? ''
      : '$_effectiveApiBaseUrl/geocode',
);
