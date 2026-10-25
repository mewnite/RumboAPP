import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/map_config.dart';
import '../../../core/config/transit_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/favorites/domain/favorite.dart';
import '../../../features/favorites/presentation/favorites_controller.dart';
import '../../../features/search/presentation/search_controller.dart';
import '../../../features/stops_and_lines/data/montevideo_realtime_bus_source.dart';
import '../../../features/stops_and_lines/data/sqflite_transit_repository.dart';
import '../../../features/stops_and_lines/data/transit_database.dart';
import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../../../features/stops_and_lines/domain/transit_repository.dart';
import '../../../features/stops_and_lines/presentation/feed_update_controller.dart';
import '../../../features/stops_and_lines/presentation/stop_details_sheet.dart';
import '../../../features/trip_planner/data/open_street_map_place_source.dart';
import '../../../features/trip_planner/domain/trip_planner.dart';
import '../../../features/trip_planner/presentation/trip_plan_details.dart';
import '../../../features/trip_planner/presentation/trip_search_sheet.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/connectivity_provider.dart';
import '../data/map_cache_repository.dart';
import 'live_bus_chip.dart';
import 'live_buses_controller.dart';
import 'map_action_provider.dart';
import 'map_location_controller.dart';

typedef MapBuilder = Widget Function(BuildContext context);

final mapBuilderOverrideProvider = Provider<MapBuilder?>((ref) => null);

final nearbyOfficialStopsProvider = FutureProvider<List<Stop>>((ref) async {
  if (transitConfig.url.isEmpty) return const [];
  final feedState = ref.watch(feedUpdateControllerProvider);
  final feed = feedState.asData?.value;
  if (feed == null || feed.status.synthetic || feed.status.stopCount == 0) {
    return const [];
  }

  final location = ref.watch(mapLocationControllerProvider).location;
  final database = TransitDatabase();
  final db = await database.open();
  try {
    return await SqfliteTransitRepository(() async => db).nearbyStops(
      location?.latitude ?? MapConfig.initialCenter.lat,
      location?.longitude ?? MapConfig.initialCenter.lon,
      1500,
    );
  } finally {
    await db.close();
  }
});

final nearbyStopRoutesProvider = FutureProvider<Map<String, List<Route>>>((
  ref,
) async {
  final stops = await ref.watch(nearbyOfficialStopsProvider.future);
  if (stops.isEmpty) return const {};
  final database = TransitDatabase();
  final db = await database.open();
  try {
    return await SqfliteTransitRepository(() async => db)
        .routesForStops(stops.map((stop) => stop.id).toSet());
  } finally {
    await db.close();
  }
});

final routeVariantsProvider = FutureProvider.family<List<RouteVariant>, String>(
  (ref, routeId) async {
    final feed = ref.watch(feedUpdateControllerProvider).asData?.value;
    if (feed == null || feed.status.synthetic) return const [];
    final db = await TransitDatabase().open();
    try {
      return await SqfliteTransitRepository(() async => db)
          .variantsForRoute(routeId);
    } finally {
      await db.close();
    }
  },
);

