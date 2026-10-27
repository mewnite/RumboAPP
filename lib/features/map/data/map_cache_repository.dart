import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/config/map_config.dart';

abstract interface class MapCacheRepository {
  Future<void> configureAmbientCache();
  Future<void> clearAmbientCache();
}

class MapLibreCacheRepository implements MapCacheRepository {
  @override
  Future<void> configureAmbientCache() async {
    if (!OfflineManager.isSupported) return;
    final manager = await OfflineManager.createInstance();
    try {
      await manager.setMaximumAmbientCacheSize(
        bytes: MapConfig.maxAmbientCacheBytes,
      );
    } finally {
      manager.dispose();
    }
  }

  @override
  Future<void> clearAmbientCache() async {
    if (!OfflineManager.isSupported) return;
    final manager = await OfflineManager.createInstance();
    try {
      await manager.clearAmbientCache();
    } finally {
      manager.dispose();
    }
  }
}

final mapCacheRepositoryProvider = Provider<MapCacheRepository>(
  (ref) => MapLibreCacheRepository(),
);
