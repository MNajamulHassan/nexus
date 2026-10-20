import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme.dart';
import '../../core/constants/env.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';
import '../../core/maps/map_models.dart';
import '../../core/maps/map_style_service.dart';
import '../../core/maps/polygon_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_error_state.dart';

class MapEditorScreen extends ConsumerStatefulWidget {
  const MapEditorScreen({super.key});

  @override
  ConsumerState<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends ConsumerState<MapEditorScreen> {
  final _viewportController = ViewportController();

  bool _loading = true;
  bool _recentering = false;
  LocationError? _locationError;
  AppLocation? _location;
  String? _status;

  MapEditorMode _mode = MapEditorMode.view;
  final List<GeoPoint> _draftVertices = [];
  MapPolygon? _playable;
  final List<MapPolygon> _restricted = [];
  String? _selectedRestrictedId;
  int _nextId = 1;

  CircleAnnotationManager? _userMarkerManager;
  CircleAnnotationManager? _vertexManager;
  PolylineAnnotationManager? _lineManager;
  PolygonAnnotationManager? _polygonManager;
  CircleAnnotation? _userMarker;
  int _redrawEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocation();
    });
  }

  @override
  void dispose() {
    _viewportController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation({bool recenter = false}) async {
    if (!AppEnv.hasMapboxToken) {
      setState(() {
        _loading = false;
        _recentering = false;
        _locationError = const LocationError(
          kind: LocationErrorKind.unknown,
          message:
              'MAPBOX_ACCESS_TOKEN is missing. Run with '
              '--dart-define-from-file=env/dev.json.',
        );
      });
      return;
    }

    if (_loading && recenter) {
      return;
    }

    setState(() {
      if (recenter) {
        _recentering = true;
      } else {
        _loading = true;
        _locationError = null;
      }
    });

    final result = await ref.read(locationServiceProvider).getCurrentLocation();
    if (!mounted) {
      return;
    }

    switch (result) {
      case LocationFix(:final location):
        setState(() {
          _loading = false;
          _recentering = false;
          _locationError = null;
          _location = location;
        });
        await _showUserMarker(location);
        _moveCamera(location, animate: recenter);
      case LocationError():
        setState(() {
          _loading = false;
          _recentering = false;
          _locationError = result;
        });
    }
  }

  void _moveCamera(AppLocation location, {required bool animate}) {
    _viewportController.moveTo(
      CameraViewportState(
        center: PolygonService.toPoint(
          GeoPoint(longitude: location.longitude, latitude: location.latitude),
        ),
        zoom: MapStyleService.defaultZoom,
      ),
      transition: animate
          ? const FlyViewportTransition(duration: Duration(milliseconds: 800))
          : const ImmediateViewportTransition(),
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    map.addInteraction(TapInteraction.onMap(_onMapTapped));

    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    _vertexManager = await map.annotations.createCircleAnnotationManager();
    _userMarkerManager = await map.annotations.createCircleAnnotationManager();

    final location = _location;
    if (location != null) {
      await _showUserMarker(location);
    }
    await _redrawAnnotations();
  }

  void _onMapTapped(MapContentGestureContext context) {
    if (_mode == MapEditorMode.view) {
      setState(() {
        _selectedRestrictedId = null;
      });
      return;
    }

    final coordinates = context.point.coordinates;
    final point = GeoPoint(
      longitude: coordinates.lng.toDouble(),
      latitude: coordinates.lat.toDouble(),
    );

    setState(() {
      _draftVertices.add(point);
      _status =
          '${_modeLabel(_mode)} · ${_draftVertices.length} point'
          '${_draftVertices.length == 1 ? '' : 's'}';
    });
    _redrawAnnotations();
  }

  Future<void> _showUserMarker(AppLocation location) async {
    final manager = _userMarkerManager;
    if (manager == null) {
      return;
    }

    final geometry = PolygonService.toPoint(
      GeoPoint(longitude: location.longitude, latitude: location.latitude),
    );
    if (_userMarker == null) {
      _userMarker = await manager.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleColor: NexusTheme.accent.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: NexusTheme.onAccent.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
      return;
    }

    _userMarker!.geometry = geometry;
    await manager.update(_userMarker!);
  }

  Future<void> _redrawAnnotations() async {
    final epoch = ++_redrawEpoch;
    final polygons = _polygonManager;
    final lines = _lineManager;
    final vertices = _vertexManager;
    if (polygons == null || lines == null || vertices == null) {
      return;
    }

    await polygons.deleteAll();
    await lines.deleteAll();
    await vertices.deleteAll();
    if (!mounted || epoch != _redrawEpoch) {
      return;
    }

    final playable = _playable;
    if (playable != null) {
      final geometry = PolygonService.toPolygon(playable.vertices);
      if (geometry != null) {
        await polygons.create(
          PolygonAnnotationOptions(
            geometry: geometry,
            fillColor: NexusTheme.accent.toARGB32(),
            fillOpacity: 0.28,
            fillOutlineColor: NexusTheme.accent.toARGB32(),
          ),
        );
      }
    }

    for (final zone in _restricted) {
      final geometry = PolygonService.toPolygon(zone.vertices);
      if (geometry == null) {
        continue;
      }
      final selected = zone.id == _selectedRestrictedId;
      await polygons.create(
        PolygonAnnotationOptions(
          geometry: geometry,
          fillColor: NexusTheme.danger.toARGB32(),
          fillOpacity: selected ? 0.5 : 0.32,
          fillOutlineColor: NexusTheme.danger.toARGB32(),
        ),
      );
    }

    if (_draftVertices.length >= 2) {
      final line = PolygonService.toLineString(_draftVertices);
      if (line != null) {
        await lines.create(
          PolylineAnnotationOptions(
            geometry: line,
            lineColor: _draftColor.toARGB32(),
            lineWidth: 3,
          ),
        );
      }
    }

    for (final vertex in _draftVertices) {
      await vertices.create(
        CircleAnnotationOptions(
          geometry: PolygonService.toPoint(vertex),
          circleColor: _draftColor.toARGB32(),
          circleRadius: 6,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
    }
  }

  Color get _draftColor {
    return _mode == MapEditorMode.drawRestrictedArea
        ? NexusTheme.danger
        : NexusTheme.accent;
  }

  void _startPlayable() {
    if (_playable != null) {
      setState(() {
        _status = 'Clear the playable area before drawing a new one.';
      });
      return;
    }
    setState(() {
      _mode = MapEditorMode.drawPlayableArea;
      _draftVertices.clear();
      _selectedRestrictedId = null;
      _status = 'Tap the map to add playable-area points.';
    });
    _redrawAnnotations();
  }

  void _startRestricted() {
    setState(() {
      _mode = MapEditorMode.drawRestrictedArea;
      _draftVertices.clear();
      _selectedRestrictedId = null;
      _status = 'Tap the map to add restricted-zone points.';
    });
    _redrawAnnotations();
  }

  void _completeDraft() {
    if (!PolygonService.canComplete(_draftVertices)) {
      setState(() {
        _status = 'Need at least ${PolygonService.minVertices} points.';
      });
      return;
    }

    final polygon = MapPolygon(
      id: _newId(
        _mode == MapEditorMode.drawRestrictedArea ? 'restricted' : 'playable',
      ),
      vertices: List<GeoPoint>.from(_draftVertices),
    );

    setState(() {
      if (_mode == MapEditorMode.drawRestrictedArea) {
        _restricted.add(polygon);
        _status = 'Restricted zone added. ${_restricted.length} total.';
      } else {
        _playable = polygon;
        _status = 'Playable area completed.';
      }
      _draftVertices.clear();
      _mode = MapEditorMode.view;
    });
    _redrawAnnotations();
  }

  void _undoLastPoint() {
    if (_draftVertices.isEmpty) {
      return;
    }
    setState(() {
      _draftVertices.removeLast();
      _status = _draftVertices.isEmpty
          ? 'No points left. Tap to add one.'
          : '${_modeLabel(_mode)} · ${_draftVertices.length} point'
                '${_draftVertices.length == 1 ? '' : 's'}';
    });
    _redrawAnnotations();
  }

  void _cancelDrawing() {
    setState(() {
      _draftVertices.clear();
      _mode = MapEditorMode.view;
      _status = 'Drawing cancelled.';
    });
    _redrawAnnotations();
  }

  void _clearPlayable() {
    setState(() {
      _playable = null;
      if (_mode == MapEditorMode.drawPlayableArea) {
        _draftVertices.clear();
        _mode = MapEditorMode.view;
      }
      _status = 'Playable area cleared.';
    });
    _redrawAnnotations();
  }

  void _deleteSelectedRestricted() {
    final id = _selectedRestrictedId;
    if (id == null) {
      if (_restricted.isEmpty) {
        setState(() {
          _status = 'No restricted zone to delete.';
        });
        return;
      }
      setState(() {
        _restricted.removeLast();
        _status = 'Last restricted zone deleted.';
      });
      _redrawAnnotations();
      return;
    }

    setState(() {
      _restricted.removeWhere((zone) => zone.id == id);
      _selectedRestrictedId = null;
      _status = 'Restricted zone deleted.';
    });
    _redrawAnnotations();
  }

  void _selectRestricted(String id) {
    setState(() {
      _selectedRestrictedId = id;
      _mode = MapEditorMode.view;
      _status = 'Restricted zone selected.';
    });
    _redrawAnnotations();
  }

  Future<void> _confirmArea() async {
    final error = PolygonService.validateForConfirm(
      playable: _playable,
      restrictedZones: _restricted,
    );
    if (error != null) {
      setState(() {
        _status = error;
      });
      return;
    }

    final playable = _playable!;
    final result = MapEditorResult(
      playable: GameZone(
        id: playable.id,
        type: ZoneType.playable,
        polygon: playable,
        name: 'Playable area',
      ),
      restrictedZones: [
        for (var i = 0; i < _restricted.length; i++)
          GameZone(
            id: _restricted[i].id,
            type: ZoneType.restricted,
            polygon: _restricted[i],
            name: 'Restricted ${i + 1}',
          ),
      ],
    );

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Area confirmed'),
          content: SingleChildScrollView(child: Text(_summary(result))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      context.pop(result);
    }
  }

  String _summary(MapEditorResult result) {
    final buffer = StringBuffer()
      ..writeln('Not saved. Temporary editor result only.')
      ..writeln()
      ..writeln('Playable: ${result.playable.polygon.vertices.length} vertices')
      ..writeln(_vertexDump(result.playable.polygon.vertices))
      ..writeln()
      ..writeln('Restricted zones: ${result.restrictedZones.length}');
    for (final zone in result.restrictedZones) {
      buffer
        ..writeln('${zone.name}: ${zone.polygon.vertices.length} vertices')
        ..writeln(_vertexDump(zone.polygon.vertices));
    }
    return buffer.toString();
  }

  String _vertexDump(List<GeoPoint> vertices) {
    return [
      for (var i = 0; i < vertices.length; i++)
        '  ${i + 1}. lng ${vertices[i].longitude.toStringAsFixed(6)}, '
            'lat ${vertices[i].latitude.toStringAsFixed(6)}',
    ].join('\n');
  }

  String _newId(String prefix) => '$prefix-${_nextId++}';

  String _modeLabel(MapEditorMode mode) {
    return switch (mode) {
      MapEditorMode.view => 'View',
      MapEditorMode.drawPlayableArea => 'Draw playable area',
      MapEditorMode.drawRestrictedArea => 'Draw restricted area',
    };
  }

  bool get _isDrawing => _mode != MapEditorMode.view;

  bool get _canConfirm =>
      _playable != null &&
      PolygonService.canComplete(_playable!.vertices) &&
      !_isDrawing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _modeLabel(_mode),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _location == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _locationError;
    if (error != null && _location == null) {
      final actionLabel = switch (error.kind) {
        LocationErrorKind.servicesDisabled => 'Open Location Settings',
        LocationErrorKind.permissionDeniedForever => 'Open App Settings',
        _ => null,
      };
      final onAction = switch (error.kind) {
        LocationErrorKind.servicesDisabled => () {
          ref.read(locationServiceProvider).openLocationSettings();
        },
        LocationErrorKind.permissionDeniedForever => () {
          ref.read(locationServiceProvider).openAppSettings();
        },
        _ => null,
      };
      return AppErrorState(
        icon: Icons.map_outlined,
        message: error.message,
        onRetry: () => _loadLocation(),
        secondaryAction: actionLabel == null
            ? null
            : OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
      );
    }

    final location = _location;
    if (location == null) {
      return const Center(child: Text('No location yet.'));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MapWidget(
                styleUri: MapStyleService.satellite,
                viewport: CameraViewportState(
                  center: PolygonService.toPoint(
                    GeoPoint(
                      longitude: location.longitude,
                      latitude: location.latitude,
                    ),
                  ),
                  zoom: MapStyleService.defaultZoom,
                ),
                viewportController: _viewportController,
                onMapCreated: _onMapCreated,
              ),
              if (_status != null)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _StatusBanner(message: _status!),
                ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  onPressed: _recentering
                      ? null
                      : () => _loadLocation(recenter: true),
                  tooltip: 'Recenter',
                  child: _recentering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
        _EditorControls(
          isDrawing: _isDrawing,
          canComplete: PolygonService.canComplete(_draftVertices),
          canUndo: _draftVertices.isNotEmpty,
          hasPlayable: _playable != null,
          hasRestricted: _restricted.isNotEmpty,
          canConfirm: _canConfirm,
          restricted: _restricted,
          selectedRestrictedId: _selectedRestrictedId,
          onDrawPlayable: _startPlayable,
          onAddRestricted: _startRestricted,
          onComplete: _completeDraft,
          onUndo: _undoLastPoint,
          onCancel: _cancelDrawing,
          onClearPlayable: _clearPlayable,
          onDeleteRestricted: _deleteSelectedRestricted,
          onSelectRestricted: _selectRestricted,
          onConfirm: _confirmArea,
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _EditorControls extends StatelessWidget {
  const _EditorControls({
    required this.isDrawing,
    required this.canComplete,
    required this.canUndo,
    required this.hasPlayable,
    required this.hasRestricted,
    required this.canConfirm,
    required this.restricted,
    required this.selectedRestrictedId,
    required this.onDrawPlayable,
    required this.onAddRestricted,
    required this.onComplete,
    required this.onUndo,
    required this.onCancel,
    required this.onClearPlayable,
    required this.onDeleteRestricted,
    required this.onSelectRestricted,
    required this.onConfirm,
  });

  final bool isDrawing;
  final bool canComplete;
  final bool canUndo;
  final bool hasPlayable;
  final bool hasRestricted;
  final bool canConfirm;
  final List<MapPolygon> restricted;
  final String? selectedRestrictedId;
  final VoidCallback onDrawPlayable;
  final VoidCallback onAddRestricted;
  final VoidCallback onComplete;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onClearPlayable;
  final VoidCallback onDeleteRestricted;
  final ValueChanged<String> onSelectRestricted;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );

    return Material(
      color: NexusTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: isDrawing ? null : onDrawPlayable,
                    child: const Text('Draw Playable Area'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: isDrawing ? null : onAddRestricted,
                    child: const Text('Add Restricted Area'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: isDrawing && canComplete ? onComplete : null,
                    child: const Text('Complete Area'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: canUndo ? onUndo : null,
                    child: const Text('Undo Last Point'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: isDrawing ? onCancel : null,
                    child: const Text('Cancel Current Drawing'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: hasPlayable ? onClearPlayable : null,
                    child: const Text('Clear Playable Area'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: hasRestricted ? onDeleteRestricted : null,
                    child: const Text('Delete Restricted Zone'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: canConfirm ? onConfirm : null,
                    child: const Text('Confirm Area'),
                  ),
                ],
              ),
              if (restricted.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < restricted.length; i++)
                      ChoiceChip(
                        label: Text('Restricted ${i + 1}'),
                        selected: restricted[i].id == selectedRestrictedId,
                        onSelected: (_) => onSelectRestricted(restricted[i].id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

