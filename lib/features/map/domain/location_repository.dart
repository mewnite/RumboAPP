/// A location reading kept in memory for the current screen only.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.capturedAt,
    this.reducedAccuracy = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime? capturedAt;
  final bool reducedAccuracy;

  /// This classifies the reported uncertainty; it never rejects the fix.
  bool get isApproximate => reducedAccuracy || accuracyMeters > 100;

  bool isFreshAt(DateTime now) {
    final timestamp = capturedAt;
    if (timestamp == null) return false;
    final age = now.difference(timestamp);
    return !age.isNegative && age <= const Duration(seconds: 15);
  }
}

enum LocationPermissionStatus { denied, deniedForever, granted }

abstract interface class LocationRepository {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();
  Future<bool> hasBackgroundPermission();
  Future<bool> requestBackgroundPermission();
  Future<DeviceLocation> getCurrentLocation();
  Stream<DeviceLocation> watchActiveTripLocation({
    required String notificationTitle,
    required String notificationText,
  });
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

enum LocationFailure {
  unavailable,
  serviceDisabled,
  permissionDenied,
  timeout,
  stale,
  invalid,
  unknown,
}

class LocationRepositoryException implements Exception {
  const LocationRepositoryException(this.failure);

  final LocationFailure failure;
}
