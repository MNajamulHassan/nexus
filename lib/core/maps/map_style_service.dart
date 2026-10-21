import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

abstract final class MapStyleService {
  static const satellite = MapboxStyles.SATELLITE;

  /// Satellite imagery with road/label overlays — used only by the map
  /// editor, where seeing streets while drawing a play area is useful.
  /// Keep this the one place that picks the editor's style.
  static const satelliteStreets = MapboxStyles.SATELLITE_STREETS;
  static const tactical = MapboxStyles.DARK;
  static const defaultZoom = 16.0;
}
