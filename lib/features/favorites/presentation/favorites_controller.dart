import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shared_preferences_favorites_repository.dart';
import '../domain/favorite.dart';
import '../domain/favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => SharedPreferencesFavoritesRepository(),
);

final favoritesControllerProvider =
    AsyncNotifierProvider<FavoritesController, List<Favorite>>(
      FavoritesController.new,
    );

class FavoritesController extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() {
    return ref.watch(favoritesRepositoryProvider).load();
  }

  Future<List<Favorite>> _readCurrent() async {
    final current = state.asData?.value;
    if (current != null) return current;
    return ref.read(favoritesRepositoryProvider).load();
  }

  Future<void> _commit(List<Favorite> favorites) async {
    try {
      await ref.read(favoritesRepositoryProvider).save(favorites);
      state = AsyncData(List<Favorite>.unmodifiable(favorites));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> add(Favorite favorite) async {
    final current = await _readCurrent();
    await _commit([
      ...current.where((saved) => saved.key != favorite.key),
      favorite,
    ]);
  }

  Future<void> remove(Favorite favorite) async {
    final current = await _readCurrent();
    await _commit([...current.where((saved) => saved.key != favorite.key)]);
  }

  Future<void> restore(Favorite favorite, int index) async {
    final current = await _readCurrent();
    final restored = [...current.where((saved) => saved.key != favorite.key)];
    restored.insert(index.clamp(0, restored.length), favorite);
    await _commit(restored);
  }

  Future<void> rename(Favorite favorite, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = await _readCurrent();
    await _commit([
      for (final saved in current)
        if (saved.key == favorite.key) saved.copyWith(name: trimmed) else saved,
    ]);
  }

  Future<void> setPlace({
    required FavoritePlaceSlot slot,
    required String name,
    required double latitude,
    required double longitude,
  }) {
    return add(
      Favorite.place(
        slot: slot,
        name: name,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }
}
