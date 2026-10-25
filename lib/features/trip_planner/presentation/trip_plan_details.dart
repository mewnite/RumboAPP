import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/trip_planner.dart';

class TripPlanDetails extends StatelessWidget {
  const TripPlanDetails({
    required this.plan,
    required this.originName,
    required this.destinationName,
    required this.onChangeTrip,
    required this.onCloseTrip,
    super.key,
  });

  final TripPlan plan;
  final String originName;
  final String destinationName;
  final VoidCallback onChangeTrip;
  final VoidCallback onCloseTrip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final legs = plan.legs;

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
        Text(
          l10n.tripPlanSummary(
            plan.duration.inMinutes,
            plan.transferCount,
            _clock(plan.arrivalTime),
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _TripEndpointTile(
          icon: Symbols.trip_origin_rounded,
          title: l10n.tripDetailDeparture(
            originName,
            _clock(plan.requestedDeparture),
          ),
        ),
        for (var index = 0; index < legs.length; index++)
          _legTile(
            context,
            l10n,
            legs[index],
            index == 0 ? null : legs[index - 1],
            originName,
            destinationName,
          ),
        _TripEndpointTile(
          icon: Symbols.location_on_rounded,
          title: l10n.tripDetailArrival(
            destinationName,
            _clock(plan.arrivalTime),
          ),
          isDestination: true,
        ),
        if (plan.totalWalkingMeters > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              l10n.tripDetailWalkingTotal(plan.totalWalkingMeters.round()),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          l10n.tripDetailScheduleNotice,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onChangeTrip,
          icon: const Icon(Symbols.edit_road_rounded),
          label: Text(l10n.tripDetailChangeTrip),
        ),
      ],
    );
  }

  Widget _legTile(
    BuildContext context,
    AppLocalizations l10n,
    TripLeg leg,
    TripLeg? previousLeg,
    String originName,
    String destinationName,
  ) {
    final theme = Theme.of(context);
    final minutes = leg.arrivalTime.difference(leg.departureTime).inMinutes;
    final stopName =
        leg.toStop?.name ?? leg.fromStop?.name ?? l10n.tripDetailUnknownStop;

    switch (leg.kind) {
      case TripLegKind.walking:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Symbols.directions_walk_rounded),
          title: Text(
            l10n.tripDetailWalking(leg.distanceMeters.round(), minutes),
          ),
          subtitle: Text(
            l10n.tripDetailBetweenStops(
              leg.fromStop?.name ??
                  (leg.fromLatitude != null
                      ? originName
                      : l10n.tripDetailUnknownStop),
              leg.toStop?.name ??
                  (leg.toLatitude != null
                      ? destinationName
                      : l10n.tripDetailUnknownStop),
            ),
          ),
        );
      case TripLegKind.waiting:
        final isTransfer = previousLeg?.kind == TripLegKind.transit;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isTransfer ? Symbols.sync_alt_rounded : Symbols.schedule_rounded,
          ),
          title: Text(
            isTransfer
                ? l10n.tripDetailTransfer(stopName, minutes)
                : l10n.tripDetailWait(stopName, minutes),
          ),
          subtitle: Text(
            '${_clock(leg.departureTime)} – ${_clock(leg.arrivalTime)}',
          ),
        );
      case TripLegKind.transit:
        final line = leg.route?.shortName ?? l10n.tripDetailUnknownStop;
        final direction = leg.headsign.trim();
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.deepBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                line,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          title: Text(
            direction.isEmpty
                ? l10n.tripDetailBus(line)
                : l10n.tripDetailBusDirection(line, direction),
          ),
          subtitle: Text(
            l10n.tripDetailBetweenStops(
              leg.fromStop?.name ?? l10n.tripDetailUnknownStop,
              leg.toStop?.name ?? l10n.tripDetailUnknownStop,
            ),
          ),
          trailing: Text(
            '${_clock(leg.departureTime)}\n${_clock(leg.arrivalTime)}',
            textAlign: TextAlign.end,
          ),
        );
    }
  }
}

class _TripEndpointTile extends StatelessWidget {
  const _TripEndpointTile({
    required this.icon,
    required this.title,
    this.isDestination = false,
  });

  final IconData icon;
  final String title;
  final bool isDestination;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: isDestination ? AppColors.deepBlue : null),
    title: Text(title),
  );
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
