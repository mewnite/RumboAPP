import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import 'line_chip.dart';

class FloatingSearchBar extends StatelessWidget {
  const FloatingSearchBar({
    required this.label,
    required this.onTap,
    this.keyValue,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? keyValue;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    excludeSemantics: true,
    onTap: onTap,
    label: label,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shadowColor: AppColors.ink.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppTokens.radius16),
      child: InkWell(
        key: keyValue == null ? null : ValueKey(keyValue),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radius16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
            child: Row(
              children: [
                Icon(
                  Symbols.search_rounded,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

class ArrivalRow extends StatelessWidget {
  const ArrivalRow({
    required this.lineLabel,
    required this.lineColor,
    required this.destination,
    required this.arrivalLabel,
    this.onTap,
    super.key,
  });

  final String lineLabel;
  final Color lineColor;
  final String destination;
  final String arrivalLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    excludeSemantics: true,
    label: '$lineLabel, $destination, $arrivalLabel',
    onTap: onTap,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
            child: Row(
              children: [
                LineChip(label: lineLabel, backgroundColor: lineColor),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: Text(
                    destination,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppTokens.space8),
                Text(
                  arrivalLabel,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ItinerarySummaryCard extends StatelessWidget {
  const ItinerarySummaryCard({
    required this.lines,
    required this.durationLabel,
    required this.walkingLabel,
    required this.transfersLabel,
    this.onTap,
    this.semanticsLabel,
    this.headingLabel,
    this.footerLabel,
    this.emptyLinesLabel,
    super.key,
  });

  final List<LineChip> lines;
  final String durationLabel;
  final String walkingLabel;
  final String transfersLabel;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final String? headingLabel;
  final String? footerLabel;
  final String? emptyLinesLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    excludeSemantics: true,
    onTap: onTap,
    label: semanticsLabel ?? '$durationLabel. $walkingLabel. $transfersLabel',
    child: Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radius16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (headingLabel != null) ...[
                Text(
                  headingLabel!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.space8),
              ],
              Row(
                children: [
                  Expanded(
                    child: lines.isNotEmpty
                        ? Wrap(
                            spacing: AppTokens.space8,
                            runSpacing: AppTokens.space8,
                            children: lines,
                          )
                        : Text(
                            emptyLinesLabel ?? '',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                  ),
                  const SizedBox(width: AppTokens.space12),
                  Text(
                    durationLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space12),
              Text(
                '$walkingLabel  ·  $transfersLabel',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (footerLabel != null) ...[
                const SizedBox(height: AppTokens.space8),
                Text(
                  footerLabel!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class RumboSheetHandle extends StatelessWidget {
  const RumboSheetHandle({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Center(
        child: Container(
          width: AppTokens.sheetHandle.width,
          height: AppTokens.sheetHandle.height,
          margin: const EdgeInsets.symmetric(vertical: AppTokens.space12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: .45),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    ),
  );
}

class TripEndpointRail extends StatelessWidget {
  const TripEndpointRail({this.height = 124, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final circleInset = height * .16;
    final lineInset = height * .24;
    final lineHeight = height - (lineInset * 2);
    return ExcludeSemantics(
      child: SizedBox(
        width: 24,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: lineInset,
              bottom: lineInset,
              child: CustomPaint(
                size: Size(2, lineHeight),
                painter: _DottedLinePainter(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            Positioned(
              top: circleInset,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: primary, width: 2),
                ),
              ),
            ),
            Positioned(
              bottom: circleInset,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                  border: Border.all(color: primary, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width
      ..strokeCap = StrokeCap.round;
    for (var y = 0.0; y <= size.height; y += 6) {
      canvas.drawCircle(Offset(size.width / 2, y), size.width / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: icon!,
            label: Text(label),
          ),
  );
}

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppTokens.minimumTapTarget,
    child: icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon!,
            label: Text(label),
          ),
  );
}

class StopMapMarker extends StatelessWidget {
  const StopMapMarker({required this.label, this.selected = false, super.key});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Parada $label${selected ? ', seleccionada' : ''}',
    child: ExcludeSemantics(
      child: Container(
        width: selected ? 32 : 24,
        height: selected ? 32 : 24,
        decoration: BoxDecoration(
          color: AppColors.rumbo,
          borderRadius: BorderRadius.circular(AppTokens.radius8),
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: selected ? AppTokens.softShadow : null,
        ),
        child: Icon(
          Symbols.directions_bus_rounded,
          size: selected ? 20 : 16,
          color: AppColors.surface,
        ),
      ),
    ),
  );
}

class BusMapMarker extends StatelessWidget {
  const BusMapMarker({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.lime,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
        ),
        child: const SizedBox(
          width: AppTokens.minimumTapTarget,
          height: AppTokens.minimumTapTarget,
          child: Icon(
            Symbols.directions_bus_rounded,
            color: AppColors.ink,
            size: 24,
          ),
        ),
      ),
    ),
  );
}

class TripProgressCard extends StatelessWidget {
  const TripProgressCard({
    required this.title,
    required this.subtitle,
    this.progress,
    super.key,
  });

  final String title;
  final String subtitle;
  final double? progress;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: '$title. $subtitle',
    value: progress == null ? null : '${(progress! * 100).round()}%',
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.space4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: AppTokens.space12),
              LinearProgressIndicator(value: progress!.clamp(0, 1)),
            ],
          ],
        ),
      ),
    ),
  );
}
