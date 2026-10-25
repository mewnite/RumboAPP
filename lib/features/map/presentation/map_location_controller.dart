import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/geolocator_location_repository.dart';
import '../domain/location_repository.dart';

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => GeolocatorLocationRepository(),
);

final mapLocationControllerProvider =
    NotifierProvider<MapLocationController, MapLocationState>(
      MapLocationController.new,
    );

enum MapLocationStatus {
  idle,
  loading,
  available,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  error,
}

class MapLocationState {
  const MapLocationState({this.status = MapLocationStatus.idle, this.location});

  final MapLocationStatus status;
  final DeviceLocation? location;
}

class MapLocationController extends Notifier<MapLocationState> {
  @override
  MapLocationState build() => const MapLocationState();

  Future<void> locate() async {
    state = const MapLocationState(status: MapLocationStatus.loading);
    final repository = ref.read(locationRepositoryProvider);
    try {
      if (!await repository.isLocationServiceEnabled()) {
        state = const MapLocationState(
          status: MapLocationStatus.serviceDisabled,
        );
        return;
      }

      var permission = await repository.checkPermission();
      if (permission == LocationPermissionStatus.denied) {
        permission = await repository.requestPermission();
      }
      if (permission == LocationPermissionStatus.denied) {
        state = const MapLocationState(
          status: MapLocationStatus.permissionDenied,
        );
        return;
      }
      if (permission == LocationPermissionStatus.deniedForever) {
        state = const MapLocationState(
          status: MapLocationStatus.permissionDeniedForever,
        );
        return;
      }

      final location = await repository.getCurrentLocation();
      state = MapLocationState(
        status: MapLocationStatus.available,
        location: location,
      );
    } on LocationRepositoryException {
      state = const MapLocationState(status: MapLocationStatus.error);
    } on Exception {
      state = const MapLocationState(status: MapLocationStatus.error);
    }
  }

  Future<void> openPermissionSettings() async {
    await ref.read(locationRepositoryProvider).openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await ref.read(locationRepositoryProvider).openLocationSettings();
  }
}
