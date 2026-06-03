import 'package:flutter/material.dart';

class AppDesign {
  AppDesign._();

  static const Color ink = Color(0xFF2F3437);
  static const Color mutedInk = Color(0xFF6B6F76);
  static const Color canvas = Color(0xFFF7F6F3);
  static const Color paper = Color(0xFFFFFEFC);
  static const Color paperSoft = Color(0xFFF1F1EF);
  static const Color line = Color(0xFFE6E4DF);
  static const Color brand = Color(0xFF2F6F68);
  static const Color brandSoft = Color(0xFFE5F0EE);
  static const Color accent = Color(0xFF8A5A44);

  static const Color darkCanvas = Color(0xFF191919);
  static const Color darkPaper = Color(0xFF202020);
  static const Color darkPaperSoft = Color(0xFF2A2A2A);
  static const Color darkLine = Color(0xFF373737);
  static const Color darkInk = Color(0xFFEDEDEB);
  static const Color darkMutedInk = Color(0xFFB4B0A8);

  static const double radiusXs = 4;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 18,
  );

  static BorderSide hairline(Color color, {double alpha = 1}) {
    return BorderSide(color: color.withValues(alpha: alpha), width: 1);
  }
}
