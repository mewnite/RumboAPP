import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/data/geolocator_location_repository.dart';

void main() {
  test('reuses only a cached location fix up to 30 seconds old', () {
    final now = DateTime(2026, 11, 19, 12);

    expect(
      GeolocatorLocationRepository.isLocationFixRecent(
        now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      isTrue,
    );
    expect(
      GeolocatorLocationRepository.isLocationFixRecent(
        now.subtract(const Duration(seconds: 31)),
        now: now,
      ),
      isFalse,
    );
  });
}
