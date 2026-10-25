/// Parámetros del planificador de viajes.
///
/// Todos los valores que afectan la búsqueda viven acá para que la UI y el
/// dominio usen exactamente los mismos límites.
class PlannerConfig {
  const PlannerConfig({
    this.detourFactor = 1.3,
    this.walkingSpeedKmh = 4.8,
    this.maximumWalkingMeters = 800,
    this.maximumTransferWalkingMeters = 150,
    this.minimumTransferTime = const Duration(minutes: 3),
    this.maximumTransfers = 1,
    this.maximumWait = const Duration(minutes: 45),
    this.resultLimit = 5,
  });

  /// Opciones que ofrece la pantalla de resultados para la caminata máxima.
  static const walkingOptionsMeters = <double>[400, 800, 1200];

  /// Multiplica la distancia en línea recta para estimar el rodeo peatonal.
  final double detourFactor;

  /// Velocidad de caminata en km/h.
  final double walkingSpeedKmh;

  /// Máximo de caminata estimada (con rodeo) para un itinerario.
  final double maximumWalkingMeters;

  /// Separación máxima en línea recta entre dos paradas para transbordar a pie.
  final double maximumTransferWalkingMeters;

  /// Tiempo mínimo entre la llegada de un viaje y la salida del siguiente.
  final Duration minimumTransferTime;

  /// Cantidad máxima de transbordos (la V1 solo contempla 0 o 1).
  final int maximumTransfers;

  /// Espera máxima antes de abordar, incluido el tramo peatonal del transbordo.
  final Duration maximumWait;

  /// Cantidad máxima de itinerarios devueltos.
  final int resultLimit;

  double get walkingSpeedMetersPerSecond => walkingSpeedKmh / 3.6;

  PlannerConfig copyWith({
    double? detourFactor,
    double? walkingSpeedKmh,
    double? maximumWalkingMeters,
    double? maximumTransferWalkingMeters,
    Duration? minimumTransferTime,
    int? maximumTransfers,
    Duration? maximumWait,
    int? resultLimit,
  }) => PlannerConfig(
    detourFactor: detourFactor ?? this.detourFactor,
    walkingSpeedKmh: walkingSpeedKmh ?? this.walkingSpeedKmh,
    maximumWalkingMeters: maximumWalkingMeters ?? this.maximumWalkingMeters,
    maximumTransferWalkingMeters:
        maximumTransferWalkingMeters ?? this.maximumTransferWalkingMeters,
    minimumTransferTime: minimumTransferTime ?? this.minimumTransferTime,
    maximumTransfers: maximumTransfers ?? this.maximumTransfers,
    maximumWait: maximumWait ?? this.maximumWait,
    resultLimit: resultLimit ?? this.resultLimit,
  );
}
