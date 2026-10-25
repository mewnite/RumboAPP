import 'package:flutter/material.dart';

double contrastRatio(Color first, Color second) {
  final luminances = [first.computeLuminance(), second.computeLuminance()]
    ..sort();
  final darker = luminances.first;
  final lighter = luminances.last;
  return (lighter + 0.05) / (darker + 0.05);
}
