import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/favorite.dart';
import '../domain/favorites_repository.dart';

/// Guarda los favoritos como una lista JSON en las preferencias locales.
class SharedPreferencesFavoritesRepository implements FavoritesRepository {
  static const String _preferenceKey = 'favorites_v1';

  @override
  Future<List<Favorite>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_preferenceKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = _decode(raw);
    if (decoded is! List) return const [];
    final favorites = <Favorite>[];
    for (final item in decoded) {
      if (item is! Map<String, Object?>) continue;
      try {
        favorites.add(Favorite.fromJson(item));
      } on FormatException {
        // Un elemento dañado no invalida el resto de la lista guardada.
      }
    }
    return favorites;
  }

  Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      // Si todo el contenido está dañado, se empieza con una lista vacía.
      return null;
    }
  }

  @override
  Future<void> save(List<Favorite> favorites) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _preferenceKey,
      jsonEncode([for (final favorite in favorites) favorite.toJson()]),
    );
  }
}
