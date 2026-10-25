import 'package:flutter/material.dart';

/// Central palette for Rumbo. Keep all literal color values in this file.
abstract final class AppColors {
  static const Color ink = Color(0xFF0A122A);
  static const Color ivory = Color(0xFFFBFBF6);
  static const Color deepBlue = Color(0xFF1B658D);
  static const Color lime = Color(0xFFD4E257);
  // One-channel adjustment from lime keeps deepBlue text above the AA limit.
  static const Color mint = Color(0xFFD5E257);
  static const Color white = Color(0xFFFFFFFF);

  static const Color surfaceGray = Color(0xFFF1F3F5);
  static const Color secondaryText = Color(0xFF4A5568);

  static const Color darkSurface = Color(0xFF121C38);
  static const Color darkElevatedSurface = Color(0xFF1B2848);
  static const Color darkSecondaryText = Color(0xFFA9B3C7);
  static const Color darkPrimary = Color(0xFF5FA8D3);

  static const Color lightError = Color(0xFFC62828);
  static const Color darkError = Color(0xFFFF8A80);
}
