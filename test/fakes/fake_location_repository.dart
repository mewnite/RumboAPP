import 'package:rumbo/features/map/domain/location_repository.dart';

class FakeLocationRepository implements LocationRepository {
  bool serviceEnabled = true;
  LocationPermissionStatus checkedPermission = LocationPermissionStatus.granted;
  LocationPermissionStatus requestedPermission =
      LocationPermissionStatus.granted;
  DeviceLocation location = const DeviceLocation(
    latitude: -34.9058,
    longitude: -56.1991,
    accuracyMeters: 18,
  );
  LocationRepositoryException? locationFailure;
  bool backgroundPermissionGranted = true;

  int serviceChecks = 0;
  int permissionChecks = 0;
  int permissionRequests = 0;
  int locationReads = 0;
  int appSettingsOpens = 0;
  int locationSettingsOpens = 0;

  @override
  Future<bool> isLocationServiceEnabled() async {
    serviceChecks++;
    return serviceEnabled;
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    permissionChecks++;
    return checkedPermission;
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    permissionRequests++;
    return requestedPermission;
  }

  @override
  Future<bool> hasBackgroundPermission() async => backgroundPermissionGranted;

  @override
  Future<bool> requestBackgroundPermission() async =>
      backgroundPermissionGranted;

  @override
  Future<DeviceLocation> getCurrentLocation() async {
    locationReads++;
    final failure = locationFailure;
    if (failure != null) throw failure;
    return location;
  }

  @override
  Stream<DeviceLocation> watchActiveTripLocation({
    required String notificationTitle,
    required String notificationText,
  }) => const Stream<DeviceLocation>.empty();

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpens++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpens++;
    return true;
  }
}
