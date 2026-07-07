import 'package:flutter/material.dart';

/// Shared neon / cyberpunk palette used across the whole app.
class AppColors {
  static const Color bgDeep = Color(0xFF060912);
  static const Color bgPanel = Color(0xFF0E1526);
  static const Color neonBlue = Color(0xFF29B6FF);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonRed = Color(0xFFFF3B5C);
  static const Color neonPurple = Color(0xFF8A5CFF);
  static const Color gold = Color(0xFFFFCB3B);
  static const Color textDim = Color(0xFF9FB2CC);
}

class AppText {
  static const String fontFallback = 'Roboto';

  static TextStyle title(double size, {Color color = Colors.white}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 1.5,
        height: 1.05,
        shadows: const [
          Shadow(color: AppColors.neonBlue, blurRadius: 18),
          Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
        ],
      );

  static TextStyle label(double size,
          {Color color = Colors.white, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: 0.5,
      );
}
