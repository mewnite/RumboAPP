import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/widgets/line_chip.dart';
import '../../../features/search/domain/place_search_service.dart';
import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/planner_config.dart';
import '../domain/trip_planner.dart';

typedef StopSearch = Future<List<Stop>> Function(String query);
typedef PlaceSearch = Future<List<TripEndpoint>> Function(String query);
typedef PlanSearch = Future<List<TripPlan>> Function(
  TripEndpoint? origin,
  TripEndpoint destination,
  TripTiming timing,
  PlannerConfig config,
);
typedef TripPlanSelected = void Function(
  TripPlan plan,
  TripEndpoint? origin,
  TripEndpoint destination,
);
typedef DepartureTimePicker = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay initialTime,
);

class TripSearchSheet extends StatefulWidget {
  const TripSearchSheet({
    required this.searchStops,
    required this.searchPlaces,
    required this.findPlans,
    required this.hasCurrentLocation,
    this.remotePlaceSearchEnabled = false,
    this.onRemotePlaceSearchConsentRequested,
    this.searchService,
    this.initialDestination,
    this.onPlanSelected,
    this.onRouteSelected,
    this.departureTimePicker,
    this.now,
    this.initialConfig = const PlannerConfig(),
    super.key,
  });

  final StopSearch searchStops;
  final PlaceSearch searchPlaces;
  final PlanSearch findPlans;
  final bool hasCurrentLocation;
  final bool remotePlaceSearchEnabled;
  final Future<bool> Function()? onRemotePlaceSearchConsentRequested;
  final PlaceSearchService? searchService;
  final TripEndpoint? initialDestination;
  final TripPlanSelected? onPlanSelected;
  final ValueChanged<Route>? onRouteSelected;
  final DepartureTimePicker? departureTimePicker;
  final DateTime Function()? now;
  final PlannerConfig initialConfig;

  @override
  State<TripSearchSheet> createState() => _TripSearchSheetState();
}

