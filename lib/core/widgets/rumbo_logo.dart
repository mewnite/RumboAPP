import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Temporary route symbol. Replace its contents with the approved Rumbo SVG.
class RumboLogo extends StatelessWidget {
  const RumboLogo({this.semanticLabel, this.size = 64, super.key});

  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        alignment: Alignment.center,
        child: Icon(
          Symbols.alt_route_rounded,
          size: size * 0.62,
          color: colorScheme.primary,
          fill: 1,
        ),
      ),
    );
  }
}
