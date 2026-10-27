import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class ActiveTripNotifications {
  Future<bool> requestPermission();
  Future<void> showProgress(String title, String body);
  Future<void> showAlightAlert(String title, String body);
  Future<void> cancel();
}

class LocalActiveTripNotifications implements ActiveTripNotifications {
  LocalActiveTripNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _progressId = 7411;
  static const _alertId = 7412;
  static const _channelId = 'active_trip';
  static const _channelName = 'Viaje activo';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _initialize();
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: false) ??
          false;
    }
    return false;
  }

  NotificationDetails _details({required bool alert}) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Progreso y avisos del viaje activo.',
      importance: alert ? Importance.high : Importance.low,
      priority: alert ? Priority.high : Priority.low,
      ongoing: !alert,
      onlyAlertOnce: true,
      playSound: false,
    ),
    iOS: DarwinNotificationDetails(
      // Progress updates replace the same notification id, so each stop
      // refreshes the count without accumulating a separate notification.
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    ),
  );

  @override
  Future<void> showProgress(String title, String body) async {
    await _initialize();
    await _plugin.show(
      id: _progressId,
      title: title,
      body: body,
      notificationDetails: _details(alert: false),
    );
  }

  @override
  Future<void> showAlightAlert(String title, String body) async {
    await _initialize();
    await _plugin.show(
      id: _alertId,
      title: title,
      body: body,
      notificationDetails: _details(alert: true),
    );
  }

  @override
  Future<void> cancel() async {
    await _initialize();
    await _plugin.cancel(id: _progressId);
    await _plugin.cancel(id: _alertId);
  }
}
