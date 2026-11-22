import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../stops_and_lines/domain/transit_models.dart';

const _activeTripStorageKey = 'active_trip_v1';

class ActiveTripSnapshot {
  const ActiveTripSnapshot({
    required this.variantStops,
    required this.destinationStopId,
    required this.targetStopName,
    required this.stopsRemaining,
    required this.progressTitle,
    required this.progressBody,
    required this.progressBodySingular,
    required this.alertTitle,
    required this.alertBody,
    required this.backgroundNotificationText,
    this.isAlightAlertSent = false,
  });

  final List<Stop> variantStops;
  final String destinationStopId;
  final String targetStopName;
  final int stopsRemaining;
  final String progressTitle;
  final String progressBody;
  final String progressBodySingular;
  final String alertTitle;
  final String alertBody;
  final String backgroundNotificationText;
  final bool isAlightAlertSent;

  ActiveTripSnapshot copyWith({int? stopsRemaining, bool? isAlightAlertSent}) =>
      ActiveTripSnapshot(
        variantStops: variantStops,
        destinationStopId: destinationStopId,
        targetStopName: targetStopName,
        stopsRemaining: stopsRemaining ?? this.stopsRemaining,
        progressTitle: progressTitle,
        progressBody: progressBody,
        progressBodySingular: progressBodySingular,
        alertTitle: alertTitle,
        alertBody: alertBody,
        backgroundNotificationText: backgroundNotificationText,
        isAlightAlertSent: isAlightAlertSent ?? this.isAlightAlertSent,
      );

  Map<String, Object?> toJson() => {
    'stops': [
      for (final stop in variantStops)
        {
          'id': stop.id,
          'name': stop.name,
          'latitude': stop.latitude,
          'longitude': stop.longitude,
          'code': stop.code,
          'description': stop.description,
        },
    ],
    'destinationStopId': destinationStopId,
    'targetStopName': targetStopName,
    'stopsRemaining': stopsRemaining,
    'progressTitle': progressTitle,
    'progressBody': progressBody,
    'progressBodySingular': progressBodySingular,
    'alertTitle': alertTitle,
    'alertBody': alertBody,
    'backgroundNotificationText': backgroundNotificationText,
    'isAlightAlertSent': isAlightAlertSent,
  };

  static ActiveTripSnapshot? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final rawStops = value['stops'];
    if (rawStops is! List) return null;
    final stops = <Stop>[];
    for (final rawStop in rawStops) {
      if (rawStop is! Map<String, dynamic>) return null;
      final latitude = _asDouble(rawStop['latitude']);
      final longitude = _asDouble(rawStop['longitude']);
      final id = rawStop['id'];
      final name = rawStop['name'];
      if (latitude == null ||
          longitude == null ||
          id is! String ||
          name is! String ||
          !latitude.isFinite ||
          !longitude.isFinite) {
        return null;
      }
      stops.add(
        Stop(
          id: id,
          name: name,
          latitude: latitude,
          longitude: longitude,
          code: rawStop['code'] is String ? rawStop['code'] as String : '',
          description: rawStop['description'] is String
              ? rawStop['description'] as String
              : '',
        ),
      );
    }

    final destinationStopId = value['destinationStopId'];
    final targetStopName = value['targetStopName'];
    final stopsRemaining = value['stopsRemaining'];
    final progressTitle = value['progressTitle'];
    final progressBody = value['progressBody'];
    final progressBodySingular = value['progressBodySingular'];
    final alertTitle = value['alertTitle'];
    final alertBody = value['alertBody'];
    final backgroundNotificationText = value['backgroundNotificationText'];
    final destinationIndex = stops.indexWhere(
      (stop) => stop.id == destinationStopId,
    );
    if (stops.length < 2 ||
        destinationIndex <= 0 ||
        stopsRemaining is! int ||
        stopsRemaining < 0 ||
        stopsRemaining > destinationIndex ||
        targetStopName is! String ||
        progressTitle is! String ||
        progressBody is! String ||
        progressBodySingular is! String ||
        alertTitle is! String ||
        alertBody is! String ||
        backgroundNotificationText is! String) {
      return null;
    }

    return ActiveTripSnapshot(
      variantStops: List.unmodifiable(stops),
      destinationStopId: destinationStopId as String,
      targetStopName: targetStopName,
      stopsRemaining: stopsRemaining,
      progressTitle: progressTitle,
      progressBody: progressBody,
      progressBodySingular: progressBodySingular,
      alertTitle: alertTitle,
      alertBody: alertBody,
      backgroundNotificationText: backgroundNotificationText,
      isAlightAlertSent: value['isAlightAlertSent'] == true,
    );
  }

  static double? _asDouble(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
}

abstract interface class ActiveTripStorage {
  Future<ActiveTripSnapshot?> read();
  Future<void> write(ActiveTripSnapshot snapshot);
  Future<void> clear();
}

class SharedPreferencesActiveTripStorage implements ActiveTripStorage {
  @override
  Future<ActiveTripSnapshot?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_activeTripStorageKey);
    if (encoded == null) return null;
    try {
      final snapshot = ActiveTripSnapshot.fromJson(jsonDecode(encoded));
      if (snapshot != null) return snapshot;
    } on FormatException {
      // Drop only a malformed active-trip record; other preferences are intact.
    }
    await preferences.remove(_activeTripStorageKey);
    return null;
  }

  @override
  Future<void> write(ActiveTripSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _activeTripStorageKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_activeTripStorageKey);
  }
}
