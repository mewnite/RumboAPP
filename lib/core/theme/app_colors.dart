import 'package:flutter/material.dart';

/// Central design tokens for Rumbo. Keep literal colors and shared scales here.
abstract final class AppColors {
  static const Color ink = Color(0xFF0A122A);
  static const Color ivory = Color(0xFFFBFBF6);
  static const Color rumbo = Color(0xFF1B658D);
  static const Color lime = Color(0xFFD4E257);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFF4A5568);
  static const Color lightError = Color(0xFFC62828);

  static const Color darkSurface = Color(0xFF121C38);
  static const Color darkElevatedSurface = Color(0xFF1B2848);
  static const Color darkSecondaryText = Color(0xFFA9B3C7);
  static const Color darkPrimary = Color(0xFF5FA8D3);
  static const Color darkError = Color(0xFFFF8A80);

  static const Color transparent = Color(0x00000000);
  static const Color lightBorder = Color(0x140A122A);
  static const Color darkBorder = Color(0x33FBFBF6);
}

abstract final class AppTokens {
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;

  static const double radius8 = 8;
  static const double radius12 = 12;
  static const double radius16 = 16;
  static const double radius24 = 24;
  static const double primaryButtonRadius = 14;
  static const double minimumTapTarget = 48;

  static const Size sheetHandle = Size(36, 4);
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationStandard = Duration(milliseconds: 200);
  static const Duration animationSlow = Duration(milliseconds: 250);

  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x140A122A), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
