import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme.dart';
import '../../core/constants/env.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';
import '../../core/maps/map_style_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_error_state.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _viewportController = ViewportController();

  bool _loading = true;
  bool _recentering = false;
  LocationError? _error;
  AppLocation? _location;
  String? _mapError;

  CircleAnnotationManager? _circleManager;
  CircleAnnotation? _marker;

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
        _error = const LocationError(
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
        _error = null;
        _mapError = null;
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
          _error = null;
          _location = location;
        });
        await _showMarker(location);
        _moveCamera(location, animate: recenter);
      case LocationError():
        setState(() {
          _loading = false;
          _recentering = false;
          _error = result;
        });
    }
  }

  Point _toPoint(AppLocation location) {
    return Point(
      coordinates: Position(location.longitude, location.latitude),
    );
  }

  void _moveCamera(AppLocation location, {required bool animate}) {
    _viewportController.moveTo(
      CameraViewportState(
        center: _toPoint(location),
        zoom: MapStyleService.defaultZoom,
      ),
      transition: animate
          ? const FlyViewportTransition(duration: Duration(milliseconds: 800))
          : const ImmediateViewportTransition(),
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _circleManager = await map.annotations.createCircleAnnotationManager();
    final location = _location;
    if (location != null) {
      await _showMarker(location);
    }
  }

  Future<void> _showMarker(AppLocation location) async {
    final manager = _circleManager;
    if (manager == null) {
      return;
    }

    final geometry = _toPoint(location);
    if (_marker == null) {
      _marker = await manager.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleColor: NexusTheme.accent.toARGB32(),
          circleRadius: 8,
          circleStrokeColor: NexusTheme.onAccent.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
      return;
    }

    _marker!.geometry = geometry;
    await manager.update(_marker!);
  }

  Future<void> _openSettings(Future<bool> Function() open) async {
    await open();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Test')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _location == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null && _location == null) {
      final actionLabel = switch (error.kind) {
        LocationErrorKind.servicesDisabled => 'Open Location Settings',
        LocationErrorKind.permissionDeniedForever => 'Open App Settings',
        _ => null,
      };
      final onAction = switch (error.kind) {
        LocationErrorKind.servicesDisabled => () {
          _openSettings(ref.read(locationServiceProvider).openLocationSettings);
        },
        LocationErrorKind.permissionDeniedForever => () {
          _openSettings(ref.read(locationServiceProvider).openAppSettings);
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

    return Stack(
      children: [
        MapWidget(
          styleUri: MapStyleService.satellite,
          viewport: CameraViewportState(
            center: _toPoint(location),
            zoom: MapStyleService.defaultZoom,
          ),
          viewportController: _viewportController,
          onMapCreated: _onMapCreated,
          onMapLoadErrorListener: (event) {
            if (!mounted) {
              return;
            }
            setState(() {
              _mapError = event.message;
            });
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _AccuracyOverlay(
            accuracyMeters: location.accuracyMeters,
            mapError: _mapError,
            locationError: error,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _recentering ? null : () => _loadLocation(recenter: true),
            tooltip: 'Recenter',
            child: _recentering
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}

class _AccuracyOverlay extends StatelessWidget {
  const _AccuracyOverlay({
    required this.accuracyMeters,
    this.mapError,
    this.locationError,
  });

  final double? accuracyMeters;
  final String? mapError;
  final LocationError? locationError;

  @override
  Widget build(BuildContext context) {
    final message = locationError?.message ??
        (mapError != null
            ? 'Map failed to load: $mapError'
            : accuracyMeters == null
            ? 'Accuracy unavailable'
            : 'Accuracy ${accuracyMeters!.toStringAsFixed(1)} m');

    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
