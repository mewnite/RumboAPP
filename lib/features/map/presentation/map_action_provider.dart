import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stops_and_lines/domain/transit_models.dart';
import '../../trip_planner/domain/trip_planner.dart';

/// Acción pendiente que Favoritos deja al mapa para abrir una línea o el
/// planificador con un destino ya elegido.
sealed class MapAction {
  const MapAction();
}

class ShowRouteOnMap extends MapAction {
  const ShowRouteOnMap(this.route);

  final Route route;
}

class PlanTripToPlace extends MapAction {
  const PlanTripToPlace(this.destination);

  final TripEndpoint destination;
}

final mapActionProvider = NotifierProvider<MapActionController, MapAction?>(
  MapActionController.new,
);

class MapActionController extends Notifier<MapAction?> {
  @override
  MapAction? build() => null;

  void showRoute(Route route) => state = ShowRouteOnMap(route);

  void planTo(TripEndpoint destination) => state = PlanTripToPlace(destination);

  void clear() => state = null;
}
