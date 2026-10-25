import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/search/domain/place_search_service.dart';
import '../../../features/stops_and_lines/domain/transit_models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/trip_planner.dart';

typedef StopSearch = Future<List<Stop>> Function(String query);
typedef PlaceSearch = Future<List<TripEndpoint>> Function(String query);
typedef PlanSearch = Future<List<TripPlan>> Function(
  TripEndpoint? origin,
  TripEndpoint destination,
  DateTime departureTime,
);
typedef TripPlanSelected = void Function(
  TripPlan plan,
  TripEndpoint? origin,
  TripEndpoint destination,
);
typedef DepartureDatePicker = Future<DateTime?> Function(
  BuildContext context,
  DateTime initialDate,
  DateTime firstDate,
  DateTime lastDate,
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
    this.searchService,
    this.initialDestination,
    this.onPlanSelected,
    this.departureDatePicker,
    this.departureTimePicker,
    super.key,
  });

  final StopSearch searchStops;
  final PlaceSearch searchPlaces;
  final PlanSearch findPlans;
  final bool hasCurrentLocation;
  final bool remotePlaceSearchEnabled;
  final PlaceSearchService? searchService;
  final TripEndpoint? initialDestination;
  final TripPlanSelected? onPlanSelected;
  final DepartureDatePicker? departureDatePicker;
  final DepartureTimePicker? departureTimePicker;

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
  bool _hasSearchedPlaces = false;
  DateTime _departureTime = DateTime.now();
  bool _departureCustomized = false;

  TextEditingController get _activeController =>
      _searchOrigin ? _originController : _destinationController;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _suggestions = const [];
      _searchError = null;
      _searching = query.trim().isNotEmpty;
      _hasSearchedPlaces = false;
    });
    if (query.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        if (widget.searchService != null) {
          final results = await widget.searchService!.searchLocal(query: query);
          if (mounted && _activeController.text == query) {
            setState(() {
              _suggestions = results.map((r) => r.toTripEndpoint()).toList();
              _searching = false;
            });
          }
        } else {
          final results = await widget.searchStops(query);
          if (mounted && _activeController.text == query) {
            setState(() {
              _suggestions = results.map(TripEndpoint.fromStop).toList();
              _searching = false;
            });
          }
        }
      } on Exception catch (error) {
        if (mounted && _activeController.text == query) {
          setState(() {
            _searchError = error;
            _searching = false;
          });
        }
      }
    });
  }

  Future<void> _searchPlaces() async {
    if (!widget.remotePlaceSearchEnabled) return;
    final query = _activeController.text.trim();
    if (query.length < 3) return;
    _debounce?.cancel();
    setState(() {
      _searching = true;
      _searchError = null;
      _hasSearchedPlaces = false;
    });
    try {
      final results = widget.searchService != null
          ? (await widget.searchService!.search(
              query: query,
              allowRemote: true,
            )).map((r) => r.toTripEndpoint()).toList()
          : await widget.searchPlaces(query);
      if (!mounted || _activeController.text.trim() != query) return;
      final seen = _suggestions.map(_endpointKey).toSet();
      setState(() {
        _suggestions = [
          ..._suggestions,
          ...results.where((result) => seen.add(_endpointKey(result))),
        ];
        _searching = false;
        _hasSearchedPlaces = true;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _searchError = error;
          _searching = false;
        });
      }
    }
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

  Future<void> _pickDepartureDate() async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = firstDate.add(const Duration(days: 60));
    var initialDate = DateTime(
      _departureTime.year,
      _departureTime.month,
      _departureTime.day,
    );
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final selected =
        await (widget.departureDatePicker?.call(
              context,
              initialDate,
              firstDate,
              lastDate,
            ) ??
            showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              helpText: l10n.tripDepartureLabel,
            ));
    if (!mounted || selected == null) return;
    setState(() {
      _departureTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _departureTime.hour,
        _departureTime.minute,
      );
      _departureCustomized = true;
      _plans = null;
      _planError = null;
    });
  }

  Future<void> _pickDepartureTime() async {
    final l10n = AppLocalizations.of(context);
    final selected =
        await (widget.departureTimePicker?.call(
              context,
              TimeOfDay.fromDateTime(_departureTime),
            ) ??
            showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_departureTime),
              helpText: l10n.tripDepartureLabel,
            ));
    if (!mounted || selected == null) return;
    setState(() {
      _departureTime = DateTime(
        _departureTime.year,
        _departureTime.month,
        _departureTime.day,
        selected.hour,
        selected.minute,
      );
      _departureCustomized = true;
      _plans = null;
      _planError = null;
    });
  }

  String _departureDateText(BuildContext context) =>
      MaterialLocalizations.of(context).formatMediumDate(_departureTime);

  String _departureTimeText(BuildContext context) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(_departureTime),
        alwaysUse24HourFormat: true,
      );

  Future<void> _findPlans() async {
    final destination = _destination;
    if (destination == null ||
        (!_originUsesLocation && _origin == null) ||
        (_originUsesLocation && !widget.hasCurrentLocation)) {
      return;
    }
    final departureTime = _departureCustomized
        ? _departureTime
        : DateTime.now();
    setState(() {
      _departureTime = departureTime;
      _planning = true;
      _planError = null;
      _plans = null;
    });
    try {
      final plans = await widget.findPlans(
        _originUsesLocation ? null : _origin,
        destination,
        departureTime,
      );
      if (mounted) setState(() => _plans = plans);
    } on Exception catch (error) {
      if (mounted) setState(() => _planError = error);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
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
                  _hasSearchedPlaces ? l10n.tripNoPlaces : l10n.tripNoStops,
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
            if (widget.remotePlaceSearchEnabled &&
                _activeController.text.trim().length >= 3 &&
                (_originFocus.hasFocus || _destinationFocus.hasFocus)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _searching ? null : _searchPlaces,
                icon: const Icon(Symbols.travel_explore_rounded),
                label: Text(l10n.tripSearchPlaces),
              ),
              Text(
                l10n.tripGeocodingPrivacy,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.tripDepartureLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: l10n.tripChangeDate,
                    child: OutlinedButton.icon(
                      key: const ValueKey('trip-departure-date'),
                      onPressed: _planning ? null : _pickDepartureDate,
                      icon: const Icon(Symbols.calendar_month_rounded),
                      label: Text(
                        _departureDateText(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
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
                child: Text(
                  l10n.tripPlanError(_planError.toString()),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_plans != null) ...[
              const SizedBox(height: 12),
              if (_plans!.isEmpty)
                Text(l10n.tripNoTrips)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final plan in _plans!)
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
            const SizedBox(height: 8),
            Text(l10n.tripStaticScheduleNotice, textAlign: TextAlign.center),
          ],
        ),
      ),
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
    final transitLegs = plan.legs
        .where((leg) => leg.kind == TripLegKind.transit)
        .toList(growable: false);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tripPlanSummary(
                  plan.duration.inMinutes,
                  plan.transferCount,
                  _clock(plan.arrivalTime),
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final leg in transitLegs)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.deepBlue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            leg.route?.shortName ?? '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${leg.fromStop?.name ?? ''} → ${leg.toStop?.name ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_clock(leg.departureTime)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
