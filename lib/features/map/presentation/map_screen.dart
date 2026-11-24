import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/map_config.dart';
import '../../../core/config/transit_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/rumbo_components.dart';
import '../../../features/favorites/domain/favorite.dart';
import '../../../features/favorites/presentation/favorites_controller.dart';
import '../../../features/search/presentation/search_controller.dart';
import '../../../features/settings/presentation/privacy_preferences.dart';
import '../../../features/stops_and_lines/data/montevideo_realtime_bus_source.dart';
import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../../../features/stops_and_lines/domain/transit_repository.dart';
import '../../../features/stops_and_lines/presentation/feed_update_controller.dart';
import '../../../features/stops_and_lines/presentation/line_details_sheet.dart';
import '../../../features/stops_and_lines/presentation/stop_details_sheet.dart';
import '../../../features/trip_planner/data/open_street_map_place_source.dart';
import '../../../features/trip_planner/domain/trip_planner.dart';
import '../../../features/trip_planner/domain/walk_graph_worker.dart';
import '../../../features/trip_planner/presentation/walk_graph_provider.dart';
import '../../../features/trip_planner/presentation/walking_red_status_provider.dart';
import '../../../features/trip_planner/presentation/trip_plan_details.dart';
import '../../../features/trip_detail/presentation/active_trip_controller.dart';
import '../../../features/trip_planner/presentation/trip_search_sheet.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/connectivity_provider.dart';
import '../data/map_cache_repository.dart';
import 'live_buses_controller.dart';
import 'map_action_provider.dart';
import 'map_location_controller.dart';
import 'live_bus_chip.dart';

typedef MapBuilder = Widget Function(BuildContext context);

const _locationRationaleAcceptedKey = 'location_rationale_accepted';
const double tripPlanSheetMinimumExtent = 0.42;

final mapBuilderOverrideProvider = Provider<MapBuilder?>((ref) => null);

final nearbyOfficialStopsProvider = FutureProvider<List<Stop>>((ref) async {
  final feedState = ref.watch(feedUpdateControllerProvider);
  final feed = feedState.asData?.value;
  if (!hasOfficialTransitData(feed)) {
    return const [];
  }

  final location = ref.watch(mapLocationControllerProvider).location;
  return ref
      .watch(transitRepositoryProvider)
      .nearbyStops(
        location?.latitude ?? MapConfig.initialCenter.lat,
        location?.longitude ?? MapConfig.initialCenter.lon,
        1500,
      );
});

final nearbyStopRoutesProvider = FutureProvider<Map<String, List<Route>>>((
  ref,
) async {
  final stops = await ref.watch(nearbyOfficialStopsProvider.future);
  if (stops.isEmpty) return const {};
  return ref
      .watch(transitRepositoryProvider)
      .routesForStops(stops.map((stop) => stop.id).toSet());
});

final routeVariantsProvider = FutureProvider.family<List<RouteVariant>, String>(
  (ref, routeId) async {
    final feed = ref.watch(feedUpdateControllerProvider).asData?.value;
    if (!hasOfficialTransitData(feed)) return const [];
    return ref.watch(transitRepositoryProvider).variantsForRoute(routeId);
  },
);

