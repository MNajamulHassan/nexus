import 'dart:math';

/// Great-circle distance between two coordinates, in meters.
double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_radians(lat1)) *
          cos(_radians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _radians(double degrees) => degrees * pi / 180;
