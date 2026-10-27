import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../../../features/trip_planner/domain/trip_planner.dart';

/// Tipo de entidad identificada en el motor de búsqueda.
enum SearchEntityKind {
  stop,
  route,
  address,
  intersection,
  poi,
  neighborhood,
  favorite,
  recentSearch,
}

/// Nivel de precisión geográfica de las coordenadas asociadas.
enum GeoPrecision {
  exactDoorNumber,
  intersectionPoint,
  stopCoordinates,
  rooftopPoi,
  streetSegment,
  approximateArea,
}

/// Procedencia o proveedor de los datos del resultado.
enum SearchDataSource { stmGtfsLocal, ideUruguay, openStreetMap, userStorage }

/// Destino geográfico unificado y estructurado para Rumbo.
class SearchResult {
  const SearchResult({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    required this.precision,
    required this.source,
    this.score = 0.0,
    this.stop,
    this.stopCode,
    this.lines = const [],
    this.externalId,
    this.neighborhood,
  });

  /// Identificador estable y único del resultado.
  final String id;

  /// Tipo de entidad geográfica o de transporte.
  final SearchEntityKind kind;

  /// Nombre principal o encabezado del resultado.
  final String title;

  /// Descripción secundaria o contexto territorial.
  final String subtitle;

  /// Coordenada WGS84 de latitud.
  final double latitude;

  /// Coordenada WGS84 de longitud.
  final double longitude;

  /// Nivel de precisión de las coordenadas.
  final GeoPrecision precision;

  /// Fuente de procedencia de la información.
  final SearchDataSource source;

  /// Puntuación de relevancia calculada por el motor de ranking.
  final double score;

  /// Parada STM original asociada, si el resultado corresponde a una parada.
  final Stop? stop;

  /// Código oficial de parada de 4 dígitos del STM (ej. "3004"), si aplica.
  final String? stopCode;

  /// Líneas de ómnibus asociadas a la parada o recorrido.
  final List<String> lines;

  /// Identificador externo en el proveedor origen (ej. IDU de IDEuy o OSM ID).
  final String? externalId;

  /// Barrio de Montevideo al que pertenece el punto.
  final String? neighborhood;

  /// Convierte este resultado en un [TripEndpoint] apto para el planificador de viajes.
  TripEndpoint toTripEndpoint() {
    if (stop != null) {
      return TripEndpoint.fromStop(stop!);
    }
    if (kind == SearchEntityKind.route) {
      final routeId = id.replaceFirst('stm:route:', '');
      final routeLabel = lines.isNotEmpty
          ? lines.first
          : title.replaceFirst('Línea ', '');
      return TripEndpoint.fromRoute(
        Route(id: routeId, shortName: routeLabel),
        latitude: latitude,
        longitude: longitude,
      );
    }
    return TripEndpoint(name: title, latitude: latitude, longitude: longitude);
  }

  SearchResult copyWith({
    String? id,
    SearchEntityKind? kind,
    String? title,
    String? subtitle,
    double? latitude,
    double? longitude,
    GeoPrecision? precision,
    SearchDataSource? source,
    double? score,
    Stop? stop,
    String? stopCode,
    List<String>? lines,
    String? externalId,
    String? neighborhood,
  }) {
    return SearchResult(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      precision: precision ?? this.precision,
      source: source ?? this.source,
      score: score ?? this.score,
      stop: stop ?? this.stop,
      stopCode: stopCode ?? this.stopCode,
      lines: lines ?? this.lines,
      externalId: externalId ?? this.externalId,
      neighborhood: neighborhood ?? this.neighborhood,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SearchResult(id: $id, kind: $kind, title: "$title", score: ${score.toStringAsFixed(1)})';
}
