import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/contrast.dart';

class LineChip extends StatelessWidget {
  const LineChip({
    required this.label,
    required this.backgroundColor,
    this.compact = false,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final bool compact;

  Color get foregroundColor {
    final options = [AppColors.surface, AppColors.rumbo, AppColors.ink];
    return options.reduce(
      (best, candidate) =>
          contrastRatio(candidate, backgroundColor) >
              contrastRatio(best, backgroundColor)
          ? candidate
          : best,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 7,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
