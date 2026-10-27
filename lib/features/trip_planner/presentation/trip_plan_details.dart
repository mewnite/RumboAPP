import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../domain/trip_planner.dart';

class TripPlanDetails extends StatelessWidget {
  const TripPlanDetails({
    required this.plan,
    required this.originName,
    required this.destinationName,
    required this.onChangeTrip,
    required this.onCloseTrip,
    this.activeTripIsActive = false,
    this.activeTripStopsRemaining,
    this.onStartActiveTrip,
    this.onStopActiveTrip,
    super.key,
  });

  final TripPlan plan;
  final String originName;
  final String destinationName;
  final VoidCallback onChangeTrip;
  final VoidCallback onCloseTrip;
  final bool activeTripIsActive;
  final int? activeTripStopsRemaining;
  final VoidCallback? onStartActiveTrip;
  final VoidCallback? onStopActiveTrip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final steps = _timelineSteps(l10n);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tripDetailTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.tripDetailClose,
              onPressed: onCloseTrip,
              icon: const Icon(Symbols.close_rounded),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                l10n.tripPlanTimes(
                  _clock(plan.requestedDeparture),
                  _clock(plan.arrivalTime),
                ),
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
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _SummaryFact(
              icon: Symbols.directions_walk_rounded,
              label: l10n.tripPlanWalkingMinutes(_walkingMinutes(plan)),
            ),
            _SummaryFact(
              icon: Symbols.sync_alt_rounded,
              label: l10n.tripPlanTransfers(plan.transferCount),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < steps.length; index++)
          _TimelineStepTile(
            step: steps[index],
            isLast: index == steps.length - 1,
            timeLabel: steps[index].estimated
                ? l10n.tripDetailEstimatedTime(_clock(steps[index].time))
                : _clock(steps[index].time),
          ),
        if (plan.totalWalkingMeters > 0) ...[
          const SizedBox(height: 4),
          Text(
            l10n.tripDetailWalkingTotal(plan.totalWalkingMeters.round()),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 8),
        Text(l10n.tripDetailWalkingApproximate, style: secondaryStyle),
        const SizedBox(height: 4),
        Text(l10n.tripDetailScheduleNotice, style: secondaryStyle),
        const SizedBox(height: 12),
        if (activeTripIsActive && activeTripStopsRemaining != null)
          Card(
            child: ListTile(
              leading: const Icon(Symbols.notifications_active_rounded),
              title: Text(l10n.activeTripNotificationTitle),
              subtitle: Text(
                l10n.activeTripStopsRemaining(
                  activeTripStopsRemaining!,
                  destinationName,
                ),
              ),
            ),
          ),
        if (onStartActiveTrip != null || onStopActiveTrip != null)
          FilledButton.icon(
            onPressed: activeTripIsActive
                ? onStopActiveTrip
                : onStartActiveTrip,
            icon: Icon(
              activeTripIsActive
                  ? Symbols.stop_circle_rounded
                  : Symbols.notifications_active_rounded,
            ),
            label: Text(
              activeTripIsActive ? l10n.activeTripFinish : l10n.activeTripStart,
            ),
          ),
        if (onStartActiveTrip != null || onStopActiveTrip != null)
          const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onChangeTrip,
          icon: const Icon(Symbols.edit_road_rounded),
          label: Text(l10n.tripDetailChangeTrip),
        ),
      ],
    );
  }

  List<_TimelineStep> _timelineSteps(AppLocalizations l10n) {
    final steps = <_TimelineStep>[
      _TimelineStep(
        icon: Symbols.trip_origin_rounded,
        title: l10n.tripDetailStart,
        subtitle: originName,
        time: plan.requestedDeparture,
        isOrigin: true,
      ),
    ];

    for (final leg in plan.legs) {
      switch (leg.kind) {
        case TripLegKind.walking:
          steps.add(
            _TimelineStep(
              icon: Symbols.directions_walk_rounded,
              title: l10n.tripDetailWalkStep(leg.distanceMeters.round()),
              subtitle: _walkingSubtitle(l10n, leg),
              time: leg.arrivalTime,
              estimated: true,
            ),
          );
        case TripLegKind.waiting:
          break;
        case TripLegKind.transit:
          steps.add(
            _TimelineStep(
              icon: Symbols.directions_bus_rounded,
              title: l10n.tripDetailBoard(
                _lineLabel(l10n, leg),
                leg.fromStop?.name ?? l10n.tripDetailUnknownStop,
              ),
              subtitle: leg.headsign.trim().isEmpty
                  ? null
                  : l10n.tripDetailToward(leg.headsign.trim()),
              time: leg.departureTime,
              estimated: true,
            ),
          );
          steps.add(
            _TimelineStep(
              icon: Symbols.flag_rounded,
              title: l10n.tripDetailAlight(
                leg.toStop?.name ?? l10n.tripDetailUnknownStop,
              ),
              time: leg.arrivalTime,
              estimated: true,
            ),
          );
      }
    }

    steps.add(
      _TimelineStep(
        icon: Symbols.location_on_rounded,
        title: l10n.tripDetailEnd,
        subtitle: destinationName,
        time: plan.arrivalTime,
        estimated: true,
        isDestination: true,
      ),
    );
    return steps;
  }

  String _walkingSubtitle(AppLocalizations l10n, TripLeg leg) {
    final from =
        leg.fromStop?.name ??
        (leg.fromLatitude != null ? originName : l10n.tripDetailUnknownStop);
    final to =
        leg.toStop?.name ??
        (leg.toLatitude != null ? destinationName : l10n.tripDetailUnknownStop);
    return l10n.tripDetailBetweenStops(from, to);
  }

  String _lineLabel(AppLocalizations l10n, TripLeg leg) {
    final route = leg.route;
    if (route == null) return l10n.tripDetailUnknownStop;
    return route.shortName.isNotEmpty ? route.shortName : route.id;
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.time,
    this.subtitle,
    this.estimated = false,
    this.isOrigin = false,
    this.isDestination = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final DateTime time;
  final bool estimated;
  final bool isOrigin;
  final bool isDestination;
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({
    required this.step,
    required this.isLast,
    required this.timeLabel,
  });

  final _TimelineStep step;
  final bool isLast;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = step.isDestination
        ? theme.colorScheme.primary
        : step.isOrigin
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(step.icon, size: 20, color: markerColor),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (step.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        step.subtitle!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({required this.icon, required this.label});

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
