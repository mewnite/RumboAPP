import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_detail/data/active_trip_storage.dart';

void main() {
  test('round trips the selected stop sequence and remaining count', () {
    const snapshot = ActiveTripSnapshot(
      variantStops: [
        Stop(id: 'a', name: 'Subida', latitude: -34.9, longitude: -56.2),
        Stop(id: 'b', name: 'Destino', latitude: -34.91, longitude: -56.21),
      ],
      destinationStopId: 'b',
      targetStopName: 'Destino',
      stopsRemaining: 1,
      progressTitle: 'Viaje activo',
      progressBody: '{stops} paradas hasta {stop}',
      progressBodySingular: 'Queda 1 parada hasta {stop}',
      alertTitle: 'Próxima parada',
      alertBody: 'Bajar en {stop}',
      backgroundNotificationText: 'Seguimiento activo',
    );

    final restored = ActiveTripSnapshot.fromJson(snapshot.toJson());

    expect(restored, isNotNull);
    expect(restored!.variantStops.map((stop) => stop.id), ['a', 'b']);
    expect(restored.destinationStopId, 'b');
    expect(restored.stopsRemaining, 1);
    expect(restored.variantStops.last.latitude, -34.91);
  });

  test('rejects incomplete or inconsistent saved route data', () {
    expect(ActiveTripSnapshot.fromJson({'stops': []}), isNull);
    expect(
      ActiveTripSnapshot.fromJson({
        ..._validSnapshot(),
        'destinationStopId': 'missing',
      }),
      isNull,
    );
    expect(
      ActiveTripSnapshot.fromJson({..._validSnapshot(), 'stopsRemaining': 5}),
      isNull,
    );
  });
}

Map<String, Object?> _validSnapshot() => const ActiveTripSnapshot(
  variantStops: [
    Stop(id: 'a', name: 'Subida', latitude: -34.9, longitude: -56.2),
    Stop(id: 'b', name: 'Destino', latitude: -34.91, longitude: -56.21),
  ],
  destinationStopId: 'b',
  targetStopName: 'Destino',
  stopsRemaining: 1,
  progressTitle: 'Viaje activo',
  progressBody: '{stops} paradas hasta {stop}',
  progressBodySingular: 'Queda 1 parada hasta {stop}',
  alertTitle: 'Próxima parada',
  alertBody: 'Bajar en {stop}',
  backgroundNotificationText: 'Seguimiento activo',
).toJson();
