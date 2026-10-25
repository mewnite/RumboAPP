/// A location reading kept in memory for the current screen only.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

enum LocationPermissionStatus { denied, deniedForever, granted }

abstract interface class LocationRepository {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();
  Future<DeviceLocation> getCurrentLocation();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

enum LocationFailure { unavailable, timeout, unknown }

class LocationRepositoryException implements Exception {
  const LocationRepositoryException(this.failure);

  final LocationFailure failure;
}