class _TripSearchSheetState extends State<TripSearchSheet> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _originFocus = FocusNode();
  final _destinationFocus = FocusNode();
  Timer? _debounce;
  TripEndpoint? _origin;
  TripEndpoint? _destination;
  List<TripEndpoint> _suggestions = const [];
  List<TripPlan>? _plans;
  Object? _searchError;
  Object? _planError;
  bool _searching = false;
  bool _planning = false;
  bool _originUsesLocation = true;
  bool _searchOrigin = false;
  bool _askedRemoteConsent = false;
  late bool _remoteSearchEnabled;
  TripTimingMode _timingMode = TripTimingMode.departNow;
  late DateTime _timedDateTime;
  bool _tomorrow = false;
  TripTiming? _lastTiming;
  late PlannerConfig _config;
  TripPlanSort _sort = TripPlanSort.fastest;

  TextEditingController get _activeController =>
      _searchOrigin ? _originController : _destinationController;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  TripTiming get _timing => switch (_timingMode) {
    TripTimingMode.departNow => const TripTiming.departNow(),
    TripTimingMode.departAt => TripTiming.departAt(_timedDateTime),
    TripTimingMode.arriveBy => TripTiming.arriveBy(_timedDateTime),
  };

  bool get _isPast =>
      _timingMode != TripTimingMode.departNow && _timing.isPast(_now);

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _remoteSearchEnabled = widget.remotePlaceSearchEnabled;
    _timedDateTime = _nextTimeSlot(_now);
    _tomorrow = _isTomorrowDate(_timedDateTime);
    if (widget.initialDestination != null) {
      _destination = widget.initialDestination;
      _destinationController.text = widget.initialDestination!.name;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final normalizedQuery = query.trim();
    setState(() {
      _suggestions = const [];
      _searchError = null;
      _searching = normalizedQuery.isNotEmpty;
    });
    if (normalizedQuery.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final shouldOfferOnlineSearch =
            normalizedQuery.length >= 3 &&
            RegExp(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]').hasMatch(normalizedQuery) &&
            !_remoteSearchEnabled &&
            !_askedRemoteConsent &&
            widget.onRemotePlaceSearchConsentRequested != null;
        if (shouldOfferOnlineSearch) {
          _askedRemoteConsent = true;
          final accepted = await widget.onRemotePlaceSearchConsentRequested!
              .call();
          if (!mounted || _activeController.text.trim() != normalizedQuery) {
            return;
          }
          if (accepted) setState(() => _remoteSearchEnabled = true);
        }

        List<TripEndpoint> endpoints;
        if (widget.searchService != null) {
          final results = await widget.searchService!.search(
            query: normalizedQuery,
            allowRemote: _remoteSearchEnabled,
          );
          endpoints = results.map((result) => result.toTripEndpoint()).toList();
        } else {
          final stops = await widget.searchStops(normalizedQuery);
          endpoints = stops.map(TripEndpoint.fromStop).toList();
          if (_remoteSearchEnabled && normalizedQuery.length >= 3) {
            final places = await widget.searchPlaces(normalizedQuery);
            final seen = endpoints.map(_endpointKey).toSet();
            endpoints.addAll(
              places.where((place) => seen.add(_endpointKey(place))),
            );
          }
        }
        if (mounted && _activeController.text.trim() == normalizedQuery) {
          setState(() {
            _suggestions = endpoints;
            _searching = false;
          });
        }
      } on Exception catch (error) {
        if (mounted && _activeController.text.trim() == normalizedQuery) {
          setState(() {
            _searchError = error;
            _searching = false;
          });
        }
      }
    });
  }

  String _endpointKey(TripEndpoint endpoint) =>
      '${endpoint.latitude}:${endpoint.longitude}';

  void _selectEndpoint(TripEndpoint endpoint) {
    setState(() {
      if (_searchOrigin) {
        _origin = endpoint;
        _originUsesLocation = false;
        _originController.text = endpoint.name;
      } else {
        _destination = endpoint;
        _destinationController.text = endpoint.name;
      }
      _suggestions = const [];
      _plans = null;
      _searchError = null;
    });
    FocusScope.of(context).unfocus();
  }

  DateTime _nextTimeSlot(DateTime now) {
    final minutes = (now.minute ~/ 10 + 1) * 10;
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(Duration(minutes: minutes));
  }

  bool _isTomorrowDate(DateTime value) {
    final now = _now;
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return DateTime(value.year, value.month, value.day) == tomorrow;
  }

  void _clearResults() {
    _plans = null;
    _planError = null;
    _lastTiming = null;
  }

  void _selectTimingMode(TripTimingMode mode) {
    if (_timingMode == mode) return;
    setState(() {
      _timingMode = mode;
      if (mode != TripTimingMode.departNow && !_timedDateTime.isAfter(_now)) {
        _timedDateTime = _nextTimeSlot(_now);
      }
      _tomorrow = _isTomorrowDate(_timedDateTime);
      _clearResults();
    });
  }

  void _selectDay(bool tomorrow) {
    setState(() {
      final day = _now.add(Duration(days: tomorrow ? 1 : 0));
      _timedDateTime = DateTime(
        day.year,
        day.month,
        day.day,
        _timedDateTime.hour,
        _timedDateTime.minute,
      );
      _tomorrow = tomorrow;
      _clearResults();
    });
  }

  Future<bool> _pickDepartureTime() async {
    final l10n = AppLocalizations.of(context);
    final initialTime = TimeOfDay.fromDateTime(_timedDateTime);
    final selected =
        await (widget.departureTimePicker?.call(context, initialTime) ??
            showTimePicker(
              context: context,
              initialTime: initialTime,
              helpText: l10n.tripTimingLabel,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(alwaysUse24HourFormat: true),
                child: child!,
              ),
            ));
    if (!mounted || selected == null) return false;
    setState(() {
      _timedDateTime = DateTime(
        _timedDateTime.year,
        _timedDateTime.month,
        _timedDateTime.day,
        selected.hour,
        selected.minute,
      );
      _clearResults();
    });
    return true;
  }

  String _departureTimeText(BuildContext context) => _clock(_timedDateTime);

  String _dayLabel(AppLocalizations l10n) {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _timedDateTime.year,
      _timedDateTime.month,
      _timedDateTime.day,
    );
    if (selected == today) return l10n.tripDayToday;
    if (selected == today.add(const Duration(days: 1))) {
      return l10n.tripDayTomorrow;
    }
    return MaterialLocalizations.of(context).formatMediumDate(_timedDateTime);
  }

  String _timingSummary(AppLocalizations l10n) {
    final time = _departureTimeText(context);
    return switch (_timingMode) {
      TripTimingMode.departNow => l10n.tripTimingSummaryNow,
      TripTimingMode.departAt => l10n.tripTimingSummaryDepart(
        _dayLabel(l10n),
        time,
      ),
      TripTimingMode.arriveBy => l10n.tripTimingSummaryArrive(
        _dayLabel(l10n),
        time,
      ),
    };
  }

  Future<void> _findPlans() async {
    final destination = _destination;
    if (destination == null ||
        (!_originUsesLocation && _origin == null) ||
        (_originUsesLocation && !widget.hasCurrentLocation)) {
      return;
    }
    final timing = _timing;
    if (timing.isPast(_now)) {
      setState(_clearResults);
      return;
    }
    setState(() {
      _lastTiming = timing;
      _planning = true;
      _planError = null;
      _plans = null;
    });
    try {
      final plans = await widget.findPlans(
        _originUsesLocation ? null : _origin,
        destination,
        timing,
        _config,
      );
      if (mounted) setState(() => _plans = plans);
    } on Exception catch (error) {
      if (mounted) setState(() => _planError = error);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _selectWalkingLimit(double meters) async {
    if (_config.maximumWalkingMeters == meters) return;
    final shouldRerun = _lastTiming != null;
    setState(() {
      _config = _config.copyWith(maximumWalkingMeters: meters);
      _plans = null;
      _planError = null;
    });
    if (shouldRerun) await _findPlans();
  }

  Future<void> _expandWalking() async {
    for (final meters in PlannerConfig.walkingOptionsMeters) {
      if (meters > _config.maximumWalkingMeters) {
        await _selectWalkingLimit(meters);
        return;
      }
    }
  }

  Future<void> _changeTimeFromEmptyState() async {
    if (_timingMode == TripTimingMode.departNow) {
      setState(() {
        _timingMode = TripTimingMode.departAt;
        if (!_timedDateTime.isAfter(_now)) {
          _timedDateTime = _nextTimeSlot(_now);
        }
        _tomorrow = _isTomorrowDate(_timedDateTime);
        _clearResults();
      });
    }
    final picked = await _pickDepartureTime();
    if (!picked || !mounted) return;
    final canPlan =
        _destination != null &&
        (_originUsesLocation ? widget.hasCurrentLocation : _origin != null);
    if (!canPlan || _timing.isPast(_now)) return;
    await _findPlans();
  }

  void _useLocation() {
    setState(() {
      _originUsesLocation = true;
      _origin = null;
      _originController.clear();
      _searchOrigin = false;
      _suggestions = const [];
      _plans = null;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPlan =
        _destination != null &&
        (_originUsesLocation ? widget.hasCurrentLocation : _origin != null);
    final shownPlans = _plans == null
        ? const <TripPlan>[]
        : sortTripPlans(_plans!, _sort);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(
              l10n.tripSearchTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _originController,
              focusNode: _originFocus,
              onTap: () {
                setState(() {
                  _searchOrigin = true;
                  _suggestions = const [];
                });
              },
              onChanged: (value) {
                _searchOrigin = true;
                _originUsesLocation = false;
                _origin = null;
                _search(value);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Symbols.trip_origin_rounded),
                hintText: widget.hasCurrentLocation
                    ? l10n.tripOriginLocationHint
                    : l10n.tripOriginStopHint,
                labelText: l10n.tripOriginLabel,
                suffixIcon: widget.hasCurrentLocation
                    ? IconButton(
                        tooltip: l10n.tripUseCurrentLocation,
                        onPressed: _useLocation,
                        icon: const Icon(Symbols.my_location_rounded),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _destinationController,
              focusNode: _destinationFocus,
              onTap: () {
                setState(() {
                  _searchOrigin = false;
                  _suggestions = const [];
                });
              },
              onChanged: (value) {
                _searchOrigin = false;
                _destination = null;
                _search(value);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Symbols.location_on_rounded),
                hintText: l10n.tripDestinationHint,
                labelText: l10n.tripDestinationLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l10n.tripSearchError(_searchError.toString()),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (_activeController.text.trim().isNotEmpty &&
                _suggestions.isEmpty &&
                (_originFocus.hasFocus || _destinationFocus.hasFocus))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _remoteSearchEnabled ? l10n.tripNoPlaces : l10n.tripNoStops,
                ),
              )
            else if (_suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final endpoint = _suggestions[index];
                    if (endpoint.route != null) {
                      return ListTile(
                        key: ValueKey(
                          'trip-endpoint-${_endpointKey(endpoint)}',
                        ),
                        leading: const Icon(Symbols.alt_route_rounded),
                        title: Text(endpoint.name),
                        subtitle: Text(l10n.searchKindRoute),
                        onTap: () {
                          if (widget.onRouteSelected != null) {
                            widget.onRouteSelected!(endpoint.route!);
                          } else {
                            _selectEndpoint(endpoint);
                          }
                        },
                      );
                    }
                    return ListTile(
                      key: ValueKey('trip-endpoint-${_endpointKey(endpoint)}'),
                      leading: Icon(
                        endpoint.stop == null
                            ? Symbols.place_rounded
                            : Symbols.directions_bus_rounded,
                      ),
                      title: Text(endpoint.name),
                      subtitle: endpoint.stop == null
                          ? Text(l10n.tripPlaceResult)
                          : endpoint.stop!.code.isEmpty
                          ? Text(l10n.tripStopResult)
                          : Text(
                              '${l10n.tripStopResult} · ${endpoint.stop!.code}',
                            ),
                      onTap: () => _selectEndpoint(endpoint),
                    );
                  },
                ),
              ),
            if (_remoteSearchEnabled &&
                _activeController.text.trim().length >= 3) ...[
              const SizedBox(height: 8),
              Text(
                l10n.tripGeocodingPrivacy,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.tripTimingLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('trip-timing-now'),
                  label: Text(l10n.tripTimingNow),
                  selected: _timingMode == TripTimingMode.departNow,
                  onSelected: _planning
                      ? null
                      : (_) => _selectTimingMode(TripTimingMode.departNow),
                ),
                ChoiceChip(
                  key: const ValueKey('trip-timing-depart-at'),
                  label: Text(l10n.tripTimingDepartAt),
                  selected: _timingMode == TripTimingMode.departAt,
                  onSelected: _planning
                      ? null
                      : (_) => _selectTimingMode(TripTimingMode.departAt),
                ),
                ChoiceChip(
                  key: const ValueKey('trip-timing-arrive-by'),
                  label: Text(l10n.tripTimingArriveBy),
                  selected: _timingMode == TripTimingMode.arriveBy,
                  onSelected: _planning
                      ? null
                      : (_) => _selectTimingMode(TripTimingMode.arriveBy),
                ),
              ],
            ),
            if (_timingMode != TripTimingMode.departNow) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    key: const ValueKey('trip-day-today'),
                    label: Text(l10n.tripDayToday),
                    selected: !_tomorrow,
                    onSelected: _planning ? null : (_) => _selectDay(false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const ValueKey('trip-day-tomorrow'),
                    label: Text(l10n.tripDayTomorrow),
                    selected: _tomorrow,
                    onSelected: _planning ? null : (_) => _selectDay(true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: l10n.tripChangeTime,
                      child: OutlinedButton.icon(
                        key: const ValueKey('trip-departure-time'),
                        onPressed: _planning ? null : _pickDepartureTime,
                        icon: const Icon(Symbols.schedule_rounded),
                        label: Text(_departureTimeText(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                key: const ValueKey('trip-timing-summary'),
                avatar: Icon(
                  _timingMode == TripTimingMode.arriveBy
                      ? Symbols.flag_rounded
                      : Symbols.schedule_rounded,
                  size: 18,
                ),
                label: Text(_timingSummary(l10n)),
              ),
            ),
            if (_isPast)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.tripPastTime,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              l10n.tripWalkingLimitLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final meters in PlannerConfig.walkingOptionsMeters)
                  ChoiceChip(
                    key: ValueKey('trip-walking-${meters.round()}'),
                    label: Text(l10n.tripWalkingMeters(meters.round())),
                    selected: _config.maximumWalkingMeters == meters,
                    onSelected: _planning
                        ? null
                        : (_) => _selectWalkingLimit(meters),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canPlan && !_planning ? _findPlans : null,
              icon: _planning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.directions_bus_rounded),
              label: Text(
                _planning ? l10n.tripSearchingTrips : l10n.tripShowTrips,
              ),
            ),
            if (_originUsesLocation && !widget.hasCurrentLocation)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.tripLocationUnavailable,
                  textAlign: TextAlign.center,
                ),
              ),
            if (_planError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _PlanErrorCard(
                  message: l10n.tripPlanError(_planError.toString()),
                  onRetry: _findPlans,
                ),
              ),
            if (_planning)
              Padding(
                key: const ValueKey('trip-planning'),
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(l10n.tripSearchingTrips, textAlign: TextAlign.center),
                  ],
                ),
              ),
            if (_plans != null) ...[
              const SizedBox(height: 12),
              if (_plans!.isEmpty)
                _PlanEmptyState(
                  title: _lastTiming?.mode == TripTimingMode.arriveBy
                      ? l10n.tripNoArrivalTrips
                      : l10n.tripNoTrips,
                  suggestion: l10n.tripEmptySuggestions,
                  expandWalkingLabel: l10n.tripEmptyExpandWalking,
                  changeTimeLabel: l10n.tripEmptyChangeTime,
                  canExpandWalking:
                      _config.maximumWalkingMeters <
                      PlannerConfig.walkingOptionsMeters.last,
                  onExpandWalking: _expandWalking,
                  onChangeTime: _changeTimeFromEmptyState,
                )
              else ...[
                Text(
                  l10n.tripSortLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('trip-sort-fastest'),
                      label: Text(l10n.tripSortFastest),
                      selected: _sort == TripPlanSort.fastest,
                      onSelected: (_) =>
                          setState(() => _sort = TripPlanSort.fastest),
                    ),
                    ChoiceChip(
                      key: const ValueKey('trip-sort-least-walking'),
                      label: Text(l10n.tripSortLeastWalking),
                      selected: _sort == TripPlanSort.leastWalking,
                      onSelected: (_) =>
                          setState(() => _sort = TripPlanSort.leastWalking),
                    ),
                    ChoiceChip(
                      key: const ValueKey('trip-sort-fewest-transfers'),
                      label: Text(l10n.tripSortFewestTransfers),
                      selected: _sort == TripPlanSort.fewestTransfers,
                      onSelected: (_) =>
                          setState(() => _sort = TripPlanSort.fewestTransfers),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final plan in shownPlans)
                        _TripPlanCard(
                          plan: plan,
                          onSelected: widget.onPlanSelected == null
                              ? null
                              : () => widget.onPlanSelected!(
                                  plan,
                                  _originUsesLocation ? null : _origin,
                                  _destination!,
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Text(l10n.tripStaticScheduleNotice, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _PlanErrorCard extends StatelessWidget {
  const _PlanErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('trip-plan-error'),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              Symbols.error_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              key: const ValueKey('trip-plan-retry'),
              onPressed: onRetry,
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanEmptyState extends StatelessWidget {
  const _PlanEmptyState({
    required this.title,
    required this.suggestion,
    required this.expandWalkingLabel,
    required this.changeTimeLabel,
    required this.canExpandWalking,
    required this.onExpandWalking,
    required this.onChangeTime,
  });

  final String title;
  final String suggestion;
  final String expandWalkingLabel;
  final String changeTimeLabel;
  final bool canExpandWalking;
  final VoidCallback onExpandWalking;
  final VoidCallback onChangeTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('trip-empty-state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 6),
        Text(suggestion, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canExpandWalking)
              OutlinedButton.icon(
                key: const ValueKey('trip-empty-expand-walking'),
                onPressed: onExpandWalking,
                icon: const Icon(Symbols.directions_walk_rounded),
                label: Text(expandWalkingLabel),
              ),
            OutlinedButton.icon(
              key: const ValueKey('trip-empty-change-time'),
              onPressed: onChangeTime,
              icon: const Icon(Symbols.schedule_rounded),
              label: Text(changeTimeLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _TripPlanCard extends StatelessWidget {
  const _TripPlanCard({required this.plan, this.onSelected});

  final TripPlan plan;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final transitLegs = plan.legs
        .where((leg) => leg.kind == TripLegKind.transit)
        .toList(growable: false);
    final lines = [for (final leg in transitLegs) _lineLabel(leg)]
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final walkingMinutes = _walkingMinutes(plan);
    final departure = _clock(plan.requestedDeparture);
    final arrival = _clock(plan.arrivalTime);
    final semanticLabel = l10n.tripPlanSemantics(
      departure,
      arrival,
      plan.duration.inMinutes,
      walkingMinutes,
      plan.transferCount,
      lines.isEmpty ? l10n.tripPlanNoLines : lines.join(', '),
    );

    return Semantics(
      container: true,
      button: onSelected != null,
      excludeSemantics: true,
      label: semanticLabel,
      onTap: onSelected,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.tripPlanTimes(departure, arrival),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.tripPlanDuration(plan.duration.inMinutes),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (lines.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final line in lines)
                        LineChip(
                          label: line,
                          backgroundColor: theme.colorScheme.primary,
                          compact: true,
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(Symbols.directions_walk_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(l10n.tripWalkOnly(plan.totalWalkingMeters.round())),
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _PlanFact(
                      icon: Symbols.directions_walk_rounded,
                      label: l10n.tripPlanWalkingMinutes(walkingMinutes),
                    ),
                    _PlanFact(
                      icon: Symbols.sync_alt_rounded,
                      label: l10n.tripPlanTransfers(plan.transferCount),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tripScheduledTimes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _PlanFact extends StatelessWidget {
  const _PlanFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _lineLabel(TripLeg leg) {
  final route = leg.route;
  if (route == null) return '';
  return route.shortName.isNotEmpty ? route.shortName : route.id;
}

int _walkingMinutes(TripPlan plan) {
  var seconds = 0;
  for (final leg in plan.legs) {
    if (leg.kind == TripLegKind.walking) {
      seconds += leg.arrivalTime.difference(leg.departureTime).inSeconds;
    }
  }
  return (seconds / 60).ceil();
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