final routeShapeProvider = FutureProvider.family<Shape?, String>((
  ref,
  variantId,
) async {
  final feed = ref.watch(feedUpdateControllerProvider).asData?.value;
  if (!hasOfficialTransitData(feed)) return null;
  return ref.watch(transitRepositoryProvider).shapeForVariant(variantId);
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
  /// Test override; production polling defaults to 10 seconds.
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
  bool _mapStyleReady = false;
  bool _pendingLocationRecenter = false;
  Future<void>? _locationRequestInFlight;
  bool _mapVisible = false;
  bool _appResumed = true;
  bool _realtimeAttached = false;
  LiveBusesController? _liveBusesController;
  RealtimeBusSource? _realtimeSource;
  MontevideoRealtimeBusSource? _ownedRealtimeSource;
  final Set<String> _expandedStopIds = {};
  String? _selectedVariantId;
  String? _selectedStopId;
  Route? _selectedRoute;
  Color _selectedRouteColor = AppColors.rumbo;
  bool? _lastDarkTheme;
  int? _mapLayerSignature;
  List<Layer>? _cachedMapLayers;
  List<BusPosition>? _cachedBusSourcePositions;
  LiveBusesBounds? _cachedBusBounds;
  Set<String> _cachedBusLines = const {};
  Set<int> _cachedBusVariantIds = const {};
  int? _cachedBusMarkerLimit;
  List<BusPosition>? _cachedVisibleBuses;
  TripPlan? _selectedTripPlan;
  String? _selectedTripOriginName;
  String? _selectedTripDestinationName;
  final Map<String, Shape> _tripPlanShapes = {};

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
    if (ref.read(liveBusesEnabledProvider).asData?.value == false) {
      controller.setEnabled(false);
      return;
    }
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
    _tripPlanShapes.clear();
    _cachedMapLayers = null;
    _cachedVisibleBuses = null;
    _cachedBusSourcePositions = null;
    _cachedBusBounds = null;
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
    _mapStyleReady = false;
    setState(() {
      _mapLoading = true;
      _mapError = false;
    });
    _startMapLoadTimer();
  }

  void _retryMap() {
    _mapController = null;
    _mapStyleReady = false;
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
    _mapStyleReady = false;
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
    _mapStyleReady = true;
    _mapLoadTimer?.cancel();
    // getVisibleRegion may be unavailable in onMapCreated until the native
    // map style has finished loading; refresh bounds now so the first bus
    // response can be rendered without waiting for a camera gesture.
    _updateVisibleBounds();
    if (mounted) {
      setState(() {
        _mapLoading = false;
        _mapError = false;
      });
    }
    if (_pendingLocationRecenter) {
      unawaited(_centerMapOnCurrentLocation());
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      _updateMetersPerPixel();
      _updateVisibleBounds();
    } else if (event is MapEventClick) {
      unawaited(_showNearestFeature(event));
    }
  }

  Future<void> _showNearestFeature(MapEventClick event) async {
    if (await _showNearestBus(event)) return;
    await _showNearestStop(event);
  }

  Future<bool> _showNearestBus(MapEventClick event) async {
    final controller = _mapController;
    if (controller == null) return false;
    final liveState = ref.read(liveBusesControllerProvider);
    final buses = liveState.filteredPositions();
    if (buses.isEmpty) return false;

    var metersPerPixel = _metersPerPixel;
    try {
      metersPerPixel = controller.getMetersPerPixelAtLatitude(event.point.lat);
    } on Exception {
      // Keep the last valid scale if the map is still settling.
    }
    final nearest =
        buses
            .map(
              (bus) => (
                bus: bus,
                distance: _distanceMeters(
                  event.point.lat,
                  event.point.lon,
                  bus.latitude,
                  bus.longitude,
                ),
              ),
            )
            .where((candidate) => candidate.distance <= metersPerPixel * 12)
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
    if (nearest.isEmpty) return false;

    final bus = nearest.first.bus;
    final now = DateTime.now();
    final ageSeconds = now.difference(bus.receivedAt).inSeconds;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RumboSheetHandle(label: bus.lineLabel),
              LiveBusChip(
                bus: bus,
                matchedVariantIds: liveState.selectedVariantIds,
                now: now,
              ),
              const SizedBox(height: AppTokens.space12),
              Text(
                bus.destinationName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${bus.speedKmh.toStringAsFixed(0)} km/h',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (ageSeconds > 60)
                Text(
                  AppLocalizations.of(context).mapBusAge(ageSeconds),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return true;
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
      final current = ref.read(liveBusesControllerProvider).visibleBounds;
      if (current != null &&
          current.minLatitude == bounds.latitudeSouth &&
          current.maxLatitude == bounds.latitudeNorth &&
          current.minLongitude == bounds.longitudeWest &&
          current.maxLongitude == bounds.longitudeEast) {
        return;
      }
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

  Future<void> _requestLocation({BuildContext? dialogContext}) {
    final inFlight = _locationRequestInFlight;
    if (inFlight != null) return inFlight;

    final request = _performLocationRequest(dialogContext: dialogContext);
    _locationRequestInFlight = request;
    return request.whenComplete(() {
      if (identical(_locationRequestInFlight, request)) {
        _locationRequestInFlight = null;
      }
    });
  }

  Future<void> _performLocationRequest({BuildContext? dialogContext}) async {
    final l10n = AppLocalizations.of(context);
    final preferences = await SharedPreferences.getInstance();
    var shouldContinue =
        preferences.getBool(_locationRationaleAcceptedKey) ?? false;
    if (!shouldContinue) {
      shouldContinue =
          (await showDialog<bool>(
            context: dialogContext ?? context,
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
          )) ??
          false;
    }
    if (!mounted || !shouldContinue) return;
    if (preferences.getBool(_locationRationaleAcceptedKey) != true) {
      await preferences.setBool(_locationRationaleAcceptedKey, true);
    }
    await ref.read(mapLocationControllerProvider.notifier).locate();
    if (!mounted) return;
    final state = ref.read(mapLocationControllerProvider);
    final location = state.location;
    if (location == null) {
      final message = switch (state.status) {
        MapLocationStatus.permissionDenied => l10n.locationPermissionDenied,
        MapLocationStatus.permissionDeniedForever =>
          l10n.locationPermissionDeniedForever,
        MapLocationStatus.serviceDisabled => l10n.locationServiceDisabled,
        _ => l10n.locationError,
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _pendingLocationRecenter = true;
    await _centerMapOnCurrentLocation();
  }

  Future<void> _centerMapOnCurrentLocation() async {
    final location = ref.read(mapLocationControllerProvider).location;
    final controller = _mapController;
    if (location == null || !mounted) return;
    if (controller == null || !_mapStyleReady) {
      _pendingLocationRecenter = true;
      return;
    }

    try {
      await controller.animateCamera(
        center: Geographic(lon: location.longitude, lat: location.latitude),
        zoom: 15,
        padding: EdgeInsets.only(
          bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
        ),
      );
    } on Exception {
      _pendingLocationRecenter = true;
      return;
    }
    _pendingLocationRecenter = false;
    _updateMetersPerPixel();
    _updateVisibleBounds();
  }

  Future<void> _showTripSearch({
    TripEndpoint? origin,
    TripEndpoint? destination,
  }) async {
    final l10n = AppLocalizations.of(context);
    final location = ref.read(mapLocationControllerProvider).location;
    final searchService = ref.read(searchServiceProvider);
    final remotePlaceSearchEnabled =
        ref.read(remotePlaceSearchEnabledProvider).asData?.value ?? false;
    final placeSource = transitConfig.placeSearchEndpoint.isEmpty
        ? null
        : OpenStreetMapPlaceSource(endpoint: transitConfig.placeSearchEndpoint);
    // El worker carga la seed fuera del hilo de UI. Si todavía no está listo,
    // planifica de forma aproximada y refina el recorrido cuando termine.
    final walkGraphWorkerFuture = ref.read(walkGraphProvider.future);
    final tripPlanner = TransitTripPlanner(
      ref.read(transitRepositoryProvider),
      walkGraphWorker: ref.read(walkGraphProvider).value,
    );
    if (!mounted) return;
    var didSelectPlan = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (context) => TripSearchSheet(
          hasCurrentLocation: location != null,
          ensureCurrentLocation: (dialogContext) async {
            await _requestLocation(dialogContext: dialogContext);
            return ref.read(mapLocationControllerProvider).location != null;
          },
          remotePlaceSearchEnabled: remotePlaceSearchEnabled,
          onRemotePlaceSearchConsentRequested: () async {
            final accepted = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(l10n.tripGeocodingConsentTitle),
                content: Text(l10n.tripGeocodingConsentBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l10n.tripGeocodingConsentAction),
                  ),
                ],
              ),
            );
            if (accepted == true) {
              await ref
                  .read(remotePlaceSearchEnabledProvider.notifier)
                  .setEnabled(true);
            }
            return accepted == true;
          },
          onCancelPlan: tripPlanner.cancelPendingSearch,
          initialOrigin: origin,
          initialDestination: destination,
          searchService: searchService,
          onPlanSelected: (plan, origin, destination) {
            didSelectPlan = true;
            final planLines = <String>{
              for (final leg in plan.legs)
                if (leg.kind == TripLegKind.transit && leg.route != null)
                  leg.route!.shortName.isNotEmpty
                      ? leg.route!.shortName
                      : leg.route!.id,
            };
            ref
                .read(liveBusesControllerProvider.notifier)
                .setSelectedLines(planLines);
            setState(() {
              _selectedTripPlan = plan;
              _selectedRoute = null;
              _selectedVariantId = null;
              _selectedTripOriginName =
                  origin?.name ?? l10n.tripOriginLocationHint;
              _selectedTripDestinationName = destination.name;
            });
            unawaited(_loadTripPlanShapes(plan));
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          onRouteSelected: (Route route) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            unawaited(_showLineDetails(route));
          },
          searchStops: (query) async {
            return ref.read(transitRepositoryProvider).searchStops(query);
          },
          searchPlaces: (query) async {
            if (placeSource == null) {
              throw Exception(l10n.tripPlaceSearchUnavailable);
            }
            return placeSource.search(query);
          },
          findPlans: (origin, destination, timing, config) async {
            var feed = ref.read(feedUpdateControllerProvider).asData?.value;
            feed = await waitForOfficialTransitData(
              feed,
              () => ref.read(feedUpdateControllerProvider.future),
            );
            if (!hasOfficialTransitData(feed)) {
              throw Exception(
                feed?.message.isNotEmpty == true
                    ? feed!.message
                    : l10n.tripOfficialDataUnavailable,
              );
            }
            final currentLocation = ref
                .read(mapLocationControllerProvider)
                .location;
            final originLatitude =
                origin?.latitude ?? currentLocation?.latitude;
            final originLongitude =
                origin?.longitude ?? currentLocation?.longitude;
            if (originLatitude == null || originLongitude == null) {
              throw Exception(l10n.tripOriginRequired);
            }
            final plans = await tripPlanner.plan(
              TripRequest(
                originLatitude: originLatitude,
                originLongitude: originLongitude,
                destinationLatitude: destination.latitude,
                destinationLongitude: destination.longitude,
                timing: timing,
                config: config,
              ),
            );
            final relevantLines = <String>{
              for (final plan in plans)
                for (final leg in plan.legs)
                  if (leg.kind == TripLegKind.transit && leg.route != null)
                    leg.route!.shortName.isNotEmpty
                        ? leg.route!.shortName
                        : leg.route!.id,
            };
            if (relevantLines.isNotEmpty) {
              ref
                  .read(liveBusesControllerProvider.notifier)
                  .setSelectedLines(relevantLines);
            }
            return plans;
          },
        ),
      );
      if (didSelectPlan && mounted) {
        if (_sheetController.isAttached) {
          await _sheetController.animateTo(
            tripPlanSheetMinimumExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        final plan = await _refreshSelectedTripPlanAfterGraphLoad(
          tripPlanner,
          walkGraphWorkerFuture,
        );
        if (plan != null) await _focusOnTripPlan(plan);
      }
    } finally {
      tripPlanner.cancelPendingSearch();
      placeSource?.close();
    }
  }

  /// Recalcula los tramos peatonales del plan seleccionado con la red
  /// peatonal (si terminó de cargar después de planificar). Devuelve el
  /// plan actualizado — o el original cuando no hay cambios.
  Future<TripPlan?> _refreshSelectedTripPlanAfterGraphLoad(
    TransitTripPlanner planner,
    Future<WalkGraphWorker?> workerFuture,
  ) async {
    final selected = _selectedTripPlan;
    if (selected == null) return null;
    try {
      final worker =
          ref.read(walkGraphProvider).value ??
          await workerFuture.timeout(const Duration(seconds: 15));
      if (worker == null) return selected;
      if (!await worker.graphLoaded().timeout(const Duration(seconds: 15))) {
        return selected;
      }
      planner.walkGraphWorker = worker;
      final refreshed = await planner.refreshWalkingSegments(selected);
      if (!mounted) return selected;
      final hasApproximateWalking = refreshed.legs.any(
        (leg) => leg.kind == TripLegKind.walking && leg.approximate,
      );
      ref
          .read(walkingSnapNullProvider.notifier)
          .setSnapNull(hasApproximateWalking);
      if (identical(refreshed, selected)) return selected;
      setState(() => _selectedTripPlan = refreshed);
      return refreshed;
    } on Object catch (error, stackTrace) {
      developer.log(
        'No se pudo refinar la caminata del plan seleccionado.',
        name: 'Rumbo',
        error: error,
        stackTrace: stackTrace,
      );
      return _selectedTripPlan ?? selected;
    }
  }

  Future<void> _startActiveTrip(TripPlan plan) async {
    final l10n = AppLocalizations.of(context);
    final transitLegs = plan.legs
        .where((leg) => leg.kind == TripLegKind.transit)
        .toList(growable: false);
    if (transitLegs.isEmpty) {
      _showMessage(l10n.activeTripNoTransit);
      return;
    }
    final finalLeg = transitLegs.last;
    final destinationStop = finalLeg.toStop;
    final variant = finalLeg.variant;
    if (destinationStop == null || variant == null) {
      _showMessage(l10n.activeTripRouteUnavailable);
      return;
    }
    late final List<Stop> variantStops;
    try {
      variantStops = await ref.read(variantStopsProvider(variant.id).future);
    } on Exception {
      if (mounted) _showMessage(l10n.activeTripRouteUnavailable);
      return;
    }
    if (!mounted) return;
    final result = await ref
        .read(activeTripControllerProvider.notifier)
        .start(
          variantStops: variantStops,
          destinationStop: destinationStop,
          progressTitle: l10n.activeTripNotificationTitle,
          progressBody: l10n.activeTripNotificationProgress(
            '{stops}',
            '{stop}',
          ),
          progressBodySingular: l10n.activeTripNotificationProgressOne(
            '{stop}',
          ),
          alertTitle: l10n.activeTripAlertTitle,
          alertBody: l10n.activeTripAlertBody('{stop}'),
          backgroundNotificationText: l10n.activeTripBackgroundNotice,
        );
    if (!mounted) return;
    switch (result) {
      case ActiveTripStartResult.started:
        _showMessage(l10n.activeTripStarted);
      case ActiveTripStartResult.alreadyActive:
        break;
      case ActiveTripStartResult.unsupportedPlatform:
        _showMessage(l10n.activeTripUnsupported);
      case ActiveTripStartResult.serviceDisabled:
        _showMessage(l10n.activeTripLocationDisabled);
      case ActiveTripStartResult.locationPermissionRequired:
        _showMessage(l10n.activeTripLocationPermission);
      case ActiveTripStartResult.backgroundPermissionRequired:
        await _showBackgroundPermissionHelp();
      case ActiveTripStartResult.locationUnavailable:
        _showMessage(l10n.activeTripLocationUnavailable);
      case ActiveTripStartResult.notificationsPermissionRequired:
        _showMessage(l10n.activeTripNotificationsRequired);
      case ActiveTripStartResult.storageUnavailable:
        _showMessage(l10n.activeTripStorageUnavailable);
      case ActiveTripStartResult.invalidRoute:
        _showMessage(l10n.activeTripRouteUnavailable);
    }
  }

  Future<void> _showBackgroundPermissionHelp() async {
    final l10n = AppLocalizations.of(context);
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.activeTripPermissionTitle),
        content: Text(l10n.activeTripPermissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.activeTripOpenSettings),
          ),
        ],
      ),
    );
    if (openSettings == true && mounted) {
      await ref.read(locationRepositoryProvider).openAppSettings();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
              const SizedBox(height: 8),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
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
    setState(() => _selectedStopId = stop.id);
    var shouldPlan = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => StopDetailsSheet(
        stop: stop,
        onHowToGetThere: () {
          shouldPlan = true;
          Navigator.of(context).pop();
        },
        onRouteSelected: (route) {
          Navigator.of(context).pop();
          unawaited(_showLineDetails(route));
        },
      ),
    );
    if (mounted) setState(() => _selectedStopId = null);
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
      case MapLocationStatus.available:
        await _requestLocation();
      case MapLocationStatus.loading:
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
    final primary = isDark ? AppColors.darkPrimary : AppColors.rumbo;
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
        strokeColor: AppColors.surface,
      ),
    ];
  }

  List<Layer> _stopLayers(List<Stop> stops) {
    if (stops.isEmpty) return const [];
    final points = [
      for (final stop in stops)
        Feature<Point>(
          geometry: Point(Geographic(lon: stop.longitude, lat: stop.latitude)),
        ),
    ];
    final selectedStop = stops.where((stop) => stop.id == _selectedStopId);
    return [
      MarkerLayer(
        points: points,
        textField: '■',
        textFont: const ['Open Sans Regular', 'Arial Unicode MS Regular'],
        textSize: 24,
        textColor: AppColors.rumbo,
        textHaloColor: AppColors.surface,
        textHaloWidth: 1.5,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      MarkerLayer(
        points: points,
        textField: '●',
        textFont: const ['Open Sans Regular', 'Arial Unicode MS Regular'],
        textSize: 9,
        textColor: AppColors.surface,
        textHaloColor: AppColors.rumbo,
        textHaloWidth: .5,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      if (selectedStop.isNotEmpty)
        CircleLayer(
          points: [
            Feature<Point>(
              geometry: Point(
                Geographic(
                  lon: selectedStop.first.longitude,
                  lat: selectedStop.first.latitude,
                ),
              ),
            ),
          ],
          radius: 15,
          color: AppColors.transparent,
          strokeWidth: 3,
          strokeColor: AppColors.lime,
        ),
    ];
  }

  List<Layer> _selectedRouteLayers(Shape? shape) {
    if (shape == null || shape.points.length < 2) return const [];
    final route = [
      Feature<LineString>(
        geometry: LineString.from([
          for (final point in shape.points)
            Geographic(lon: point.longitude, lat: point.latitude),
        ]),
      ),
    ];
    return [
      _RoundedPolylineLayer(list: route, color: AppColors.surface, width: 7),
      _RoundedPolylineLayer(list: route, color: _selectedRouteColor, width: 5),
    ];
  }

  List<Layer> _busLayers(List<BusPosition> buses) {
    if (buses.isEmpty) return const [];
    final points = [
      for (final bus in buses)
        Feature<Point>(
          geometry: Point(Geographic(lon: bus.longitude, lat: bus.latitude)),
        ),
    ];
    return [
      CircleLayer(
        points: points,
        radius: 10,
        color: AppColors.lime,
        strokeWidth: 2,
        strokeColor: AppColors.surface,
      ),
      MarkerLayer(
        points: points,
        textField: '●',
        textFont: const ['Open Sans Regular', 'Arial Unicode MS Regular'],
        textSize: 11,
        textColor: AppColors.ink,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    ];
  }

  List<BusPosition> _visibleBusesFor(
    LiveBusesState state, {
    required Set<String> selectedLines,
    required Set<int> selectedVariantIds,
  }) {
    final cached = _cachedVisibleBuses;
    if (cached != null &&
        identical(state.positions, _cachedBusSourcePositions) &&
        identical(state.visibleBounds, _cachedBusBounds) &&
        state.maxMarkers == _cachedBusMarkerLimit &&
        setEquals(selectedLines, _cachedBusLines) &&
        setEquals(selectedVariantIds, _cachedBusVariantIds)) {
      return cached;
    }

    final visible = state.filteredPositions(
      selectedLines: selectedLines,
      selectedVariantIds: selectedVariantIds,
    );
    _cachedBusSourcePositions = state.positions;
    _cachedBusBounds = state.visibleBounds;
    _cachedBusMarkerLimit = state.maxMarkers;
    _cachedBusLines = Set<String>.of(selectedLines);
    _cachedBusVariantIds = Set<int>.of(selectedVariantIds);
    return _cachedVisibleBuses = visible;
  }

  List<Layer> _mapLayers({
    required List<Stop> stops,
    required List<Stop>? fallbackStops,
    required Shape? shape,
    required MapLocationState locationState,
    required List<BusPosition> buses,
    required bool isDark,
  }) {
    final location = locationState.location;
    final shapeKey = identityHashCode(shape);
    final routeStopsKey = identityHashCode(fallbackStops);
    final locationKey = Object.hash(
      locationState.status,
      location?.latitude,
      location?.longitude,
      location?.accuracyMeters,
      _metersPerPixel,
    );
    final busKey = identityHashCode(buses);
    final signature = Object.hash(
      identityHashCode(stops),
      identityHashCode(_selectedTripPlan),
      shapeKey,
      routeStopsKey,
      locationKey,
      busKey,
      _selectedStopId,
      isDark,
    );
    final cached = _cachedMapLayers;
    if (cached != null && signature == _mapLayerSignature) return cached;

    final layers = <Layer>[
      ..._tripPlanLayers(_selectedTripPlan),
      ..._selectedRouteLayers(shape),
      ..._stopLayers(
        {
          for (final stop in [...stops, ...?fallbackStops]) stop.id: stop,
        }.values.toList(growable: false),
      ),
      ..._busLayers(
        _selectedTripPlan == null
            ? buses
            : buses.where((bus) {
                final planLines = {
                  for (final leg in _selectedTripPlan!.legs)
                    if (leg.kind == TripLegKind.transit && leg.route != null)
                      leg.route!.shortName.isNotEmpty
                          ? leg.route!.shortName
                          : leg.route!.id,
                };
                return planLines.contains(bus.lineLabel);
              }).toList(),
      ),
      ..._locationLayers(locationState, isDark),
    ];
    _mapLayerSignature = signature;
    return _cachedMapLayers = List<Layer>.unmodifiable(layers);
  }

  List<Layer> _tripPlanLayers(TripPlan? plan) {
    if (plan == null) return const [];

    final realWalkingPoints = <Feature<LineString>>[];
    final approxWalkingPoints = <Feature<LineString>>[];
    final transitPoints = <Feature<LineString>>[];
    for (final leg in plan.legs) {
      if (leg.kind == TripLegKind.waiting) continue;

      if (leg.kind == TripLegKind.walking) {
        // Tramos peatonales: geometría real de la red peatonal; sin red ni
        // snap válido, línea recta punteada marcada como aproximada.
        final walkPoints = leg.shape?.points;
        if (walkPoints == null || walkPoints.length < 2) continue;
        if (leg.gapMeters > 0) {
          // Segmento punteado user→proyectado: los primeros dos puntos del
          // camino real son el punto real del usuario y el vértice proyectado
          // donde empieza la red; lo demás es camino real sólido.
          approxWalkingPoints.add(
            Feature<LineString>(
              geometry: LineString.from([
                Geographic(
                  lon: walkPoints[0].longitude,
                  lat: walkPoints[0].latitude,
                ),
                Geographic(
                  lon: walkPoints[1].longitude,
                  lat: walkPoints[1].latitude,
                ),
              ]),
            ),
          );
          if (walkPoints.sublist(1).length >= 2) {
            realWalkingPoints.add(
              Feature<LineString>(
                geometry: LineString.from([
                  for (final point in walkPoints.sublist(1))
                    Geographic(lon: point.longitude, lat: point.latitude),
                ]),
              ),
            );
          }
          if (walkPoints.length >= 2) {
            final penultimate = walkPoints[walkPoints.length - 2];
            final destination = walkPoints.last;
            if (penultimate.latitude != destination.latitude ||
                penultimate.longitude != destination.longitude) {
              approxWalkingPoints.add(
                Feature<LineString>(
                  geometry: LineString.from([
                    Geographic(
                      lon: penultimate.longitude,
                      lat: penultimate.latitude,
                    ),
                    Geographic(
                      lon: destination.longitude,
                      lat: destination.latitude,
                    ),
                  ]),
                ),
              );
            }
          }
        } else {
          final feature = Feature<LineString>(
            geometry: LineString.from([
              for (final point in walkPoints)
                Geographic(lon: point.longitude, lat: point.latitude),
            ]),
          );
          if (leg.approximate) {
            approxWalkingPoints.add(feature);
          } else {
            realWalkingPoints.add(feature);
          }
        }
        continue;
      }

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
      final variant = leg.variant;
      final shape = variant == null ? null : _tripPlanShapes[variant.id];
      if (shape == null) continue;
      final points = _shapeSegment(
        shape,
        fromLatitude: fromLat,
        fromLongitude: fromLon,
        toLatitude: toLat,
        toLongitude: toLon,
      );
      if (points.length < 2) continue;
      transitPoints.add(Feature<LineString>(geometry: LineString.from(points)));
    }

    final layers = <Layer>[];
    final routeColor = AppColors.rumbo;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (realWalkingPoints.isNotEmpty) {
      layers.add(
        PolylineLayer(
          polylines: realWalkingPoints,
          color: routeColor.withValues(alpha: 0.72),
          width: 4,
        ),
      );
    }
    if (approxWalkingPoints.isNotEmpty) {
      layers.add(
        PolylineLayer(
          polylines: approxWalkingPoints,
          color: routeColor.withValues(alpha: 0.72),
          width: 4,
          dashArray: const [2, 3],
        ),
      );
    }
    if (transitPoints.isNotEmpty) {
      layers
        ..add(
          _RoundedPolylineLayer(
            list: transitPoints,
            color: AppColors.surface,
            width: 7,
          ),
        )
        ..add(
          _RoundedPolylineLayer(
            list: transitPoints,
            color: routeColor,
            width: 5,
          ),
        );
    }

    final origin = _tripPlanEndpoint(plan, first: true);
    if (origin != null) {
      layers.add(
        CircleLayer(
          points: [Feature<Point>(geometry: Point(origin))],
          radius: 7,
          color: isDark ? AppColors.ivory : AppColors.ink,
          strokeWidth: 3,
          strokeColor: isDark ? AppColors.ink : AppColors.surface,
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
          strokeColor: isDark ? AppColors.ivory : AppColors.ink,
        ),
      );
    }
    return layers;
  }

  List<Geographic> _shapeSegment(
    Shape shape, {
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    if (shape.points.length < 2) return const [];
    var fromIndex = 0;
    var toIndex = 0;
    var fromDistance = double.infinity;
    var toDistance = double.infinity;
    for (var index = 0; index < shape.points.length; index++) {
      final point = shape.points[index];
      final fromCandidate = _distanceMeters(
        fromLatitude,
        fromLongitude,
        point.latitude,
        point.longitude,
      );
      final toCandidate = _distanceMeters(
        toLatitude,
        toLongitude,
        point.latitude,
        point.longitude,
      );
      if (fromCandidate < fromDistance) {
        fromDistance = fromCandidate;
        fromIndex = index;
      }
      if (toCandidate < toDistance) {
        toDistance = toCandidate;
        toIndex = index;
      }
    }
    final start = math.min(fromIndex, toIndex);
    final end = math.max(fromIndex, toIndex);
    final segment = shape.points
        .sublist(start, end + 1)
        .map((point) => Geographic(lon: point.longitude, lat: point.latitude))
        .toList(growable: false);
    return segment.length >= 2
        ? segment
        : [
            Geographic(lon: fromLongitude, lat: fromLatitude),
            Geographic(lon: toLongitude, lat: toLatitude),
          ];
  }

  Future<void> _loadTripPlanShapes(TripPlan plan) async {
    final variants = {
      for (final leg in plan.legs)
        if (leg.kind == TripLegKind.transit && leg.variant != null)
          leg.variant!,
    };
    if (variants.isEmpty) return;
    final variantIds = variants.map((variant) => variant.id).toSet();
    _tripPlanShapes.removeWhere((id, _) => !variantIds.contains(id));
    final shapes = await Future.wait(
      variants.map(
        (variant) async => MapEntry(
          variant.id,
          await ref.read(routeShapeProvider(variant.id).future),
        ),
      ),
    );
    if (!mounted) return;
    var changed = false;
    for (final entry in shapes) {
      final shape = entry.value;
      if (shape != null && !identical(_tripPlanShapes[entry.key], shape)) {
        _tripPlanShapes[entry.key] = shape;
        changed = true;
      }
    }
    if (changed) setState(() {});
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
    final routeColor = AppColors.rumbo;
    ref
        .read(liveBusesControllerProvider.notifier)
        .setSelectedLines(_lineLabelsFor(route));
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
    await _showLineDetails(route);
  }

  Set<String> _lineLabelsFor(Route route) {
    if (route.shortName.isNotEmpty) return {route.shortName};
    if (route.id.isNotEmpty) return {route.id};
    return {};
  }

  Future<void> _showLineDetails(Route route, {String? initialVariantId}) async {
    final routeColor = AppColors.rumbo;
    ref
        .read(liveBusesControllerProvider.notifier)
        .setSelectedLines(_lineLabelsFor(route));
    setState(() {
      _selectedTripPlan = null;
      _selectedVariantId = initialVariantId;
      _selectedRoute = route;
      _selectedRouteColor = routeColor;
    });

    final variants = await ref.read(lineVariantsProvider(route.id).future);
    RouteVariant? variant;
    if (initialVariantId != null) {
      variant = variants.where((v) => v.id == initialVariantId).firstOrNull;
    }
    variant ??= variants.firstOrNull;

    if (variant != null && mounted) {
      setState(() => _selectedVariantId = variant!.id);
      final shape = await ref.read(routeShapeProvider(variant.id).future);
      var points = shape?.points;
      if (points == null || points.isEmpty) {
        final stops = await ref.read(variantStopsProvider(variant.id).future);
        points = [
          for (var i = 0; i < stops.length; i++)
            ShapePoint(stops[i].latitude, stops[i].longitude, i),
        ];
      }
      if (points.isNotEmpty && mounted) {
        final middle = points[points.length ~/ 2];
        await _mapController?.animateCamera(
          center: Geographic(lon: middle.longitude, lat: middle.latitude),
          zoom: 12.5,
          padding: EdgeInsets.only(
            bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
          ),
        );
      }
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => LineDetailsSheet(
        route: route,
        initialVariantId: variant?.id,
        onClose: () => Navigator.of(sheetContext).pop(),
        onVariantSelected: (newVariant) async {
          setState(() => _selectedVariantId = newVariant.id);
          final shape = await ref.read(
            routeShapeProvider(newVariant.id).future,
          );
          var points = shape?.points;
          if (points == null || points.isEmpty) {
            final stops = await ref.read(
              variantStopsProvider(newVariant.id).future,
            );
            points = [
              for (var i = 0; i < stops.length; i++)
                ShapePoint(stops[i].latitude, stops[i].longitude, i),
            ];
          }
          if (points.isNotEmpty && mounted) {
            final middle = points[points.length ~/ 2];
            await _mapController?.animateCamera(
              center: Geographic(lon: middle.longitude, lat: middle.latitude),
              zoom: 12.5,
              padding: EdgeInsets.only(
                bottom: MediaQuery.sizeOf(context).height * _sheetExtent,
              ),
            );
          }
        },
        onStopSelected: (stop) {
          Navigator.of(sheetContext).pop();
          unawaited(_showStopDetails(stop));
        },
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
    ref.listen(liveBusesEnabledProvider, (previous, next) {
      final enabled = next.asData?.value;
      if (enabled == false) {
        ref.read(liveBusesControllerProvider.notifier).setEnabled(false);
      } else if (enabled == true) {
        _syncRealtimePolling();
      }
    });
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
    final activeTrip = ref.watch(activeTripControllerProvider);
    final selectedRoute = _selectedRoute;
    final Map<String, Route> selectedRoutes = selectedRoute == null
        ? {}
        : {selectedRoute.id: selectedRoute};
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
    final busesInVisibleArea = _visibleBusesFor(
      liveBuses,
      selectedLines: selectedRoute == null ? const {} : selectedLines,
      selectedVariantIds: selectedRoute == null ? const {} : selectedVariantIds,
    );
    final selectedShapeAsync = _selectedVariantId == null
        ? null
        : ref.watch(routeShapeProvider(_selectedVariantId!));
    final selectedShape = selectedShapeAsync?.asData?.value;
    final fallbackStops = _selectedVariantId == null
        ? null
        : ref.watch(variantStopsProvider(_selectedVariantId!)).asData?.value;
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
          layers: _mapLayers(
            stops: stops,
            fallbackStops: fallbackStops,
            shape: selectedShape,
            locationState: locationState,
            buses: busesInVisibleArea,
            isDark: isDark,
          ),
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
                    FloatingSearchBar(
                      keyValue: 'map-search-control',
                      label: l10n.mapSearchPlaceholder,
                      onTap: _showTripSearch,
                    ),
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
                    if (liveBuses.shouldShowError &&
                        networkState.asData?.value != false)
                      _InfoBanner(
                        icon: Symbols.cloud_off_rounded,
                        label: l10n.mapLiveServiceDown,
                      ),
                    if (_selectedVariantId != null &&
                        selectedShapeAsync?.hasValue == true &&
                        (selectedShape == null ||
                            selectedShape.points.length < 2))
                      _InfoBanner(
                        icon: Symbols.route_rounded,
                        label: l10n.mapRouteShapeUnavailable,
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
                  child: Center(
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: l10n.locationRecenter,
                        onPressed: () =>
                            _handleLocationAction(locationState.status),
                        icon: locationState.status == MapLocationStatus.loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Symbols.my_location_rounded),
                      ),
                    ),
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
                      constraints: BoxConstraints(
                        minHeight: 48,
                        maxWidth: MediaQuery.sizeOf(context).width - 32,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                l10n.mapAttributionShort,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
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
              initialChildSize: _selectedTripPlan == null
                  ? 0.23
                  : tripPlanSheetMinimumExtent,
              minChildSize: _selectedTripPlan == null
                  ? 0.18
                  : tripPlanSheetMinimumExtent,
              maxChildSize: _selectedTripPlan == null ? 0.46 : 0.68,
              snap: true,
              snapSizes: _selectedTripPlan == null
                  ? const [0.23, 0.46]
                  : const [tripPlanSheetMinimumExtent, 0.68],
              builder: (context, scrollController) => Semantics(
                container: true,
                label: _selectedTripPlan == null
                    ? l10n.mapStopsAndBuses
                    : l10n.tripDetailTitle,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTokens.radius24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      RumboSheetHandle(label: l10n.mapStopsAndBuses),
                      const SizedBox(height: AppTokens.space8),
                      if (feedState != null &&
                          !feedState.status.synthetic &&
                          (isFeedExpired(
                                feedState.status.validUntil,
                                DateTime.now(),
                              ) ||
                              isFeedExpiringSoon(
                                feedState.status.validUntil,
                                DateTime.now(),
                              )))
                        _FeedValidityWarning(
                          validUntil: feedState.status.validUntil!,
                          onUpdate: () => unawaited(
                            ref
                                .read(feedUpdateControllerProvider.notifier)
                                .updateNow(),
                          ),
                        ),
                      if (_selectedTripPlan != null) ...[
                        TripPlanDetails(
                          plan: _selectedTripPlan!,
                          livePositions: liveBuses.positions,
                          tripPlanShapes: _tripPlanShapes,
                          originName:
                              _selectedTripOriginName ??
                              l10n.tripOriginLocationHint,
                          destinationName:
                              _selectedTripDestinationName ??
                              l10n.tripDetailUnknownStop,
                          onSwapTrip: () {
                            final originPoint = _tripPlanEndpoint(
                              _selectedTripPlan!,
                              first: true,
                            );
                            final destinationPoint = _tripPlanEndpoint(
                              _selectedTripPlan!,
                              first: false,
                            );
                            if (originPoint == null ||
                                destinationPoint == null) {
                              return;
                            }
                            unawaited(
                              _showTripSearch(
                                origin: TripEndpoint(
                                  name:
                                      _selectedTripDestinationName ??
                                      l10n.tripDetailUnknownStop,
                                  latitude: destinationPoint.lat,
                                  longitude: destinationPoint.lon,
                                ),
                                destination: TripEndpoint(
                                  name:
                                      _selectedTripOriginName ??
                                      l10n.tripOriginLocationHint,
                                  latitude: originPoint.lat,
                                  longitude: originPoint.lon,
                                ),
                              ),
                            );
                          },
                          activeTripIsActive: activeTrip.isActive,
                          activeTripStopsRemaining: activeTrip.stopsRemaining,
                          onStartActiveTrip:
                              _selectedTripPlan!.legs.any(
                                (leg) =>
                                    leg.kind == TripLegKind.transit &&
                                    leg.variant != null &&
                                    leg.toStop != null,
                              )
                              ? () => unawaited(
                                  _startActiveTrip(_selectedTripPlan!),
                                )
                              : null,
                          onStopActiveTrip: activeTrip.isActive
                              ? () => unawaited(
                                  ref
                                      .read(
                                        activeTripControllerProvider.notifier,
                                      )
                                      .stop(),
                                )
                              : null,
                          onChangeTrip: () {
                            if (activeTrip.isActive) {
                              unawaited(
                                ref
                                    .read(activeTripControllerProvider.notifier)
                                    .stop(),
                              );
                            }
                            ref
                                .read(liveBusesControllerProvider.notifier)
                                .setSelectedLines(const {});
                            setState(() {
                              _selectedTripPlan = null;
                              _selectedTripOriginName = null;
                              _selectedTripDestinationName = null;
                            });
                            unawaited(_showTripSearch());
                          },
                          onCloseTrip: () {
                            ref
                                .read(liveBusesControllerProvider.notifier)
                                .setSelectedLines(const {});
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
                        if (activeTrip.isActive &&
                            activeTrip.stopsRemaining != null) ...[
                          TripProgressCard(
                            title: l10n.activeTripNotificationTitle,
                            subtitle: l10n.activeTripStopsRemaining(
                              activeTrip.stopsRemaining!,
                              activeTrip.targetStopName ??
                                  l10n.tripDetailUnknownStop,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PrimaryActionButton(
                            onPressed: () => unawaited(
                              ref
                                  .read(activeTripControllerProvider.notifier)
                                  .stop(),
                            ),
                            icon: const Icon(Symbols.stop_circle_rounded),
                            label: l10n.activeTripFinish,
                          ),
                          const SizedBox(height: 12),
                        ],
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
                                  leading: Icon(
                                    Symbols.location_on_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
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
                                feedAsync.isLoading ||
                                feedState?.phase ==
                                    FeedUpdatePhase.downloading ||
                                feedState?.phase ==
                                    FeedUpdatePhase.processing) &&
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
                                      ? feedState?.phase ==
                                                    FeedUpdatePhase
                                                        .processing &&
                                                feedState!.progress > .35
                                            ? l10n.mapFeedProgress(
                                                (feedState.progress * 100)
                                                    .round(),
                                              )
                                            : l10n.mapFeedLoading
                                      : l10n.mapStopsLoading,
                                ),
                              ),
                            ],
                          )
                        else if ((feedState?.phase == FeedUpdatePhase.offline ||
                                feedState?.phase ==
                                    FeedUpdatePhase.errorWithOldData) &&
                            !hasOfficialTransitData(feedState))
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
                        else if (liveBuses.selectedLines.isEmpty)
                          Text(l10n.mapLiveNeedsTrip)
                        else if (liveBuses.shouldShowError)
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
                            l10n.mapLiveBusCount(busesInVisibleArea.length),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        if (stops.isEmpty && liveBuses.selectedLines.isEmpty)
                          Text(l10n.mapLiveNeedsTrip),
                        if (stops.isEmpty &&
                            liveBuses.selectedLines.isNotEmpty &&
                            liveBuses.shouldShowError)
                          Text(l10n.mapLiveError(liveBuses.error!)),
                        if (stops.isEmpty &&
                            liveBuses.selectedLines.isNotEmpty &&
                            liveBuses.lastUpdatedAt == null &&
                            !liveBuses.shouldShowError)
                          Text(l10n.mapLiveLoading),
                        if (stops.isEmpty && liveBuses.lastUpdatedAt != null)
                          Text(l10n.mapLiveBusCount(busesInVisibleArea.length)),
                        if (liveBuses.lastUpdatedAt != null &&
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
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    child: Text(
                                      bus.lineLabel,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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

class _FeedValidityWarning extends StatelessWidget {
  const _FeedValidityWarning({
    required this.validUntil,
    required this.onUpdate,
  });

  final DateTime validUntil;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date =
        '${validUntil.year.toString().padLeft(4, '0')}-'
        '${validUntil.month.toString().padLeft(2, '0')}-'
        '${validUntil.day.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Symbols.warning_amber_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.transitValidityWarning(date)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onUpdate,
                      child: Text(l10n.transitUpdateNow),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
                  Text(
                    label,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
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
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
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
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
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
        padding: const EdgeInsets.all(8),
        child: EmptyState(
          icon: Icon(
            Symbols.map_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: l10n.mapErrorTitle,
          message: l10n.mapErrorBody,
          footer: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh_rounded),
            label: Text(l10n.actionRetry),
          ),
        ),
      ),
    );
  }
}

class _RoundedPolylineLayer extends Layer<Feature<LineString>> {
  const _RoundedPolylineLayer({
    required super.list,
    required this.color,
    required this.width,
  });

  final Color color;
  final int width;

  @override
  Map<String, Object> getPaint() => {
    'line-color': color.toHexString(),
    'line-opacity': color.a,
    'line-width': width,
  };

  @override
  Map<String, Object> getLayout() => {
    'line-cap': 'round',
    'line-join': 'round',
  };

  @override
  StyleLayer createStyleLayer(int index) => LineStyleLayer(
    id: getLayerId(index),
    sourceId: getSourceId(index),
    paint: getPaint(),
    layout: getLayout(),
    minZoom: minZoom,
    maxZoom: maxZoom,
  );
}