final routeShapeProvider = FutureProvider.family<Shape?, String>((
  ref,
  variantId,
) async {
  final feed = ref.watch(feedUpdateControllerProvider).asData?.value;
  if (feed == null || feed.status.synthetic) return null;
  final db = await TransitDatabase().open();
  try {
    return await SqfliteTransitRepository(() async => db)
        .shapeForVariant(variantId);
  } finally {
    await db.close();
  }
});

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    this.mapBuilder,
    this.mapLoadTimeout,
    @visibleForTesting this.realtimeBusSource,
    @visibleForTesting this.realtimePollInterval = const Duration(seconds: 10),
  });

  @visibleForTesting
  final MapBuilder? mapBuilder;

  @visibleForTesting
  final Duration? mapLoadTimeout;

  @visibleForTesting
  final RealtimeBusSource? realtimeBusSource;

  @visibleForTesting
  final Duration realtimePollInterval;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  Timer? _mapLoadTimer;
  MapController? _mapController;
  double _sheetExtent = 0.23;
  double _metersPerPixel = 5;
  int _mapGeneration = 0;
  bool _mapLoading = true;
  bool _mapError = false;
  bool _mapVisible = false;
  bool _appResumed = true;
  bool _realtimeAttached = false;
  LiveBusesController? _liveBusesController;
  RealtimeBusSource? _realtimeSource;
  MontevideoRealtimeBusSource? _ownedRealtimeSource;
  final Set<String> _expandedStopIds = {};
  String? _selectedVariantId;
  Route? _selectedRoute;
  Color _selectedRouteColor = AppColors.deepBlue;
  bool? _lastDarkTheme;
  TripPlan? _selectedTripPlan;
  String? _selectedTripOriginName;
  String? _selectedTripDestinationName;
  Stop? _openDetailStop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheetController.addListener(_onSheetChanged);
    final hasTestMap =
        widget.mapBuilder != null ||
        ref.read(mapBuilderOverrideProvider) != null;
    if (hasTestMap && widget.mapLoadTimeout == null) {
      _mapLoading = false;
    } else {
      _startMapLoadTimer();
    }
    _realtimeSource = widget.realtimeBusSource;
    if (_realtimeSource == null && transitConfig.realtimeEndpoint.isNotEmpty) {
      _ownedRealtimeSource = MontevideoRealtimeBusSource(
        transitConfig.realtimeEndpoint,
      );
      _realtimeSource = _ownedRealtimeSource;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isVisible = TickerMode.valuesOf(context).enabled;
    if (_mapVisible != isVisible) {
      _mapVisible = isVisible;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRealtimePolling();
      });
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_lastDarkTheme != null && _lastDarkTheme != isDark) {
      _mapController?.setStyle(_styleFor(isDark));
      _beginMapLoad();
    }
    _lastDarkTheme = isDark;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncRealtimePolling();
  }

  void _syncRealtimePolling() {
    final source = _realtimeSource;
    if (source == null) return;
    final controller = ref.read(liveBusesControllerProvider.notifier);
    _liveBusesController = controller;
    if (!_mapVisible || !_appResumed) {
      controller.pausePolling();
      return;
    }
    if (!_realtimeAttached) {
      controller.attachSource(
        source,
        pollInterval: widget.realtimePollInterval,
        maxMarkers: 60,
      );
      _realtimeAttached = true;
    } else {
      controller.resumePolling();
    }
  }

  @override
  void dispose() {
    _mapLoadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_realtimeAttached) {
      _liveBusesController?.pausePolling();
    }
    _ownedRealtimeSource?.close();
    _sheetController
      ..removeListener(_onSheetChanged)
      ..dispose();
    super.dispose();
  }

  void _onSheetChanged() {
    if (mounted && _sheetController.isAttached) {
      setState(() => _sheetExtent = _sheetController.size);
    }
  }

  String _styleFor(bool isDark) =>
      isDark ? MapConfig.darkStyleUrl : MapConfig.lightStyleUrl;

  void _startMapLoadTimer() {
    _mapLoadTimer?.cancel();
    _mapLoadTimer = Timer(
      widget.mapLoadTimeout ?? MapConfig.mapLoadTimeout,
      () {
        if (mounted && _mapLoading) {
          setState(() {
            _mapLoading = false;
            _mapError = true;
          });
        }
      },
    );
  }

  void _beginMapLoad() {
    setState(() {
      _mapLoading = true;
      _mapError = false;
    });
    _startMapLoadTimer();
  }

  void _retryMap() {
    _mapController = null;
    setState(() {
      _mapGeneration++;
      _mapLoading = true;
      _mapError = false;
    });
    _startMapLoadTimer();
  }

  List<BusPosition> _nearbyBuses(
    MapLocationState locationState,
    List<BusPosition> positions,
  ) {
    final centerLatitude =
        locationState.location?.latitude ?? MapConfig.initialCenter.lat;
    final centerLongitude =
        locationState.location?.longitude ?? MapConfig.initialCenter.lon;
    return positions
        .where(
          (bus) =>
              _distanceMeters(
                centerLatitude,
                centerLongitude,
                bus.latitude,
                bus.longitude,
              ) <=
              2000,
        )
        .toList()
      ..sort(
        (a, b) =>
            _distanceMeters(
              centerLatitude,
              centerLongitude,
              a.latitude,
              a.longitude,
            ).compareTo(
              _distanceMeters(
                centerLatitude,
                centerLongitude,
                b.latitude,
                b.longitude,
              ),
            ),
      );
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final latitudeDelta = (lat2 - lat1) * math.pi / 180;
    final longitudeDelta = (lon2 - lon1) * math.pi / 180;
    final haversine =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadius *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  Future<void> _onMapCreated(MapController controller) async {
    _mapController = controller;
    _startMapLoadTimer();
    _updateMetersPerPixel();
    _updateVisibleBounds();
    try {
      await ref.read(mapCacheRepositoryProvider).configureAmbientCache();
    } on Exception {
      // The map remains usable if cache configuration is unavailable.
    }
  }

  void _onStyleLoaded(StyleController _) {
    _mapLoadTimer?.cancel();
    if (mounted) {
      setState(() {
        _mapLoading = false;
        _mapError = false;
      });
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveCamera) {
      _updateMetersPerPixel();
      _updateVisibleBounds();
    } else if (event is MapEventClick) {
      unawaited(_showNearestStop(event));
    }
  }

  Future<void> _showNearestStop(MapEventClick event) async {
    final stops =
        ref.read(nearbyOfficialStopsProvider).asData?.value ?? const <Stop>[];
    final controller = _mapController;
    if (stops.isEmpty || controller == null) return;

    var metersPerPixel = _metersPerPixel;
    try {
      metersPerPixel = controller.getMetersPerPixelAtLatitude(event.point.lat);
    } on Exception {
      // Keep the last valid scale if the map is still settling.
    }
    final nearest =
        stops
            .map(
              (stop) => (
                stop: stop,
                distance: _distanceMeters(
                  event.point.lat,
                  event.point.lon,
                  stop.latitude,
                  stop.longitude,
                ),
              ),
            )
            .where((candidate) => candidate.distance <= metersPerPixel * 8)
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
    if (nearest.isNotEmpty) await _showStopDetails(nearest.first.stop);
  }

  void _updateVisibleBounds() {
    final controller = _mapController;
    if (controller == null) return;
    try {
      final bounds = controller.getVisibleRegion();
      ref
          .read(liveBusesControllerProvider.notifier)
          .setVisibleBounds(
            LiveBusesBounds(
              minLatitude: bounds.latitudeSouth,
              maxLatitude: bounds.latitudeNorth,
              minLongitude: bounds.longitudeWest,
              maxLongitude: bounds.longitudeEast,
            ),
          );
    } on Exception {
      // Keep the last valid visible region until the map is ready again.
    }
  }

  Marker _busMarker(
    BuildContext context,
    BusPosition bus,
    Set<int> matchedVariantIds,
  ) {
    final now = DateTime.now();
    final ageSeconds = now.difference(bus.receivedAt).inSeconds;
    final isStale = ageSeconds > 60;
    final l10n = AppLocalizations.of(context);
    final chip = LiveBusChip(
      bus: bus,
      matchedVariantIds: matchedVariantIds,
      now: now,
    );

    return Marker(
      point: Geographic(lon: bus.longitude, lat: bus.latitude),
      size: const Size(48, 48),
      child: Semantics(
        button: true,
        label: '${bus.lineLabel}, ${bus.destinationName}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chip,
                      const SizedBox(height: 12),
                      Text(
                        bus.destinationName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${bus.speedKmh.toStringAsFixed(0)} km/h'),
                      if (isStale) Text(l10n.mapBusAge(ageSeconds)),
                    ],
                  ),
                ),
              ),
            ),
            child: Center(child: FittedBox(child: chip)),
          ),
        ),
      ),
    );
  }

  void _updateMetersPerPixel() {
    final location = ref.read(mapLocationControllerProvider).location;
    final controller = _mapController;
    if (location == null || controller == null) return;
    try {
      final value = controller.getMetersPerPixelAtLatitude(location.latitude);
      if (value > 0 && value.isFinite && mounted) {
        setState(() => _metersPerPixel = value);
      }
    } on Exception {
      // Keep the last valid scale until the map is ready again.
    }
  }

  Future<void> _requestLocation() async {
    final l10n = AppLocalizations.of(context);
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.my_location_rounded),
        title: Text(l10n.locationRationaleTitle),
        content: Text(l10n.locationRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.locationRationaleContinue),
          ),
        ],
      ),
    );
    if (!mounted || shouldContinue != true) return;
    await ref.read(mapLocationControllerProvider.notifier).locate();
    if (!mounted) return;
    final state = ref.read(mapLocationControllerProvider);
    final location = state.location;
    if (location != null) {
      final position = Geographic(
        lon: location.longitude,
        lat: location.latitude,
      );
      await _mapController?.animateCamera(
        center: position,
        zoom: 15,
        padding: EdgeInsets.only(
          bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
        ),
      );
      _updateMetersPerPixel();
      _updateVisibleBounds();
    }
  }

  Future<void> _showTripSearch({TripEndpoint? destination}) async {
    final l10n = AppLocalizations.of(context);
    final location = ref.read(mapLocationControllerProvider).location;
    final feed = ref.read(feedUpdateControllerProvider).asData?.value;
    final hasOfficialFeed =
        feed != null && !feed.status.synthetic && feed.status.stopCount > 0;
    final searchService = hasOfficialFeed
        ? ref.read(searchServiceProvider)
        : null;
    final remotePlaceSearchEnabled =
        ref.read(remotePlaceSearchEnabledProvider).asData?.value ?? false;
    final placeSource = transitConfig.placeSearchEndpoint.isEmpty
        ? null
        : OpenStreetMapPlaceSource(endpoint: transitConfig.placeSearchEndpoint);
    var didSelectPlan = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (context) => TripSearchSheet(
          hasCurrentLocation: location != null,
          remotePlaceSearchEnabled: remotePlaceSearchEnabled,
          initialDestination: destination,
          searchService: searchService,
          onPlanSelected: (plan, origin, destination) {
            didSelectPlan = true;
            setState(() {
              _selectedTripPlan = plan;
              _selectedTripOriginName =
                  origin?.name ?? l10n.tripOriginLocationHint;
              _selectedTripDestinationName = destination.name;
            });
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          searchStops: (query) async {
            final feed = ref.read(feedUpdateControllerProvider).asData?.value;
            if (feed == null ||
                feed.status.synthetic ||
                feed.status.stopCount == 0) {
              throw Exception(l10n.tripOfficialDataUnavailable);
            }
            final db = await TransitDatabase().open();
            try {
              return await SqfliteTransitRepository(() async => db)
                  .searchStops(query);
            } finally {
              await db.close();
            }
          },
          searchPlaces: (query) async {
            if (placeSource == null) {
              throw Exception(l10n.tripPlaceSearchUnavailable);
            }
            return placeSource.search(query);
          },
          findPlans: (origin, destination, timing, config) async {
            final feed = ref.read(feedUpdateControllerProvider).asData?.value;
            if (feed == null ||
                feed.status.synthetic ||
                feed.status.stopCount == 0) {
              throw Exception(l10n.tripOfficialDataUnavailable);
            }
            final originLatitude = origin?.latitude ?? location?.latitude;
            final originLongitude = origin?.longitude ?? location?.longitude;
            if (originLatitude == null || originLongitude == null) {
              throw Exception(l10n.tripOriginRequired);
            }
            final db = await TransitDatabase().open();
            try {
              return await TransitTripPlanner(
                SqfliteTransitRepository(() async => db),
              ).plan(
                TripRequest(
                  originLatitude: originLatitude,
                  originLongitude: originLongitude,
                  destinationLatitude: destination.latitude,
                  destinationLongitude: destination.longitude,
                  timing: timing,
                  config: config,
                ),
              );
            } finally {
              await db.close();
            }
          },
        ),
      );
      if (didSelectPlan && mounted) {
        if (_sheetController.isAttached) {
          await _sheetController.animateTo(
            .65,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        final plan = _selectedTripPlan;
        if (plan != null) await _focusOnTripPlan(plan);
      }
    } finally {
      placeSource?.close();
    }
  }

  Future<void> _showAttribution() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.mapAttributionTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(MapConfig.attribution),
              const SizedBox(height: 16),
              Text(l10n.mapAttributionDetails),
              const SizedBox(height: 16),
              Text(l10n.mapLocationPrivacy),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStopDetails(Stop stop) async {
    var shouldPlan = false;
    setState(() => _openDetailStop = stop);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StopDetailsSheet(
        stop: stop,
        onHowToGetThere: () {
          shouldPlan = true;
          Navigator.of(context).pop();
        },
      ),
    );
    if (mounted) {
      setState(() => _openDetailStop = null);
    }
    if (mounted && shouldPlan) {
      await _showTripSearch(destination: TripEndpoint.fromStop(stop));
    }
  }

  Future<void> _handleLocationAction(MapLocationStatus status) async {
    final controller = ref.read(mapLocationControllerProvider.notifier);
    switch (status) {
      case MapLocationStatus.permissionDeniedForever:
        await controller.openPermissionSettings();
      case MapLocationStatus.serviceDisabled:
        await controller.openLocationSettings();
      case MapLocationStatus.permissionDenied:
      case MapLocationStatus.error:
        await _requestLocation();
      case MapLocationStatus.idle:
      case MapLocationStatus.loading:
      case MapLocationStatus.available:
        break;
    }
  }

  List<Layer> _locationLayers(MapLocationState state, bool isDark) {
    final location = state.location;
    if (state.status != MapLocationStatus.available || location == null) {
      return const [];
    }
    final point = Feature<Point>(
      geometry: Point(
        Geographic(lon: location.longitude, lat: location.latitude),
      ),
    );
    final primary = isDark ? AppColors.darkPrimary : AppColors.deepBlue;
    final radius = (location.accuracyMeters / _metersPerPixel)
        .round()
        .clamp(16, 96)
        .toInt();
    return [
      CircleLayer(
        points: [point],
        radius: radius,
        color: primary.withValues(alpha: 0.2),
        strokeWidth: 1,
        strokeColor: primary.withValues(alpha: 0.58),
      ),
      CircleLayer(
        points: [point],
        radius: 7,
        color: primary,
        strokeWidth: 3,
        strokeColor: AppColors.white,
      ),
    ];
  }

  List<Layer> _stopLayers(List<Stop> stops) {
    if (stops.isEmpty) return const [];
    return [
      CircleLayer(
        points: [
          for (final stop in stops)
            Feature<Point>(
              geometry: Point(
                Geographic(lon: stop.longitude, lat: stop.latitude),
              ),
            ),
        ],
        radius: 8,
        color: AppColors.lime,
        strokeWidth: 2,
        strokeColor: AppColors.ink,
      ),
    ];
  }

  List<Layer> _selectedRouteLayers(Shape? shape) {
    if (shape == null || shape.points.length < 2) return const [];
    return [
      PolylineLayer(
        polylines: [
          Feature<LineString>(
            geometry: LineString.from([
              for (final point in shape.points)
                Geographic(lon: point.longitude, lat: point.latitude),
            ]),
          ),
        ],
        color: _selectedRouteColor,
        width: 5,
      ),
    ];
  }

  List<Layer> _tripPlanLayers(TripPlan? plan) {
    if (plan == null) return const [];

    final walkingPoints = <Feature<LineString>>[];
    final transitPoints = <Feature<LineString>>[];
    for (final leg in plan.legs) {
      final fromLat = leg.fromLatitude ?? leg.fromStop?.latitude;
      final fromLon = leg.fromLongitude ?? leg.fromStop?.longitude;
      final toLat = leg.toLatitude ?? leg.toStop?.latitude;
      final toLon = leg.toLongitude ?? leg.toStop?.longitude;
      if (fromLat == null ||
          fromLon == null ||
          toLat == null ||
          toLon == null) {
        continue;
      }
      final segment = Feature<LineString>(
        geometry: LineString.from([
          Geographic(lon: fromLon, lat: fromLat),
          Geographic(lon: toLon, lat: toLat),
        ]),
      );
      switch (leg.kind) {
        case TripLegKind.walking:
          walkingPoints.add(segment);
        case TripLegKind.transit:
          transitPoints.add(segment);
        case TripLegKind.waiting:
          break;
      }
    }

    final layers = <Layer>[];
    if (walkingPoints.isNotEmpty) {
      layers.add(
        PolylineLayer(
          polylines: walkingPoints,
          color: AppColors.deepBlue.withValues(alpha: 0.72),
          width: 4,
          dashArray: const [1, 2],
        ),
      );
    }
    if (transitPoints.isNotEmpty) {
      layers.add(
        PolylineLayer(
          polylines: transitPoints,
          color: AppColors.deepBlue,
          width: 6,
        ),
      );
    }

    final origin = _tripPlanEndpoint(plan, first: true);
    if (origin != null) {
      layers.add(
        CircleLayer(
          points: [Feature<Point>(geometry: Point(origin))],
          radius: 7,
          color: AppColors.ink,
          strokeWidth: 3,
          strokeColor: AppColors.white,
        ),
      );
    }
    final destination = _tripPlanEndpoint(plan, first: false);
    if (destination != null) {
      layers.add(
        CircleLayer(
          points: [Feature<Point>(geometry: Point(destination))],
          radius: 8,
          color: AppColors.lime,
          strokeWidth: 3,
          strokeColor: AppColors.ink,
        ),
      );
    }
    return layers;
  }

  Geographic? _tripPlanEndpoint(TripPlan plan, {required bool first}) {
    if (plan.legs.isEmpty) return null;
    final legs = first ? plan.legs : plan.legs.reversed;
    for (final leg in legs) {
      final latitude = first
          ? leg.fromLatitude ?? leg.fromStop?.latitude
          : leg.toLatitude ?? leg.toStop?.latitude;
      final longitude = first
          ? leg.fromLongitude ?? leg.fromStop?.longitude
          : leg.toLongitude ?? leg.toStop?.longitude;
      if (latitude != null && longitude != null) {
        return Geographic(lon: longitude, lat: latitude);
      }
    }
    return null;
  }

  Future<void> _focusOnTripPlan(TripPlan plan) async {
    final points = <Geographic>[];
    for (final leg in plan.legs) {
      final fromLat = leg.fromLatitude ?? leg.fromStop?.latitude;
      final fromLon = leg.fromLongitude ?? leg.fromStop?.longitude;
      final toLat = leg.toLatitude ?? leg.toStop?.latitude;
      final toLon = leg.toLongitude ?? leg.toStop?.longitude;
      if (fromLat == null ||
          fromLon == null ||
          toLat == null ||
          toLon == null) {
        continue;
      }
      points.addAll([
        Geographic(lon: fromLon, lat: fromLat),
        Geographic(lon: toLon, lat: toLat),
      ]);
    }
    if (points.isEmpty) return;
    final latitudes = points.map((point) => point.lat).toList();
    final longitudes = points.map((point) => point.lon).toList();
    final minLat = latitudes.reduce(math.min);
    final maxLat = latitudes.reduce(math.max);
    final minLon = longitudes.reduce(math.min);
    final maxLon = longitudes.reduce(math.max);
    final center = Geographic(
      lon: (minLon + maxLon) / 2,
      lat: (minLat + maxLat) / 2,
    );
    final deltaLat = maxLat - minLat;
    final deltaLon = maxLon - minLon;
    final zoom = deltaLat < 0.01 && deltaLon < 0.01 ? 14.0 : 12.5;
    await _mapController?.animateCamera(
      center: center,
      zoom: zoom,
      padding: EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
      ),
    );
  }

  Future<void> _selectVariant(
    RouteVariant variant,
    Route route,
    Stop stop,
  ) async {
    final hexColor = route.color.replaceFirst('#', '');
    final routeColor = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hexColor)
        ? Color(int.parse('FF$hexColor', radix: 16))
        : AppColors.deepBlue;
    setState(() {
      _selectedVariantId = variant.id;
      _selectedRoute = route;
      _selectedRouteColor = routeColor;
    });
    await _mapController?.animateCamera(
      center: Geographic(lon: stop.longitude, lat: stop.latitude),
      zoom: 12.5,
      padding: EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
      ),
    );
    if (_sheetController.isAttached) {
      await _sheetController.animateTo(
        .46,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showSavedRoute(Route route) async {
    final hexColor = route.color.replaceFirst('#', '');
    final routeColor = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hexColor)
        ? Color(int.parse('FF$hexColor', radix: 16))
        : AppColors.deepBlue;
    setState(() {
      _selectedTripPlan = null;
      _selectedVariantId = null;
      _selectedRoute = route;
      _selectedRouteColor = routeColor;
    });
    final variants = await ref.read(routeVariantsProvider(route.id).future);
    RouteVariant? variant;
    for (final candidate in variants) {
      if (candidate.shapeId != null) {
        variant = candidate;
        break;
      }
    }
    if (variant == null || !mounted || _selectedRoute?.id != route.id) return;
    final shape = await ref.read(routeShapeProvider(variant.id).future);
    if (!mounted || _selectedRoute?.id != route.id) return;
    setState(() => _selectedVariantId = variant!.id);
    final points = shape?.points;
    if (points == null || points.isEmpty) return;
    final middle = points[points.length ~/ 2];
    await _mapController?.animateCamera(
      center: Geographic(lon: middle.longitude, lat: middle.latitude),
      zoom: 12.5,
      padding: EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
      ),
    );
  }

  Future<void> _setNearbyStopsExpanded(Stop stop, bool expanded) async {
    setState(() {
      if (expanded) {
        _expandedStopIds.add(stop.id);
      } else {
        _expandedStopIds.remove(stop.id);
      }
    });
    if (!expanded || !_sheetController.isAttached) return;
    await _sheetController.animateTo(
      .46,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<MapAction?>(mapActionProvider, (previous, next) {
      if (next == null) return;
      ref.read(mapActionProvider.notifier).clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (next) {
          case ShowRouteOnMap(:final route):
            unawaited(_showSavedRoute(route));
          case PlanTripToPlace(:final destination):
            unawaited(_showTripSearch(destination: destination));
        }
      });
    });
    final favorites =
        ref.watch(favoritesControllerProvider).asData?.value ??
        const <Favorite>[];
    final placeFavorites = <FavoritePlaceSlot, Favorite>{};
    for (final favorite in favorites) {
      final slot = favorite.placeSlot;
      if (slot != null &&
          favorite.latitude != null &&
          favorite.longitude != null) {
        placeFavorites[slot] = favorite;
      }
    }
    final locationState = ref.watch(mapLocationControllerProvider);
    final networkState = ref.watch(networkAvailableProvider);
    final feedAsync = ref.watch(feedUpdateControllerProvider);
    final feedState = feedAsync.asData?.value;
    final nearbyStops = ref.watch(nearbyOfficialStopsProvider);
    final stops = nearbyStops.asData?.value ?? const <Stop>[];
    final stopRoutes = ref.watch(nearbyStopRoutesProvider);
    final routesByStop =
        stopRoutes.asData?.value ?? const <String, List<Route>>{};
    final liveBuses = ref.watch(liveBusesControllerProvider);
    final selectedRoute = _selectedRoute;
    final selectedRoutes = <String, Route>{
      ...?(selectedRoute == null ? null : {selectedRoute.id: selectedRoute}),
      for (final stopId in {
        ..._expandedStopIds,
        if (_openDetailStop != null) _openDetailStop!.id,
      })
        for (final route in routesByStop[stopId] ?? const <Route>[])
          route.id: route,
    };
    final selectedLines = <String>{};
    final selectedVariantIds = <int>{};
    for (final route in selectedRoutes.values) {
      if (route.shortName.isNotEmpty) selectedLines.add(route.shortName);
      final variants = ref.watch(routeVariantsProvider(route.id)).asData?.value;
      selectedVariantIds.addAll(
        variants
                ?.map((variant) => variant.externalVariantId)
                .whereType<int>() ??
            const <int>[],
      );
    }
    final selectedShape = _selectedVariantId == null
        ? null
        : ref.watch(routeShapeProvider(_selectedVariantId!)).asData?.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mapBuilder =
        widget.mapBuilder ?? ref.watch(mapBuilderOverrideProvider);
    final mapWidget =
        mapBuilder?.call(context) ??
        MapLibreMap(
          key: ValueKey(_mapGeneration),
          options: MapOptions(
            initStyle: _styleFor(isDark),
            initCenter: MapConfig.initialCenter,
            initZoom: MapConfig.initialZoom,
            minZoom: 2,
            maxZoom: 19,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onEvent: _onMapEvent,
          layers: [
            ..._tripPlanLayers(_selectedTripPlan),
            ..._selectedRouteLayers(selectedShape),
            ..._stopLayers(stops),
            ..._locationLayers(locationState, isDark),
          ],
          children: [
            WidgetLayer(
              allowInteraction: true,
              markers: [
                if (_selectedTripPlan == null)
                  for (final bus in liveBuses.filteredPositions(
                    selectedLines: selectedLines,
                    selectedVariantIds: selectedVariantIds,
                  ))
                    _busMarker(context, bus, selectedVariantIds),
              ],
            ),
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetHeight = constraints.maxHeight * _sheetExtent;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(child: mapWidget),
            if (_mapLoading)
              Positioned(
                top: placeFavorites.isEmpty ? 92 : 148,
                left: 0,
                right: 0,
                child: Center(
                  child: _StatusPill(
                    icon: const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: l10n.mapLoading,
                  ),
                ),
              ),
            if (_mapError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 88, 24, 130),
                  child: _MapErrorCard(onRetry: _retryMap),
                ),
              ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _SearchControl(onTap: _showTripSearch),
                    if (placeFavorites.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final slot in FavoritePlaceSlot.values)
                              if (placeFavorites[slot] case final favorite?)
                                _FavoriteShortcutChip(
                                  key: ValueKey('map-favorite-${slot.name}'),
                                  label: slot == FavoritePlaceSlot.home
                                      ? l10n.favoritesHome
                                      : l10n.favoritesWork,
                                  semanticLabel: l10n.favoritesPlanTo(
                                    slot == FavoritePlaceSlot.home
                                        ? l10n.favoritesHome
                                        : l10n.favoritesWork,
                                  ),
                                  onTap: () => unawaited(
                                    _showTripSearch(
                                      destination: TripEndpoint(
                                        name: favorite.name,
                                        latitude: favorite.latitude!,
                                        longitude: favorite.longitude!,
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (networkState.asData?.value == false)
                      _InfoBanner(
                        icon: Symbols.wifi_off_rounded,
                        label: l10n.mapOffline,
                      ),
                    if (liveBuses.error != null &&
                        networkState.asData?.value != false)
                      _InfoBanner(
                        icon: Symbols.cloud_off_rounded,
                        label: l10n.mapLiveServiceDown,
                      ),
                    _LocationBanner(
                      status: locationState.status,
                      onAction: () =>
                          _handleLocationAction(locationState.status),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: sheetHeight + 68,
              child: Semantics(
                button: true,
                label: l10n.locationRecenter,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: FloatingActionButton(
                    heroTag: 'map-recenter',
                    tooltip: l10n.locationRecenter,
                    onPressed: _requestLocation,
                    child: locationState.status == MapLocationStatus.loading
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.my_location_rounded),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: sheetHeight + 10,
              child: Semantics(
                button: true,
                label: l10n.mapAttributionButton,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: _showAttribution,
                    borderRadius: BorderRadius.circular(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.mapAttributionShort,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(width: 4),
                            const Icon(Symbols.info_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.23,
              minChildSize: 0.18,
              maxChildSize: _selectedTripPlan == null ? 0.46 : 0.68,
              snap: true,
              snapSizes: _selectedTripPlan == null
                  ? const [0.23, 0.46]
                  : const [0.46, 0.68],
              builder: (context, scrollController) => Semantics(
                container: true,
                label: _selectedTripPlan == null
                    ? l10n.mapStopsAndBuses
                    : l10n.tripDetailTitle,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_selectedTripPlan != null) ...[
                        TripPlanDetails(
                          plan: _selectedTripPlan!,
                          originName:
                              _selectedTripOriginName ??
                              l10n.tripOriginLocationHint,
                          destinationName:
                              _selectedTripDestinationName ??
                              l10n.tripDetailUnknownStop,
                          onChangeTrip: () {
                            setState(() {
                              _selectedTripPlan = null;
                              _selectedTripOriginName = null;
                              _selectedTripDestinationName = null;
                            });
                            unawaited(_showTripSearch());
                          },
                          onCloseTrip: () {
                            setState(() {
                              _selectedTripPlan = null;
                              _selectedTripOriginName = null;
                              _selectedTripDestinationName = null;
                            });
                            if (_sheetController.isAttached) {
                              unawaited(
                                _sheetController.animateTo(
                                  .23,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                ),
                              );
                            }
                          },
                        ),
                      ] else ...[
                        Text(
                          l10n.mapStopsAndBuses,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (transitConfig.url.isNotEmpty &&
                            stops.isNotEmpty) ...[
                          Text(
                            l10n.mapStopsNearby,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...stops.take(12).map((stop) {
                            final routes =
                                routesByStop[stop.id] ?? const <Route>[];
                            final expanded = _expandedStopIds.contains(stop.id);
                            return Column(
                              children: [
                                ListTile(
                                  key: ValueKey('stop-${stop.id}'),
                                  onTap: () =>
                                      unawaited(_showStopDetails(stop)),
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Symbols.location_on_rounded,
                                    color: AppColors.deepBlue,
                                  ),
                                  title: Text(stop.name),
                                  subtitle: Text(
                                    stopRoutes.isLoading
                                        ? l10n.mapRoutesLoading
                                        : routes.isNotEmpty
                                        ? l10n.mapStopRouteCount(routes.length)
                                        : l10n.mapStopNoRoutes,
                                  ),
                                  trailing: routes.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: expanded
                                              ? l10n.mapStopCollapseRoutes
                                              : l10n.mapStopExpandRoutes,
                                          onPressed: () => unawaited(
                                            _setNearbyStopsExpanded(
                                              stop,
                                              !expanded,
                                            ),
                                          ),
                                          icon: Icon(
                                            expanded
                                                ? Symbols.expand_less_rounded
                                                : Symbols.expand_more_rounded,
                                          ),
                                        ),
                                ),
                                if (expanded)
                                  for (final route in routes)
                                    _StopRouteExpansion(
                                      stop: stop,
                                      route: route,
                                      selectedVariantId: _selectedVariantId,
                                      onSelectVariant: _selectVariant,
                                    ),
                              ],
                            );
                          }),
                        ],
                        if (transitConfig.url.isEmpty)
                          Text(l10n.mapLiveNotConfigured)
                        else if ((nearbyStops.isLoading ||
                                feedAsync.isLoading) &&
                            stops.isEmpty)
                          Row(
                            children: [
                              const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  feedState?.phase ==
                                              FeedUpdatePhase.processing ||
                                          feedState?.phase ==
                                              FeedUpdatePhase.downloading
                                      ? l10n.mapFeedLoading
                                      : l10n.mapStopsLoading,
                                ),
                              ),
                            ],
                          )
                        else if (feedState?.phase == FeedUpdatePhase.offline ||
                            feedState?.phase ==
                                FeedUpdatePhase.errorWithOldData)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.mapFeedError(
                                  feedState?.message.isNotEmpty == true
                                      ? feedState!.message
                                      : l10n.mapFeedUnknownError,
                                ),
                              ),
                              if (kDebugMode) ...[
                                const SizedBox(height: 8),
                                Text(l10n.mapFeedProxyHint),
                              ],
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () => ref
                                    .read(feedUpdateControllerProvider.notifier)
                                    .updateNow(),
                                icon: const Icon(Symbols.refresh_rounded),
                                label: Text(l10n.actionRetry),
                              ),
                            ],
                          )
                        else if (feedState?.status.synthetic == true)
                          Text(l10n.mapFeedDemoOnly)
                        else if (nearbyStops.hasError)
                          Text(l10n.mapStopsError(nearbyStops.error.toString()))
                        else if (stops.isEmpty)
                          Text(l10n.mapNoStops)
                        else if (stopRoutes.isLoading)
                          Text(l10n.mapRoutesLoading)
                        else if (stopRoutes.hasError)
                          Text(l10n.mapRoutesError(stopRoutes.error.toString()))
                        else if (liveBuses.error != null)
                          Text(l10n.mapLiveError(liveBuses.error!))
                        else if (liveBuses.lastUpdatedAt == null)
                          Row(
                            children: [
                              const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(l10n.mapLiveLoading),
                            ],
                          )
                        else
                          Text(
                            l10n.mapLiveSection,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        if (stops.isNotEmpty &&
                            liveBuses.lastUpdatedAt != null &&
                            _nearbyBuses(
                              locationState,
                              liveBuses.positions,
                            ).isNotEmpty)
                          ..._nearbyBuses(locationState, liveBuses.positions)
                              .take(8)
                              .map(
                                (bus) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    child: Text(bus.lineLabel),
                                  ),
                                  title: Text(bus.destinationName),
                                  subtitle: Text(
                                    '${bus.speedKmh.toStringAsFixed(0)} km/h',
                                  ),
                                  trailing: Text(
                                    l10n.mapLiveUpdated(
                                      '${bus.receivedAt.hour.toString().padLeft(2, '0')}:'
                                      '${bus.receivedAt.minute.toString().padLeft(2, '0')}',
                                    ),
                                  ),
                                ),
                              ),
                        if (liveBuses.lastUpdatedAt != null &&
                            _nearbyBuses(
                              locationState,
                              liveBuses.positions,
                            ).isEmpty)
                          Text(l10n.mapLiveEmpty),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StopRouteExpansion extends ConsumerWidget {
  const _StopRouteExpansion({
    required this.stop,
    required this.route,
    required this.selectedVariantId,
    required this.onSelectVariant,
  });

  final Stop stop;
  final Route route;
  final String? selectedVariantId;
  final Future<void> Function(RouteVariant variant, Route route, Stop stop)
  onSelectVariant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final variants = ref.watch(routeVariantsProvider(route.id));
    return ExpansionTile(
      key: ValueKey('route-${stop.id}-${route.id}'),
      tilePadding: const EdgeInsets.only(left: 44),
      title: Text(route.shortName),
      subtitle: Text(route.longName),
      children: [
        _LineFavoriteButton(route: route),
        if (variants.isLoading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.mapRoutesLoading),
          )
        else if (variants.hasError)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.mapRoutesError(variants.error.toString())),
          )
        else if (variants.asData?.value.isEmpty ?? true)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.mapRouteNoVariants),
          )
        else
          ...variants.requireValue.map(
            (variant) => ListTile(
              key: ValueKey('variant-${variant.id}'),
              selected: variant.id == selectedVariantId,
              leading: const Icon(Symbols.route_rounded),
              title: Text(
                variant.destination.isEmpty
                    ? route.longName
                    : variant.destination,
              ),
              subtitle: Text(
                variant.shapeId == null
                    ? l10n.mapRouteNoGeometry
                    : l10n.mapRouteShowOnMap,
              ),
              onTap: variant.shapeId == null
                  ? null
                  : () => onSelectVariant(variant, route, stop),
            ),
          ),
      ],
    );
  }
}

