enum LocationErrorKind {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unknown,
}

enum LocationPrecision { precise, approximate, unknown }

class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.precision,
    this.accuracyMeters,
    this.altitudeMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final LocationPrecision precision;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;

  /// Course over ground in degrees (0-360, clockwise from north) — only
  /// meaningful while moving. This is GPS travel direction, not a true
  /// magnetometer compass heading.
  final double? headingDegrees;
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.location);

  final AppLocation location;
}

class LocationError extends LocationResult {
  const LocationError({required this.kind, required this.message});

  final LocationErrorKind kind;
  final String message;
}
