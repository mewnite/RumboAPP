import 'dart:math' as math;

import '../../stops_and_lines/domain/transit_models.dart';

class ActiveTripProgress {
  const ActiveTripProgress({
    required this.stopsRemaining,
    required this.distanceToDestinationMeters,
    required this.shouldAlert,
  });

  final int stopsRemaining;
  final double distanceToDestinationMeters;
  final bool shouldAlert;
}

/// Tracks forward progress along an ordered variant stop sequence.
class ActiveTripTracker {
  ActiveTripTracker({
    required List<Stop> stops,
    required this.destinationStopId,
  }) : stops = List.unmodifiable(stops),
       destinationIndex = stops.indexWhere(
         (stop) => stop.id == destinationStopId,
       );

  final List<Stop> stops;
  final String destinationStopId;
  final int destinationIndex;
  int _furthestIndex = 0;
  bool _hasAlerted = false;

  ActiveTripProgress update(double latitude, double longitude) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index <= destinationIndex; index++) {
      final stop = stops[index];
      final distance = _distanceMeters(
        latitude,
        longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    _furthestIndex = math.max(_furthestIndex, nearestIndex);
    final remaining = math.max(0, destinationIndex - _furthestIndex);
    final destination = stops[destinationIndex];
    final destinationDistance = _distanceMeters(
      latitude,
      longitude,
      destination.latitude,
      destination.longitude,
    );
    final shouldAlert =
        !_hasAlerted &&
        (destinationDistance <= 300 || (_furthestIndex > 0 && remaining <= 2));
    if (shouldAlert) _hasAlerted = true;
    return ActiveTripProgress(
      stopsRemaining: remaining,
      distanceToDestinationMeters: destinationDistance,
      shouldAlert: shouldAlert,
    );
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return 6371000 *
        math.asin(
          math.sqrt(
            math.pow(math.sin((lat2 - lat1) * math.pi / 360), 2) +
                math.cos(lat1 * math.pi / 180) *
                    math.cos(lat2 * math.pi / 180) *
                    math.pow(math.sin((lon2 - lon1) * math.pi / 360), 2),
          ),
        );
  }
}
