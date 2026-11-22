import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/location_repository.dart';
import '../../map/presentation/map_location_controller.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../data/active_trip_notifications.dart';
import '../data/active_trip_storage.dart';
import '../domain/active_trip_tracker.dart';

final activeTripNotificationsProvider = Provider<ActiveTripNotifications>(
  (ref) => LocalActiveTripNotifications(),
);

final activeTripStorageProvider = Provider<ActiveTripStorage>(
  (ref) => SharedPreferencesActiveTripStorage(),
);

final activeTripControllerProvider =
    NotifierProvider<ActiveTripController, ActiveTripState>(
      ActiveTripController.new,
    );

enum ActiveTripStartResult {
  started,
  alreadyActive,
  unsupportedPlatform,
  serviceDisabled,
  locationPermissionRequired,
  backgroundPermissionRequired,
  locationUnavailable,
  notificationsPermissionRequired,
  storageUnavailable,
  invalidRoute,
}

class ActiveTripState {
  const ActiveTripState({
    this.isActive = false,
    this.isTracking = false,
    this.targetStopName,
    this.stopsRemaining,
    this.isAlightAlertSent = false,
    this.error,
  });

  final bool isActive;
  final bool isTracking;
  final String? targetStopName;
  final int? stopsRemaining;
  final bool isAlightAlertSent;
  final String? error;
}

class ActiveTripController extends Notifier<ActiveTripState> {
  StreamSubscription<DeviceLocation>? _subscription;
  ActiveTripTracker? _tracker;
  ActiveTripSnapshot? _snapshot;
  Future<void> _restoreFuture = Future<void>.value();
  bool _disposed = false;