class _LineFavoriteButton extends ConsumerWidget {
  const _LineFavoriteButton({required this.route});

  final Route route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final favorites =
        ref.watch(favoritesControllerProvider).asData?.value ??
        const <Favorite>[];
    Favorite? saved;
    for (final favorite in favorites) {
      if (favorite.type == FavoriteType.line && favorite.id == route.id) {
        saved = favorite;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('favorite-line-${route.id}'),
          onPressed: () => unawaited(_toggleLineFavorite(ref, route, saved)),
          icon: Icon(
            saved == null
                ? Symbols.favorite_border_rounded
                : Symbols.favorite_rounded,
            fill: saved == null ? 0 : 1,
          ),
          label: Text(
            saved == null ? l10n.lineFavoriteSave : l10n.lineFavoriteRemove,
          ),
        ),
      ),
    );
  }
}

Future<void> _toggleLineFavorite(
  WidgetRef ref,
  Route route,
  Favorite? saved,
) async {
  final controller = ref.read(favoritesControllerProvider.notifier);
  if (saved != null) {
    await controller.remove(saved);
    return;
  }
  await controller.add(
    Favorite(
      id: route.id,
      type: FavoriteType.line,
      name: route.shortName.isEmpty ? route.id : route.shortName,
    ),
  );
}

