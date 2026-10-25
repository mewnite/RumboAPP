import '../domain/favorite.dart';
import '../domain/favorites_repository.dart';

/// Repositorio en memoria para pruebas; conserva los datos entre lecturas.
class FakeFavoritesRepository implements FavoritesRepository {
  FakeFavoritesRepository([List<Favorite> initial = const []])
    : _favorites = List<Favorite>.of(initial);

  List<Favorite> _favorites;
  int saveCount = 0;

  @override
  Future<List<Favorite>> load() async =>
      List<Favorite>.unmodifiable(_favorites);

  @override
  Future<void> save(List<Favorite> favorites) async {
    _favorites = List<Favorite>.of(favorites);
    saveCount++;
  }
}
