import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/data/geolocator_location_repository.dart';
import 'package:rumbo/features/map/domain/location_repository.dart';

void main() {
  final now = DateTime(2026, 11, 27, 12);

  test('accepts a recent coordinate and preserves its reported accuracy', () {
    expect(
      GeolocatorLocationRepository.validateLocationFix(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 18.4,
        timestamp: now.subtract(const Duration(seconds: 2)),
        now: now,
      ),
      isNull,
    );

    const location = DeviceLocation(
      latitude: -34.9,
      longitude: -56.2,
      accuracyMeters: 18.4,
      reducedAccuracy: false,
    );
    expect(location.accuracyMeters, 18.4);
    expect(location.isApproximate, isFalse);
  });

  test('rejects a stale timestamp and a timestamp from the future', () {
    expect(
      GeolocatorLocationRepository.validateLocationFix(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 18,
        timestamp: now.subtract(const Duration(seconds: 16)),
        now: now,
      ),
      LocationFailure.stale,
    );
    expect(
      GeolocatorLocationRepository.validateLocationFix(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 18,
        timestamp: now.add(const Duration(seconds: 1)),
        now: now,
      ),
      LocationFailure.stale,
    );
  });

  test('rejects invalid coordinates and invalid accuracy values', () {
    for (final (latitude, longitude, accuracy) in [
      (91.0, -56.2, 10.0),
      (-34.9, 181.0, 10.0),
      (double.nan, -56.2, 10.0),
      (-34.9, double.infinity, 10.0),
      (-34.9, -56.2, double.nan),
      (-34.9, -56.2, -1.0),
    ]) {
      expect(
        GeolocatorLocationRepository.validateLocationFix(
          latitude: latitude,
          longitude: longitude,
          accuracyMeters: accuracy,
          timestamp: now,
          now: now,
        ),
        LocationFailure.invalid,
      );
    }
  });

  test(
    'keeps reduced or low-precision fixes usable and labels uncertainty',
    () {
      const reducedPermission = DeviceLocation(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 760,
        reducedAccuracy: true,
      );
      const poorReportedAccuracy = DeviceLocation(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 130,
      );

      expect(reducedPermission.isApproximate, isTrue);
      expect(poorReportedAccuracy.isApproximate, isTrue);
      expect(reducedPermission.accuracyMeters, 760);
      expect(poorReportedAccuracy.accuracyMeters, 130);
    },
  );

  test(
    'marks only a fresh device fix as usable for an initial trip origin',
    () {
      final fresh = DeviceLocation(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 18,
        capturedAt: now.subtract(const Duration(seconds: 10)),
      );
      final stale = DeviceLocation(
        latitude: -34.9,
        longitude: -56.2,
        accuracyMeters: 18,
        capturedAt: now.subtract(const Duration(seconds: 16)),
      );

      expect(fresh.isFreshAt(now), isTrue);
      expect(stale.isFreshAt(now), isFalse);
      expect(
        const DeviceLocation(
          latitude: -34.9,
          longitude: -56.2,
          accuracyMeters: 18,
        ).isFreshAt(now),
        isFalse,
      );
    },
  );
}
