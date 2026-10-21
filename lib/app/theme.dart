import 'package:flutter/material.dart';

abstract final class NexusTheme {
  /// The single source of truth for the app's display name — never
  /// hardcode "MANHUNT" directly in a widget.
  static const appName = 'MANHUNT';

  static const background = Color(0xFF07131F);
  static const surface = Color(0xFF0B2030);
  static const surfaceRaised = Color(0xFF142C40);
  static const hairline = Color(0xFF1E3A52);
  static const accent = Color(0xFF22E4FF);
  static const onAccent = Color(0xFF041018);
  static const textPrimary = Color(0xFFE6F1FF);
  static const dimText = Color(0xFF7C93AD);

  /// One hostile color, one safe color, one caution color, one restricted-
  /// zone color — used everywhere instead of ad hoc `Colors.redAccent`/
  /// `greenAccent`/`amberAccent` literals, so each meaning always maps to
  /// the same hue across every screen.
  static const danger = Color(0xFFFF3B4E);
  static const restricted = Color(0xFF2F6BFF);
  static const success = Color(0xFF00E676);
  static const warning = Color(0xFFFFC247);

  /// Glass-card surface — the translucent dark panel used for HUD
  /// overlays sitting on top of a map.
  static final glassSurface = surface.withValues(alpha: 0.9);

  static const cardRadius = 14.0;
  static const spacingSm = 8.0;
  static const spacingMd = 16.0;
  static const spacingLg = 24.0;

  /// Rajdhani: wordmark, headings, labels, buttons, timers — anything
  /// that reads as an instrument-panel readout or a short, wide-tracked
  /// label. Exo 2: body copy and anything meant to read as prose.
  static const fontDisplay = 'Rajdhani';
  static const fontBody = 'Exo 2';

  /// Tabular figures for GPS/HUD readouts (timers, distances, join codes) —
  /// this app is a live instrument panel, so fixed-width digits are
  /// functional here, not decorative.
  static const readout = TextStyle(
    fontFamily: fontDisplay,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.5,
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      surface: surface,
      onSurface: textPrimary,
      error: danger,
    );

    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: fontBody,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: textPrimary,
        ),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
        ),
        headlineSmall: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelLarge: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: dimText,
        ),
        labelSmall: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: dimText,
        ),
        bodyLarge: TextStyle(fontFamily: fontBody, color: textPrimary),
        bodyMedium: TextStyle(fontFamily: fontBody, color: textPrimary),
        bodySmall: TextStyle(fontFamily: fontBody, color: dimText),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: dimText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: accent,
          side: const BorderSide(color: accent),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
          side: BorderSide(color: hairline),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: TextStyle(fontFamily: fontBody, color: textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
          side: BorderSide(color: hairline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: const TextStyle(
          fontFamily: fontBody,
          color: textPrimary,
        ),
        shape: shape.copyWith(side: const BorderSide(color: hairline)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : dimText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.4)
              : hairline,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.2),
        side: const BorderSide(color: hairline),
        labelStyle: const TextStyle(fontFamily: fontBody, color: textPrimary),
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: dimText,
          selectedBackgroundColor: accent.withValues(alpha: 0.18),
          selectedForegroundColor: accent,
          side: const BorderSide(color: hairline),
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : dimText,
        ),
      ),
    );
  }
}
