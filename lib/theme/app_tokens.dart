import 'package:flutter/material.dart';

/// Дизайн-токены приложения.
///
/// Тёплый фон, графит, медь. Все экраны используют эти значения, чтобы
/// «премиальный» стиль не расползался на случайные цвета.
class AppTokens {
  AppTokens._();

  static const Color ink = Color(0xFF18222D);
  static const Color inkSoft = Color(0xFF3A4652);
  static const Color muted = Color(0xFF6F746F);
  static const Color faint = Color(0xFF8A938D);
  static const Color copper = Color(0xFFB86B3D);
  static const Color copperDark = Color(0xFF8E4E2A);
  static const Color copperSoft = Color(0xFFF2E2D5);
  static const Color cream = Color(0xFFF4EFE7);
  static const Color creamDeep = Color(0xFFEDE4D7);
  static const Color paper = Color(0xFFFFFCF8);
  static const Color white = Colors.white;
  static const Color line = Color(0xFFE3D9CC);
  static const Color lineSoft = Color(0xFFEFE8DE);
  static const Color green = Color(0xFF2E7D5B);
  static const Color greenSoft = Color(0xFFE2F0E9);
  static const Color red = Color(0xFFB03A3A);
  static const Color redSoft = Color(0xFFF7E4E2);
  static const Color amber = Color(0xFFB7791F);
  static const Color amberSoft = Color(0xFFF8EED9);
  static const Color blue = Color(0xFF3F6488);
  static const Color blueSoft = Color(0xFFE4EDF5);
  static const Color graphiteSoft = Color(0xFFE9ECEF);

  static const double gapXs = 4;
  static const double gapS = 8;
  static const double gapM = 14;
  static const double gapL = 20;
  static const double gapXl = 28;
  static const double gapXxl = 40;

  static const double radiusS = 10;
  static const double radiusM = 14;
  static const double radiusL = 20;
  static const double radiusXl = 26;

  static const double pageMaxWidth = 1600;

  static const List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: Color(0x0A18222D),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> shadowLift = [
    BoxShadow(
      color: Color(0x1A18222D),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  static const LinearGradient copperGradient = LinearGradient(
    colors: [Color(0xFFC57A4A), Color(0xFF9E562E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient paperGradient = LinearGradient(
    colors: [Color(0xFFFFFCF8), Color(0xFFF8F2E9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
