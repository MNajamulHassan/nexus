import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_models.dart';

abstract final class PolygonService {
  static const minVertices = 3;

  static bool canComplete(List<GeoPoint> vertices) {
    return vertices.length >= minVertices;
  }

  static List<GeoPoint> closedRing(List<GeoPoint> vertices) {
    if (vertices.isEmpty) {
      return const [];
    }
    final first = vertices.first;
    final last = vertices.last;
    if (first.longitude == last.longitude && first.latitude == last.latitude) {
      return List<GeoPoint>.from(vertices);
    }
    return [...vertices, first];
  }

  static Position toPosition(GeoPoint point) {
    return Position(point.longitude, point.latitude);
  }

  static Point toPoint(GeoPoint point) {
    return Point(coordinates: toPosition(point));
  }

  static LineString? toLineString(List<GeoPoint> vertices) {
    if (vertices.length < 2) {
      return null;
    }
    return LineString(
      coordinates: [for (final vertex in vertices) toPosition(vertex)],
    );
  }

  static Polygon? toPolygon(List<GeoPoint> vertices) {
    if (!canComplete(vertices)) {
      return null;
    }
    return Polygon(
      coordinates: [
        [for (final vertex in closedRing(vertices)) toPosition(vertex)],
      ],
    );
  }

  /// Returns a human-readable error, or null when the draft can be confirmed.
  static String? validateForConfirm({
    required MapPolygon? playable,
    required List<MapPolygon> restrictedZones,
  }) {
    if (playable == null || !canComplete(playable.vertices)) {
      return 'Confirm Area needs a playable polygon with at least $minVertices points.';
    }

    if (_hasDuplicateConsecutive(playable.vertices)) {
      return 'Playable area has duplicate consecutive points.';
    }

    final playablePolygon = toPolygon(playable.vertices);
    if (playablePolygon == null) {
      return 'Playable area geometry is invalid.';
    }

    for (var index = 0; index < restrictedZones.length; index++) {
      final zone = restrictedZones[index];
      if (!canComplete(zone.vertices)) {
        return 'Restricted zone ${index + 1} needs at least $minVertices points.';
      }
      if (_hasDuplicateConsecutive(zone.vertices)) {
        return 'Restricted zone ${index + 1} has duplicate consecutive points.';
      }

      final restrictedPolygon = toPolygon(zone.vertices);
      if (restrictedPolygon == null) {
        return 'Restricted zone ${index + 1} has invalid geometry.';
      }

      try {
        if (!booleanContains(playablePolygon, restrictedPolygon)) {
          return 'Restricted zone ${index + 1} must sit inside the playable area.';
        }
      } catch (_) {
        return 'Could not validate that restricted zone ${index + 1} is inside the playable area.';
      }
    }

    return null;
  }

  static bool _hasDuplicateConsecutive(List<GeoPoint> vertices) {
    for (var i = 1; i < vertices.length; i++) {
      final previous = vertices[i - 1];
      final current = vertices[i];
      if (previous.longitude == current.longitude &&
          previous.latitude == current.latitude) {
        return true;
      }
    }
    return false;
  }
}
