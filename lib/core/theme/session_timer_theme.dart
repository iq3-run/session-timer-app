import 'package:flutter/material.dart';

/// Color palette carried over from the HTML prototype (docs/prototype-reference.html)
/// so the native app keeps the same OLED-black, low-repaint visual language.
abstract final class SessionTimerColors {
  static const background = Color(0xFF000000);
  static const panel = Color(0xFF0B0D0C);
  static const line = Color(0xFF1C211F);
  static const amber = Color(0xFFFFB000);
  static const cyan = Color(0xFF4FD1C5);
  static const white = Color(0xFFE9EDE9);
  static const red = Color(0xFFFF3B30);
  static const muted = Color(0xFF7C8580);
}

abstract final class SessionTimerTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SessionTimerColors.background,
      colorScheme: const ColorScheme.dark(
        surface: SessionTimerColors.background,
        primary: SessionTimerColors.amber,
        secondary: SessionTimerColors.cyan,
        error: SessionTimerColors.red,
        onSurface: SessionTimerColors.white,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: SessionTimerColors.white),
      ),
    );
  }
}