class _FavoriteShortcutChip extends StatelessWidget {
  const _FavoriteShortcutChip({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.bookmark_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchControl extends StatelessWidget {
  const _SearchControl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const ValueKey('map-search-control'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(
                  Symbols.search_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.mapSearchPlaceholder,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [icon, const SizedBox(width: 8), Text(label)],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.status, required this.onAction});

  final MapLocationStatus status;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String? message, String? action, IconData icon) = switch (status) {
      MapLocationStatus.permissionDenied => (
        l10n.locationPermissionDenied,
        l10n.locationRetry,
        Symbols.location_disabled_rounded,
      ),
      MapLocationStatus.permissionDeniedForever => (
        l10n.locationPermissionDeniedForever,
        l10n.locationOpenSettings,
        Symbols.settings_rounded,
      ),
      MapLocationStatus.serviceDisabled => (
        l10n.locationServiceDisabled,
        l10n.locationEnableService,
        Symbols.location_off_rounded,
      ),
      MapLocationStatus.error => (
        l10n.locationError,
        l10n.locationRetry,
        Symbols.location_searching_rounded,
      ),
      MapLocationStatus.idle ||
      MapLocationStatus.loading ||
      MapLocationStatus.available => (null, null, Symbols.my_location_rounded),
    };
    if (message == null || action == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
              TextButton(onPressed: onAction, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapErrorCard extends StatelessWidget {
  const _MapErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.map_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.mapErrorTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.mapErrorBody, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh_rounded),
              label: Text(l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}
