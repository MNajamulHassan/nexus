/// Geographic point stored in GeoJSON / Mapbox order: longitude, then latitude.
class GeoPoint {
  const GeoPoint({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;

  @override
  String toString() =>
      '${longitude.toStringAsFixed(6)}, ${latitude.toStringAsFixed(6)}';
}

enum ZoneType { playable, restricted }

class MapPolygon {
  const MapPolygon({required this.id, required this.vertices});

  final String id;

  /// Unclosed ring. GeoJSON close-ring is produced by [PolygonService].
  final List<GeoPoint> vertices;
}

class GameZone {
  const GameZone({
    required this.id,
    required this.type,
    required this.polygon,
    this.name,
  });

  final String id;
  final ZoneType type;
  final MapPolygon polygon;
  final String? name;
}

class MapEditorResult {
  const MapEditorResult({
    required this.playable,
    required this.restrictedZones,
  });

  final GameZone playable;
  final List<GameZone> restrictedZones;
}

enum MapEditorMode { view, drawPlayableArea, drawRestrictedArea }
