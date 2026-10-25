import 'package:maplibre/maplibre.dart';

/// All map style URLs and defaults live here so a provider can be changed once.
abstract final class MapConfig {
  static const String lightStyleUrl =
      'https://tiles.openfreemap.org/styles/positron';
  static const String darkStyleUrl =
      'https://tiles.openfreemap.org/styles/dark';
  static const String attribution =
      '© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap';
  static const String providerName = 'OpenFreeMap';
  static const String providerWebsite = 'openfreemap.org';
  static const Geographic initialCenter = Geographic(
    lon: -56.1991,
    lat: -34.9058,
  );
  static const double initialZoom = 12;
  static const int maxAmbientCacheBytes = 50 * 1024 * 1024;
  static const Duration mapLoadTimeout = Duration(seconds: 25);
}
