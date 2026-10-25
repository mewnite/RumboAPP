import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/map/domain/location_repository.dart';
import 'package:rumbo/features/map/presentation/map_location_controller.dart';

import 'fakes/fake_location_repository.dart';

void main() {
  late FakeLocationRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeLocationRepository();
    container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWith((ref) => repository)],
    );
  });

  tearDown(() => container.dispose());

  test('uses an already granted foreground permission', () async {
    await container.read(mapLocationControllerProvider.notifier).locate();

    expect(
      container.read(mapLocationControllerProvider).status,
      MapLocationStatus.available,
    );
    expect(repository.permissionRequests, 0);
    expect(repository.locationReads, 1);
  });

  test('reports denied permission and permits a later retry', () async {
    repository.checkedPermission = LocationPermissionStatus.denied;
    repository.requestedPermission = LocationPermissionStatus.denied;

    await container.read(mapLocationControllerProvider.notifier).locate();

    expect(
      container.read(mapLocationControllerProvider).status,
      MapLocationStatus.permissionDenied,
    );
    expect(repository.permissionRequests, 1);
    expect(repository.locationReads, 0);
  });

  test('does not request a permission denied permanently', () async {
    repository.checkedPermission = LocationPermissionStatus.deniedForever;

    await container.read(mapLocationControllerProvider.notifier).locate();

    expect(
      container.read(mapLocationControllerProvider).status,
      MapLocationStatus.permissionDeniedForever,
    );
    expect(repository.permissionRequests, 0);
    await container
        .read(mapLocationControllerProvider.notifier)
        .openPermissionSettings();
    expect(repository.appSettingsOpens, 1);
  });

  test(
    'reports disabled location service without checking permissions',
    () async {
      repository.serviceEnabled = false;

      await container.read(mapLocationControllerProvider.notifier).locate();

      expect(
        container.read(mapLocationControllerProvider).status,
        MapLocationStatus.serviceDisabled,
      );
      expect(repository.permissionChecks, 0);
      await container
          .read(mapLocationControllerProvider.notifier)
          .openLocationSettings();
      expect(repository.locationSettingsOpens, 1);
    },
  );

  test('turns repository failures into a recoverable error state', () async {
    repository.locationFailure = const LocationRepositoryException(
      LocationFailure.timeout,
    );

    await container.read(mapLocationControllerProvider.notifier).locate();

    expect(
      container.read(mapLocationControllerProvider).status,
      MapLocationStatus.error,
    );
  });
}
