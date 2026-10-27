import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/domain/location_repository.dart';
import 'package:rumbo/features/map/presentation/map_location_controller.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/trip_detail/data/active_trip_notifications.dart';
import 'package:rumbo/features/trip_detail/presentation/active_trip_controller.dart';

class _StreamingLocationRepository implements LocationRepository {
  final StreamController<DeviceLocation> locations = StreamController();

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<bool> hasBackgroundPermission() async => true;
  @override
  Future<bool> requestBackgroundPermission() async => true;
  @override
  Future<DeviceLocation> getCurrentLocation() async => const DeviceLocation(
    latitude: -34.9,
    longitude: -56.2,
    accuracyMeters: 5,
  );
  @override
  Stream<DeviceLocation> watchActiveTripLocation({
    required String notificationTitle,
    required String notificationText,
  }) => locations.stream;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class _RecordingNotifications implements ActiveTripNotifications {
  final List<(String, String)> progress = [];
  final List<(String, String)> alerts = [];
  int cancelCount = 0;

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showProgress(String title, String body) async =>
      progress.add((title, body));
  @override
  Future<void> showAlightAlert(String title, String body) async =>
      alerts.add((title, body));
  @override
  Future<void> cancel() async => cancelCount++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts local background tracking and stops it with the trip', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final locations = _StreamingLocationRepository();
    final notifications = _RecordingNotifications();
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(locations),
        activeTripNotificationsProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(locations.locations.close);

    const stops = [
      Stop(id: 'a', name: 'Subida', latitude: -34.9, longitude: -56.20),
      Stop(id: 'b', name: 'Una antes', latitude: -34.9, longitude: -56.19),
      Stop(id: 'c', name: 'Dos antes', latitude: -34.9, longitude: -56.18),
      Stop(id: 'd', name: 'Bajada', latitude: -34.9, longitude: -56.17),
    ];
    final notifier = container.read(activeTripControllerProvider.notifier);
    final result = await notifier.start(
      variantStops: stops,
      destinationStop: stops.last,
      progressTitle: 'Viaje activo',
      progressBody: '{stops} paradas hasta {stop}',
      alertTitle: 'Próxima parada',
      alertBody: 'Bajar en {stop}',
      backgroundNotificationText: 'Seguimiento activo',
    );

    expect(result, ActiveTripStartResult.started);
    locations.locations.add(
      const DeviceLocation(
        latitude: -34.9,
        longitude: -56.18,
        accuracyMeters: 8,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(activeTripControllerProvider).isActive, isTrue);
    expect(notifications.progress.last.$2, '1 paradas hasta Bajada');
    expect(notifications.alerts.single.$2, 'Bajar en Bajada');

    await notifier.stop();
    expect(container.read(activeTripControllerProvider).isActive, isFalse);
    expect(notifications.cancelCount, 1);
  });
}
