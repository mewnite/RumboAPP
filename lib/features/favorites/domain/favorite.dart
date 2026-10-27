/// Tipo de entidad que se puede guardar en Favoritos.
enum FavoriteType { stop, line, place }

/// Ranuras fijas para los lugares de uso frecuente.
enum FavoritePlaceSlot { home, work }

/// Un favorito guardado localmente. No contiene datos de red ni de ubicación
/// en vivo: solo lo necesario para volver a abrir la parada, la línea o el
/// destino en el planificador.
class Favorite {
  const Favorite({
    required this.id,
    required this.type,
    required this.name,
    this.latitude,
    this.longitude,
    this.placeSlot,
  });

  static const String homeId = 'place-home';
  static const String workId = 'place-work';

  factory Favorite.place({
    required FavoritePlaceSlot slot,
    required String name,
    required double latitude,
    required double longitude,
  }) {
    return Favorite(
      id: slot == FavoritePlaceSlot.home ? homeId : workId,
      type: FavoriteType.place,
      name: name,
      latitude: latitude,
      longitude: longitude,
      placeSlot: slot,
    );
  }

  factory Favorite.line({required String id, required String name}) {
    return Favorite(id: id, type: FavoriteType.line, name: name);
  }

  factory Favorite.stop({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
  }) {
    return Favorite(
      id: id,
      type: FavoriteType.stop,
      name: name,
      latitude: latitude,
      longitude: longitude,
    );
  }

  factory Favorite.fromJson(Map<String, Object?> json) {
    final typeName = json['type'];
    final type = FavoriteType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    final id = json['id'];
    final name = json['name'];
    if (type == null || id is! String || id.isEmpty || name is! String) {
      throw const FormatException('Favorito inválido');
    }
    final latitudeValue = json['latitude'];
    final longitudeValue = json['longitude'];
    if ((latitudeValue != null && latitudeValue is! num) ||
        (longitudeValue != null && longitudeValue is! num)) {
      throw const FormatException('Coordenadas inválidas');
    }
    final latitude = (latitudeValue as num?)?.toDouble();
    final longitude = (longitudeValue as num?)?.toDouble();
    final placeSlotName = json['placeSlot'];
    final placeSlot = placeSlotName is String
        ? FavoritePlaceSlot.values
              .where((value) => value.name == placeSlotName)
              .firstOrNull
        : null;
    if (type == FavoriteType.place && (latitude == null || longitude == null)) {
      throw const FormatException('El lugar no tiene coordenadas');
    }
    return Favorite(
      id: id,
      type: type,
      name: name,
      latitude: latitude,
      longitude: longitude,
      placeSlot: placeSlot,
    );
  }

  final String id;
  final FavoriteType type;
  final String name;
  final double? latitude;
  final double? longitude;
  final FavoritePlaceSlot? placeSlot;

  String get key => '${type.name}:$id';

  bool get isPlace => type == FavoriteType.place;

  Favorite copyWith({String? name}) => Favorite(
    id: id,
    type: type,
    name: name ?? this.name,
    latitude: latitude,
    longitude: longitude,
    placeSlot: placeSlot,
  );

  Map<String, Object?> toJson() => {
    'type': type.name,
    'id': id,
    'name': name,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (placeSlot != null) 'placeSlot': placeSlot!.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Favorite && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'Favorite($key, "$name")';
}
