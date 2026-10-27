import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/presentation/map_location_controller.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../data/active_trip_notifications.dart';
import '../domain/active_trip_tracker.dart';

final activeTripNotificationsProvider = Provider<ActiveTripNotifications>(
  (ref) => LocalActiveTripNotifications(),
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
  backgroundPermissionRequired,
  notificationsPermissionRequired,
  invalidRoute,
}

class ActiveTripState {
  const ActiveTripState({
    this.isActive = false,
    this.targetStopName,
    this.stopsRemaining,
    this.isAlightAlertSent = false,
    this.error,
  });

  final bool isActive;
  final String? targetStopName;
  final int? stopsRemaining;
  final bool isAlightAlertSent;
  final String? error;
}

class ActiveTripController extends Notifier<ActiveTripState> {
  StreamSubscription? _subscription;
  ActiveTripTracker? _tracker;
  ActiveTripNotifications? _notifications;
  bool _disposed = false;

  @override
  ActiveTripState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
      final notifications = _notifications;
      if (notifications != null) unawaited(notifications.cancel());
    });
    return const ActiveTripState();
  }

  Future<ActiveTripStartResult> start({
    required List<Stop> variantStops,
    required Stop destinationStop,
    required String progressTitle,
    required String progressBody,
    required String alertTitle,
    required String alertBody,
    required String backgroundNotificationText,
  }) async {
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
    if (!await locationRepository.hasBackgroundPermission() &&
        !await locationRepository.requestBackgroundPermission()) {
      return ActiveTripStartResult.backgroundPermissionRequired;
    }
    final notifications = ref.read(activeTripNotificationsProvider);
    _notifications = notifications;
    if (!await notifications.requestPermission()) {
      return ActiveTripStartResult.notificationsPermissionRequired;
    }

    _tracker = ActiveTripTracker(
      stops: variantStops,
      destinationStopId: destinationStop.id,
    );
    state = ActiveTripState(
      isActive: true,
      targetStopName: destinationStop.name,
      stopsRemaining: targetIndex,
    );
    _subscription = locationRepository
        .watchActiveTripLocation(
          notificationTitle: progressTitle,
          notificationText: backgroundNotificationText,
        )
        .listen(
          (position) => unawaited(
            _onLocation(
              position.latitude,
              position.longitude,
              progressTitle,
              progressBody,
              alertTitle,
              alertBody,
            ),
          ),
          onError: (Object error, StackTrace stack) {
            if (_disposed) return;
            state = ActiveTripState(error: error.toString());
            unawaited(_subscription?.cancel());
            unawaited(notifications.cancel());
          },
        );
    return ActiveTripStartResult.started;
  }

  Future<void> _onLocation(
    double latitude,
    double longitude,
    String progressTitle,
    String progressBody,
    String alertTitle,
    String alertBody,
  ) async {
    final tracker = _tracker;
    if (tracker == null || _disposed) return;
    final progress = tracker.update(latitude, longitude);
    final targetName = state.targetStopName ?? '';
    if (state.stopsRemaining != progress.stopsRemaining) {
      state = ActiveTripState(
        isActive: true,
        targetStopName: targetName,
        stopsRemaining: progress.stopsRemaining,
        isAlightAlertSent: state.isAlightAlertSent,
      );
      await ref
          .read(activeTripNotificationsProvider)
          .showProgress(
            progressTitle,
            progressBody
                .replaceAll('{stops}', '${progress.stopsRemaining}')
                .replaceAll('{stop}', targetName),
          );
    }
    if (progress.shouldAlert) {
      state = ActiveTripState(
        isActive: true,
        targetStopName: targetName,
        stopsRemaining: progress.stopsRemaining,
        isAlightAlertSent: true,
      );
      await ref
          .read(activeTripNotificationsProvider)
          .showAlightAlert(
            alertTitle,
            alertBody.replaceAll('{stop}', targetName),
          );
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _tracker = null;
    state = const ActiveTripState();
    await ref.read(activeTripNotificationsProvider).cancel();
    _notifications = null;
  }
}
