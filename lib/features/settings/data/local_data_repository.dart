import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../map/data/map_cache_repository.dart';

abstract interface class LocalDataRepository {
  Future<void> clearUserData();
}

class SharedPreferencesLocalDataRepository implements LocalDataRepository {
  SharedPreferencesLocalDataRepository({
    Future<SharedPreferences> Function()? preferences,
    required this.mapCache,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;
  final MapCacheRepository mapCache;

  @override
  Future<void> clearUserData() async {
    final preferences = await _preferences();
    await preferences.remove('favorites_v1');
    await preferences.remove('rumbo_recent_searches_v1');
    await mapCache.clearAmbientCache();
  }
}

final localDataRepositoryProvider = Provider<LocalDataRepository>(
  (ref) => SharedPreferencesLocalDataRepository(
    mapCache: ref.read(mapCacheRepositoryProvider),
  ),
);
