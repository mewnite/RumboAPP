import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/line_chip.dart';
import '../../stops_and_lines/domain/transit_models.dart';

class LiveBusChip extends StatelessWidget {
  const LiveBusChip({
    required this.bus,
    required this.matchedVariantIds,
    this.now,
    super.key,
  });

  final BusPosition bus;
  final Set<int> matchedVariantIds;
  final DateTime? now;

  bool get isStale {
    final age = (now ?? DateTime.now()).difference(bus.receivedAt);
    return age > const Duration(seconds: 60);
  }

  bool get isMatched => matchedVariantIds.contains(bus.variantId);

  @override
  Widget build(BuildContext context) {
    final color = isMatched
        ? AppColors.deepBlue
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Opacity(
      opacity: isStale || !isMatched ? 0.5 : 1,
      child: LineChip(
        label: bus.lineLabel,
        backgroundColor: color,
        compact: true,
      ),
    );
  }
}
