import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/data/map_cache_repository.dart';
import 'package:rumbo/features/settings/data/local_data_repository.dart';
import 'package:rumbo/features/settings/presentation/privacy_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeMapCacheRepository implements MapCacheRepository {
  int clearCount = 0;

  @override
  Future<void> configureAmbientCache() async {}

  @override
  Future<void> clearAmbientCache() async => clearCount++;
}

void main() {
  test(
    'live bus display preference persists across provider containers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      expect(await first.read(liveBusesEnabledProvider.future), isTrue);
      await first.read(liveBusesEnabledProvider.notifier).setEnabled(false);
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(await second.read(liveBusesEnabledProvider.future), isFalse);
    },
  );

  test(
    'clear local data removes favorites and recents and clears map cache',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorites_v1': 'saved',
        'rumbo_recent_searches_v1': 'recent',
      });
      final cache = _FakeMapCacheRepository();
      final repository = SharedPreferencesLocalDataRepository(mapCache: cache);

      await repository.clearUserData();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.get('favorites_v1'), isNull);
      expect(preferences.get('rumbo_recent_searches_v1'), isNull);
      expect(cache.clearCount, 1);
    },
  );
}
