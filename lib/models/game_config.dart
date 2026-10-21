import '../core/maps/map_models.dart';
import '../core/maps/polygon_service.dart';

enum GameMode { hideAndSeek, infected }

class GameConfig {
  const GameConfig({
    required this.mode,
    required this.matchDurationSeconds,
    required this.hidingDurationSeconds,
    required this.catchRadiusMeters,
    required this.revealIntervalSeconds,
    required this.revealDurationSeconds,
    required this.tauntsEnabled,
    required this.playablePolygon,
    required this.restrictedPolygons,
  });

  /// Blueprint starting values. Hiding/match lengths are not named in the
  /// blueprint; 3-minute hide and 20-minute match fit one 10-minute reveal.
  static const defaultMatchDurationSeconds = 20 * 60;
  static const defaultHidingDurationSeconds = 3 * 60;
  static const defaultCatchRadiusMeters = 20.0;
  static const defaultRevealIntervalSeconds = 10 * 60;
  static const defaultRevealDurationSeconds = 30;
  static const defaultTauntsEnabled = true;

  static const minCatchRadiusMeters = 5.0;
  static const maxCatchRadiusMeters = 100.0;

  final GameMode mode;
  final int matchDurationSeconds;
  final int hidingDurationSeconds;
  final double catchRadiusMeters;
  final int revealIntervalSeconds;
  final int revealDurationSeconds;
  final bool tauntsEnabled;
  final MapPolygon playablePolygon;
  final List<MapPolygon> restrictedPolygons;

  String get modeLabel => modeDisplayName(mode);

  String get modeWireValue => modeToWire(mode);

  String? validateSelf() {
    return validate(
      mode: mode,
      matchDurationSeconds: matchDurationSeconds,
      hidingDurationSeconds: hidingDurationSeconds,
      catchRadiusMeters: catchRadiusMeters,
      revealIntervalSeconds: revealIntervalSeconds,
      revealDurationSeconds: revealDurationSeconds,
      playablePolygon: playablePolygon,
      restrictedPolygons: restrictedPolygons,
    );
  }

  static String modeDisplayName(GameMode mode) {
    return switch (mode) {
      GameMode.hideAndSeek => 'Hide & Seek',
      GameMode.infected => 'Infected',
    };
  }

  static String modeToWire(GameMode mode) {
    return switch (mode) {
      GameMode.hideAndSeek => 'hide_and_seek',
      GameMode.infected => 'infected',
    };
  }

  static GameMode? modeFromWire(String raw) {
    return switch (raw) {
      'hide_and_seek' => GameMode.hideAndSeek,
      'infected' => GameMode.infected,
      _ => null,
    };
  }

  /// Returns a human-readable error, or null when [GameConfig] can be built.
  static String? validate({
    required GameMode mode,
    required int? matchDurationSeconds,
    required int? hidingDurationSeconds,
    required double? catchRadiusMeters,
    required int? revealIntervalSeconds,
    required int? revealDurationSeconds,
    required MapPolygon? playablePolygon,
    required List<MapPolygon> restrictedPolygons,
  }) {
    final settingsError = validateSettings(
      mode: mode,
      matchDurationSeconds: matchDurationSeconds,
      hidingDurationSeconds: hidingDurationSeconds,
      catchRadiusMeters: catchRadiusMeters,
      revealIntervalSeconds: revealIntervalSeconds,
      revealDurationSeconds: revealDurationSeconds,
    );
    if (settingsError != null) {
      return settingsError;
    }

    if (playablePolygon == null) {
      return 'Select a play area before creating a lobby.';
    }

    return PolygonService.validateForConfirm(
      playable: playablePolygon,
      restrictedZones: restrictedPolygons,
    );
  }

  /// The non-zone subset of [validate] — mode/timing/catch-radius checks
  /// shared with the lobby's Edit Settings sheet, which never touches zones.
  static String? validateSettings({
    required GameMode mode,
    required int? matchDurationSeconds,
    required int? hidingDurationSeconds,
    required double? catchRadiusMeters,
    required int? revealIntervalSeconds,
    required int? revealDurationSeconds,
  }) {
    if (!GameMode.values.contains(mode)) {
      return 'Choose Hide & Seek or Infected.';
    }

    final timingError = _positiveTiming(
      matchDurationSeconds,
      'Match duration',
    );
    if (timingError != null) {
      return timingError;
    }

    final hidingError = _positiveTiming(
      hidingDurationSeconds,
      'Hiding duration',
    );
    if (hidingError != null) {
      return hidingError;
    }

    if (catchRadiusMeters == null ||
        catchRadiusMeters.isNaN ||
        catchRadiusMeters.isInfinite) {
      return 'Catch radius must be a number.';
    }
    if (catchRadiusMeters < minCatchRadiusMeters ||
        catchRadiusMeters > maxCatchRadiusMeters) {
      return 'Catch radius must be between '
          '${minCatchRadiusMeters.toStringAsFixed(0)} and '
          '${maxCatchRadiusMeters.toStringAsFixed(0)} meters.';
    }

    final revealIntervalError = _positiveTiming(
      revealIntervalSeconds,
      'Reveal interval',
    );
    if (revealIntervalError != null) {
      return revealIntervalError;
    }

    return _positiveTiming(revealDurationSeconds, 'Reveal duration');
  }

  static String? _positiveTiming(int? seconds, String label) {
    if (seconds == null) {
      return '$label must be a whole number of seconds.';
    }
    if (seconds <= 0) {
      return '$label must be greater than 0 seconds.';
    }
    return null;
  }

  String debugDump() {
    final buffer = StringBuffer()
      ..writeln('GameConfig')
      ..writeln('  mode: $modeLabel')
      ..writeln('  matchDurationSeconds: $matchDurationSeconds')
      ..writeln('  hidingDurationSeconds: $hidingDurationSeconds')
      ..writeln('  catchRadiusMeters: $catchRadiusMeters')
      ..writeln('  revealIntervalSeconds: $revealIntervalSeconds')
      ..writeln('  revealDurationSeconds: $revealDurationSeconds')
      ..writeln('  tauntsEnabled: $tauntsEnabled')
      ..writeln(
        '  playable: ${playablePolygon.id} '
        '(${playablePolygon.vertices.length} vertices)',
      );
    for (var i = 0; i < playablePolygon.vertices.length; i++) {
      buffer.writeln('    ${i + 1}. ${_point(playablePolygon.vertices[i])}');
    }
    buffer.writeln('  restrictedPolygons: ${restrictedPolygons.length}');
    for (var i = 0; i < restrictedPolygons.length; i++) {
      final zone = restrictedPolygons[i];
      buffer.writeln(
        '    ${i + 1}. ${zone.id} (${zone.vertices.length} vertices)',
      );
      for (var v = 0; v < zone.vertices.length; v++) {
        buffer.writeln('      ${v + 1}. ${_point(zone.vertices[v])}');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _point(GeoPoint point) {
    return 'lng ${point.longitude.toStringAsFixed(6)}, '
        'lat ${point.latitude.toStringAsFixed(6)}';
  }
}
