import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_models.dart';
import 'location_permissions.dart';

class LocationService {
  const LocationService({
    this.permissions = const LocationPermissions(),
  });

  final LocationPermissions permissions;

  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 20),
  );

  Future<LocationResult> getCurrentLocation() async {
    try {
      final serviceEnabled = await permissions.isServiceEnabled();
      if (!serviceEnabled) {
        return const LocationError(
          kind: LocationErrorKind.servicesDisabled,
          message:
              'Location services are turned off. Enable GPS in system settings, then try again.',
        );
      }

      var permission = await permissions.check();
      if (permission == LocationPermission.denied) {
        permission = await permissions.request();
      }

      if (permission == LocationPermission.denied) {
        return const LocationError(
          kind: LocationErrorKind.permissionDenied,
          message:
              'Location permission was denied. Nexus needs location while the app is open to read your GPS position.',
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationError(
          kind: LocationErrorKind.permissionDeniedForever,
          message:
              'Location permission is permanently denied. Open app settings and allow location access, then try again.',
        );
      }

      if (permission == LocationPermission.unableToDetermine) {
        return const LocationError(
          kind: LocationErrorKind.unknown,
          message: 'Could not determine location permission status.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      );
      final precision = await _readPrecision();

      return LocationFix(_toAppLocation(position, precision));
    } on LocationServiceDisabledException {
      return const LocationError(
        kind: LocationErrorKind.servicesDisabled,
        message:
            'Location services are turned off. Enable GPS in system settings, then try again.',
      );
    } on PermissionDeniedException {
      return const LocationError(
        kind: LocationErrorKind.permissionDenied,
        message:
            'Location permission was denied. Nexus needs location while the app is open to read your GPS position.',
      );
    } on TimeoutException {
      return const LocationError(
        kind: LocationErrorKind.timeout,
        message:
            'Timed out waiting for a GPS fix. Move outdoors or wait for a clearer signal, then refresh.',
      );
    } on PermissionRequestInProgressException {
      return const LocationError(
        kind: LocationErrorKind.unknown,
        message: 'A location permission request is already in progress.',
      );
    } on PermissionDefinitionsNotFoundException {
      return const LocationError(
        kind: LocationErrorKind.unknown,
        message:
            'Android location permissions are missing from the app manifest.',
      );
    } catch (error) {
      return LocationError(
        kind: LocationErrorKind.unknown,
        message: 'Could not read location: $error',
      );
    }
  }

  /// Continuous position updates for an active match. Yields at most one
  /// [LocationError] (permission/service problems) then completes, or an
  /// unbounded stream of fixes as the device moves at least 3 meters.
  Stream<LocationResult> watchPosition() async* {
    final serviceEnabled = await permissions.isServiceEnabled();
    if (!serviceEnabled) {
      yield const LocationError(
        kind: LocationErrorKind.servicesDisabled,
        message:
            'Location services are turned off. Enable GPS in system settings, then try again.',
      );
      return;
    }

    var permission = await permissions.check();
    if (permission == LocationPermission.denied) {
      permission = await permissions.request();
    }

    if (permission == LocationPermission.denied) {
      yield const LocationError(
        kind: LocationErrorKind.permissionDenied,
        message:
            'Location permission was denied. Nexus needs location while the app is open to read your GPS position.',
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      yield const LocationError(
        kind: LocationErrorKind.permissionDeniedForever,
        message:
            'Location permission is permanently denied. Open app settings and allow location access, then try again.',
      );
      return;
    }

    final precision = await _readPrecision();

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).map((position) => LocationFix(_toAppLocation(position, precision)));
  }

  Future<bool> openAppSettings() => permissions.openAppSettings();

  Future<bool> openLocationSettings() => permissions.openLocationSettings();

  Future<LocationPrecision> _readPrecision() async {
    try {
      final status = await permissions.accuracyStatus();
      return switch (status) {
        LocationAccuracyStatus.precise => LocationPrecision.precise,
        LocationAccuracyStatus.reduced => LocationPrecision.approximate,
        LocationAccuracyStatus.unknown => LocationPrecision.unknown,
      };
    } catch (_) {
      return LocationPrecision.unknown;
    }
  }

  AppLocation _toAppLocation(Position position, LocationPrecision precision) {
    return AppLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp.toLocal(),
      precision: precision,
      accuracyMeters: position.hasAccuracy ? position.accuracy : null,
      altitudeMeters: position.hasAltitude ? position.altitude : null,
      speedMetersPerSecond: position.hasSpeed ? position.speed : null,
      headingDegrees: position.hasHeading ? position.heading : null,
    );
  }
}
