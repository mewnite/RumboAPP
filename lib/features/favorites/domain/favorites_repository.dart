import 'favorite.dart';

/// Persistencia local de favoritos. La implementación no usa red.
abstract interface class FavoritesRepository {
  Future<List<Favorite>> load();

  Future<void> save(List<Favorite> favorites);
}
