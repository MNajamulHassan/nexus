import 'package:geolocator/geolocator.dart';

class LocationPermissions {
  const LocationPermissions();

  Future<bool> isServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> check() {
    return Geolocator.checkPermission();
  }

  Future<LocationPermission> request() {
    return Geolocator.requestPermission();
  }

  Future<LocationAccuracyStatus> accuracyStatus() {
    return Geolocator.getLocationAccuracy();
  }

  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }

  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }
}