  @override
  ActiveTripState build() {
    _restoreFuture = _restoreSavedTrip();
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
      // The operating system owns the foreground service while the app is
      // backgrounded. A process restart rehydrates its progress from storage.
    });
    return const ActiveTripState();
  }

  Future<void> get ready => _restoreFuture;

  Future<ActiveTripStartResult> start({
    required List<Stop> variantStops,
    required Stop destinationStop,
    required String progressTitle,
    required String progressBody,
    required String progressBodySingular,
    required String alertTitle,
    required String alertBody,
    required String backgroundNotificationText,
  }) async {
    await _restoreFuture;
    if (state.isActive) return ActiveTripStartResult.alreadyActive;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return ActiveTripStartResult.unsupportedPlatform;
    }
    final targetIndex = variantStops.indexWhere(
      (stop) => stop.id == destinationStop.id,
    );
    if (targetIndex <= 0) return ActiveTripStartResult.invalidRoute;

    final locationRepository = ref.read(locationRepositoryProvider);
    if (!await locationRepository.isLocationServiceEnabled()) {
      return ActiveTripStartResult.serviceDisabled;
    }
    var locationPermission = await locationRepository.checkPermission();
    if (locationPermission != LocationPermissionStatus.granted) {
      locationPermission = await locationRepository.requestPermission();
    }
    if (locationPermission != LocationPermissionStatus.granted) {
      return ActiveTripStartResult.locationPermissionRequired;
    }
    // Android's foreground location service can continue an explicitly
    // started trip with while-in-use permission. iOS requires Always access
    // to keep location updates running after the app is backgrounded.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !await locationRepository.hasBackgroundPermission() &&
        !await locationRepository.requestBackgroundPermission()) {
      return ActiveTripStartResult.backgroundPermissionRequired;
    }

    final notifications = ref.read(activeTripNotificationsProvider);
    if (!await notifications.requestPermission()) {
      return ActiveTripStartResult.notificationsPermissionRequired;
    }

    final DeviceLocation initialLocation;
    try {
      initialLocation = await locationRepository.getCurrentLocation();
    } on LocationRepositoryException {
      return ActiveTripStartResult.locationUnavailable;
    }

    final tracker = ActiveTripTracker(
      stops: variantStops,
      destinationStopId: destinationStop.id,
    );
    final initialProgress = tracker.update(
      initialLocation.latitude,
      initialLocation.longitude,
    );
    final snapshot = ActiveTripSnapshot(
      variantStops: List.unmodifiable(variantStops),
      destinationStopId: destinationStop.id,
      targetStopName: destinationStop.name,
      stopsRemaining: initialProgress.stopsRemaining,
      progressTitle: progressTitle,
      progressBody: progressBody,
      progressBodySingular: progressBodySingular,
      alertTitle: alertTitle,
      alertBody: alertBody,
      backgroundNotificationText: backgroundNotificationText,
      isAlightAlertSent: initialProgress.shouldAlert,
    );
    try {
      await ref.read(activeTripStorageProvider).write(snapshot);
    } on Exception {
      return ActiveTripStartResult.storageUnavailable;
    }

    _snapshot = snapshot;
    _tracker = tracker;
    state = ActiveTripState(
      isActive: true,
      isTracking: true,
      targetStopName: destinationStop.name,
      stopsRemaining: initialProgress.stopsRemaining,
      isAlightAlertSent: initialProgress.shouldAlert,
    );
    await _showProgress(snapshot, initialProgress.stopsRemaining);
    if (initialProgress.shouldAlert) {
      await notifications.showAlightAlert(
        alertTitle,
        alertBody.replaceAll('{stop}', destinationStop.name),
      );
    }
    _listenForLocation(locationRepository, snapshot);
    return ActiveTripStartResult.started;
  }

  Future<void> _restoreSavedTrip() async {
    ActiveTripSnapshot? snapshot;
    try {
      snapshot = await ref.read(activeTripStorageProvider).read();
    } on Exception {
      return;
    }
    if (!ref.mounted || _disposed || snapshot == null) return;
    final destinationIndex = snapshot.variantStops.indexWhere(
      (stop) => stop.id == snapshot!.destinationStopId,
    );
    if (destinationIndex <= 0) {
      await ref.read(activeTripStorageProvider).clear();
      return;
    }
    _snapshot = snapshot;
    final restoredTracker = ActiveTripTracker(
      stops: snapshot.variantStops,
      destinationStopId: snapshot.destinationStopId,
      initialFurthestIndex: destinationIndex - snapshot.stopsRemaining,
    );
    if (snapshot.isAlightAlertSent) restoredTracker.markAlightAlertSent();
    _tracker = restoredTracker;
    state = ActiveTripState(
      isActive: true,
      targetStopName: snapshot.targetStopName,
      stopsRemaining: snapshot.stopsRemaining,
      isAlightAlertSent: snapshot.isAlightAlertSent,
    );

    final locationRepository = ref.read(locationRepositoryProvider);
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS) ||
        !await locationRepository.isLocationServiceEnabled() ||
        await locationRepository.checkPermission() !=
            LocationPermissionStatus.granted ||
        (defaultTargetPlatform == TargetPlatform.iOS &&
            !await locationRepository.hasBackgroundPermission())) {
      return;
    }
    if (!ref.mounted || _disposed) return;
    state = ActiveTripState(
      isActive: true,
      isTracking: true,
      targetStopName: snapshot.targetStopName,
      stopsRemaining: snapshot.stopsRemaining,
      isAlightAlertSent: snapshot.isAlightAlertSent,
    );
    try {
      await _showProgress(snapshot, snapshot.stopsRemaining);
    } on Exception {
      // The saved trip remains available even if notification access changed.
    }
    _listenForLocation(locationRepository, snapshot);
  }

  void _listenForLocation(
    LocationRepository locationRepository,
    ActiveTripSnapshot snapshot,
  ) {
    _subscription = locationRepository
        .watchActiveTripLocation(
          notificationTitle: snapshot.progressTitle,
          notificationText: snapshot.backgroundNotificationText,
        )
        .listen(
          (position) => unawaited(_onLocation(position)),
          onError: (Object error, StackTrace stack) {
            if (_disposed || !ref.mounted) return;
            state = ActiveTripState(
              isActive: true,
              targetStopName: state.targetStopName,
              stopsRemaining: state.stopsRemaining,
              isAlightAlertSent: state.isAlightAlertSent,
              error: error.toString(),
            );
          },
        );
  }

  Future<void> _onLocation(DeviceLocation position) async {
    final tracker = _tracker;
    final snapshot = _snapshot;
    if (tracker == null || snapshot == null || _disposed || !ref.mounted) {
      return;
    }
    final progress = tracker.update(position.latitude, position.longitude);
    final countChanged = state.stopsRemaining != progress.stopsRemaining;
    final alertChanged = progress.shouldAlert && !state.isAlightAlertSent;
    if (!countChanged && !alertChanged) return;

    final updatedSnapshot = snapshot.copyWith(
      stopsRemaining: progress.stopsRemaining,
      isAlightAlertSent: state.isAlightAlertSent || alertChanged,
    );
    _snapshot = updatedSnapshot;
    try {
      await ref.read(activeTripStorageProvider).write(updatedSnapshot);
    } on Exception {
      // In-memory progress and user notifications still update if storage is
      // temporarily unavailable; the next position retries persistence.
    }
    state = ActiveTripState(
      isActive: true,
      isTracking: true,
      targetStopName: snapshot.targetStopName,
      stopsRemaining: progress.stopsRemaining,
      isAlightAlertSent: updatedSnapshot.isAlightAlertSent,
    );
    if (countChanged) {
      await _showProgress(updatedSnapshot, progress.stopsRemaining);
    }
    if (alertChanged) {
      await ref
          .read(activeTripNotificationsProvider)
          .showAlightAlert(
            snapshot.alertTitle,
            snapshot.alertBody.replaceAll('{stop}', snapshot.targetStopName),
          );
    }
  }

  Future<void> _showProgress(
    ActiveTripSnapshot snapshot,
    int stopsRemaining,
  ) async {
    final template = stopsRemaining == 1
        ? snapshot.progressBodySingular
        : snapshot.progressBody;
    await ref
        .read(activeTripNotificationsProvider)
        .showProgress(
          snapshot.progressTitle,
          template
              .replaceAll('{stops}', '$stopsRemaining')
              .replaceAll('{stop}', snapshot.targetStopName),
        );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _tracker = null;
    _snapshot = null;
    await ref.read(activeTripStorageProvider).clear();
    state = const ActiveTripState();
    await ref.read(activeTripNotificationsProvider).cancel();
  }
}
