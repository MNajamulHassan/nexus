import 'package:flutter/material.dart';

abstract final class NexusTheme {
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF121A2A);
  static const surfaceRaised = Color(0xFF1A2438);
  static const hairline = Color(0xFF263252);
  static const accent = Color(0xFF00E5FF);
  static const onAccent = Color(0xFF041018);

  /// One hostile color, one safe color, one caution color — used everywhere
  /// instead of ad hoc `Colors.redAccent`/`greenAccent`/`amberAccent`
  /// literals, so "danger" always means the same hue across every screen.
  static const danger = Color(0xFFFF3B5C);
  static const success = Color(0xFF00E676);
  static const warning = Color(0xFFFFC247);

  /// Tabular figures for GPS/HUD readouts (timers, distances, join codes) —
  /// this app is a live instrument panel, so fixed-width digits are
  /// functional here, not decorative.
  static const readout = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.5,
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      surface: surface,
      onSurface: Color(0xFFE8EEF7),
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Color(0xFFE8EEF7),
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 6),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: accent,
          side: const BorderSide(color: accent),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
