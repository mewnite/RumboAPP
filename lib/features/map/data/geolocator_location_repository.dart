import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/location_repository.dart';

class GeolocatorLocationRepository implements LocationRepository {
  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      _mapPermission(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      _mapPermission(await Geolocator.requestPermission());

  @override
  Future<bool> hasBackgroundPermission() async =>
      await Geolocator.checkPermission() == LocationPermission.always;

  @override
  Future<bool> requestBackgroundPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always;
  }

  @override
  Future<DeviceLocation> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on LocationServiceDisabledException {
      throw const LocationRepositoryException(LocationFailure.unavailable);
    } on PermissionDeniedException {
      throw const LocationRepositoryException(LocationFailure.unavailable);
    } on Exception catch (error) {
      if (error.toString().contains('TimeoutException')) {
        throw const LocationRepositoryException(LocationFailure.timeout);
      }
      throw const LocationRepositoryException(LocationFailure.unknown);
    }
  }

  @override
  Stream<DeviceLocation> watchActiveTripLocation({
    required String notificationTitle,
    required String notificationText,
  }) {
    final LocationSettings settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          notificationChannelName: notificationTitle,
          enableWakeLock: false,
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 20,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    };
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      ),
    );
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.whileInUse ||
      LocationPermission.always => LocationPermissionStatus.granted,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationPermissionStatus.denied,
    };
  }
}
