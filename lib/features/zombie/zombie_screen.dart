import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme.dart';
import '../../core/location/distance.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';
import '../../core/maps/map_models.dart';
import '../../core/maps/map_style_service.dart';
import '../../core/maps/polygon_service.dart';
import '../../core/widgets/app_card.dart';
import 'zombie_models.dart';

/// Singleplayer outdoor mode: walk from your current position to a
/// player-chosen destination while zombies (simple chase AI) try to catch
/// you. Fully local — no Supabase round-trip, no persistence.
class ZombieScreen extends ConsumerStatefulWidget {
  const ZombieScreen({super.key});

  @override
  ConsumerState<ZombieScreen> createState() => _ZombieScreenState();
}

class _ZombieScreenState extends ConsumerState<ZombieScreen> {
  static const _winRadiusMeters = 15.0;
  static const _lossRadiusMeters = 6.0;
  static const _zombieCount = 5;
  static const _baseDetectionRadiusMeters = 30.0;
  static const _concealedDetectionRadiusMeters = 12.0;

  final _viewportController = ViewportController();
  final _random = Random();

  ZombieGameStatus _status = ZombieGameStatus.settingDestination;
  AppLocation? _myLocation;
  Point? _initialCenter;
  String? _locationNotice;

  GeoPoint? _start;
  GeoPoint? _destination;
  List<List<GeoPoint>> _corridors = const [];
  List<Zombie> _zombies = const [];
  bool _inSafeZone = true;
  int _elapsedSeconds = 0;

  StreamSubscription<LocationResult>? _locationSub;
  Timer? _zombieTicker;
  Timer? _displayTicker;

  PolygonAnnotationManager? _corridorManager;
  CircleAnnotationManager? _selfMarkerManager;
  CircleAnnotationManager? _destinationMarkerManager;
  CircleAnnotationManager? _zombieMarkerManager;
  CircleAnnotation? _selfMarker;

  @override
  void initState() {
    super.initState();
    _startLocationStream();
  }

  @override
  void dispose() {
    unawaited(_locationSub?.cancel());
    _zombieTicker?.cancel();
    _displayTicker?.cancel();
    _viewportController.dispose();
    super.dispose();
  }

  void _startLocationStream() {
    _locationSub = ref.read(locationServiceProvider).watchPosition().listen((
      result,
    ) {
      if (!mounted) {
        return;
      }
      switch (result) {
        case LocationFix(:final location):
          final point = GeoPoint(
            longitude: location.longitude,
            latitude: location.latitude,
          );
          setState(() {
            _myLocation = location;
            _locationNotice = null;
            _initialCenter ??= PolygonService.toPoint(point);
            _start ??= point;
          });
          unawaited(_showSelfMarker(location));
          if (_status == ZombieGameStatus.playing) {
            _checkWinLoss(point);
          }
        case LocationError(:final message):
          setState(() => _locationNotice = message);
      }
    });
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));

    map.addInteraction(TapInteraction.onMap(_onMapTapped));
    _corridorManager = await map.annotations.createPolygonAnnotationManager();
    _selfMarkerManager = await map.annotations.createCircleAnnotationManager();
    _destinationMarkerManager = await map.annotations
        .createCircleAnnotationManager();
    _zombieMarkerManager = await map.annotations.createCircleAnnotationManager();

    final location = _myLocation;
    if (location != null) {
      await _showSelfMarker(location);
    }
  }

  void _onMapTapped(MapContentGestureContext context) {
    if (_status != ZombieGameStatus.settingDestination) {
      return;
    }
    final start = _start;
    if (start == null) {
      return;
    }
    final coordinates = context.point.coordinates;
    final destination = GeoPoint(
      longitude: coordinates.lng.toDouble(),
      latitude: coordinates.lat.toDouble(),
    );

    final corridors = _buildCorridors(start, destination);
    final zombies = _spawnZombies(start, destination);

    setState(() {
      _destination = destination;
      _corridors = corridors;
      _zombies = zombies;
      _status = ZombieGameStatus.playing;
      _elapsedSeconds = 0;
    });

    unawaited(_drawCorridors());
    unawaited(_drawDestination());
    unawaited(_redrawZombies());

    _displayTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
    _zombieTicker = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _zombieTick(),
    );
  }

  void _zombieTick() {
    final player = _myLocation;
    if (player == null || _status != ZombieGameStatus.playing) {
      return;
    }
    final playerPoint = GeoPoint(
      longitude: player.longitude,
      latitude: player.latitude,
    );
    final inSafeZone =
        _corridors.isEmpty ||
        _corridors.any((zone) => _pointInPolygon(playerPoint, zone));
    final detectionRadius = inSafeZone
        ? _concealedDetectionRadiusMeters
        : _baseDetectionRadiusMeters;
    setState(() {
      _inSafeZone = inSafeZone;
      for (final zombie in _zombies) {
        zombie.tick(
          playerPosition: playerPoint,
          detectionRadiusMeters: detectionRadius,
        );
      }
    });
    unawaited(_redrawZombies());
    _checkWinLoss(playerPoint);
  }

  void _checkWinLoss(GeoPoint playerPoint) {
    if (_status != ZombieGameStatus.playing) {
      return;
    }
    final destination = _destination;
    if (destination != null) {
      final toGoal = haversineMeters(
        playerPoint.latitude,
        playerPoint.longitude,
        destination.latitude,
        destination.longitude,
      );
      if (toGoal <= _winRadiusMeters) {
        _finish(ZombieGameStatus.won);
        return;
      }
    }
    for (final zombie in _zombies) {
      final toZombie = haversineMeters(
        playerPoint.latitude,
        playerPoint.longitude,
        zombie.position.latitude,
        zombie.position.longitude,
      );
      if (toZombie <= _lossRadiusMeters) {
        _finish(ZombieGameStatus.lost);
        return;
      }
    }
  }

  void _finish(ZombieGameStatus status) {
    _zombieTicker?.cancel();
    _displayTicker?.cancel();
    setState(() => _status = status);
  }

  void _reset() {
    _zombieTicker?.cancel();
    _displayTicker?.cancel();
    setState(() {
      _status = ZombieGameStatus.settingDestination;
      _destination = null;
      _corridors = const [];
      _zombies = const [];
      _inSafeZone = true;
      _elapsedSeconds = 0;
    });
    unawaited(_corridorManager?.deleteAll());
    unawaited(_destinationMarkerManager?.deleteAll());
    unawaited(_zombieMarkerManager?.deleteAll());
  }

  Future<void> _showSelfMarker(AppLocation location) async {
    final manager = _selfMarkerManager;
    if (manager == null) {
      return;
    }
    final geometry = PolygonService.toPoint(
      GeoPoint(longitude: location.longitude, latitude: location.latitude),
    );
    if (_selfMarker == null) {
      _selfMarker = await manager.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleColor: NexusTheme.accent.toARGB32(),
          circleRadius: 8,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
      return;
    }
    _selfMarker!.geometry = geometry;
    await manager.update(_selfMarker!);
  }

  Future<void> _drawCorridors() async {
    final manager = _corridorManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    for (final zone in _corridors) {
      final geometry = PolygonService.toPolygon(zone);
      if (geometry == null) {
        continue;
      }
      await manager.create(
        PolygonAnnotationOptions(
          geometry: geometry,
          fillColor: NexusTheme.success.toARGB32(),
          fillOpacity: 0.18,
          fillOutlineColor: NexusTheme.success.toARGB32(),
        ),
      );
    }
  }

  Future<void> _drawDestination() async {
    final manager = _destinationMarkerManager;
    final destination = _destination;
    if (manager == null || destination == null) {
      return;
    }
    await manager.deleteAll();
    await manager.create(
      CircleAnnotationOptions(
        geometry: PolygonService.toPoint(destination),
        circleColor: NexusTheme.success.toARGB32(),
        circleRadius: 10,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 2,
      ),
    );
  }

  Future<void> _redrawZombies() async {
    final manager = _zombieMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    for (final zombie in _zombies) {
      final (color, radius) = switch (zombie.aiState) {
        ZombieAiState.patrol => (NexusTheme.warning, 7.0),
        ZombieAiState.investigating => (NexusTheme.warning, 8.0),
        ZombieAiState.hunting => (NexusTheme.danger, 10.0),
      };
      await manager.create(
        CircleAnnotationOptions(
          geometry: PolygonService.toPoint(zombie.position),
          circleColor: color.toARGB32(),
          circleRadius: radius,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
    }
  }

  void _recenter() {
    final location = _myLocation;
    if (location == null) {
      return;
    }
    _viewportController.moveTo(
      CameraViewportState(
        center: PolygonService.toPoint(
          GeoPoint(longitude: location.longitude, latitude: location.latitude),
        ),
        zoom: MapStyleService.defaultZoom,
      ),
      transition: const FlyViewportTransition(
        duration: Duration(milliseconds: 600),
      ),
    );
  }

  // --- Local geometry helpers (meters <-> degrees via an equirectangular
  // approximation; accurate enough at the scale of one outdoor route). ---

  GeoPoint _lerp(GeoPoint a, GeoPoint b, double t) {
    return GeoPoint(
      longitude: a.longitude + (b.longitude - a.longitude) * t,
      latitude: a.latitude + (b.latitude - a.latitude) * t,
    );
  }

  List<GeoPoint> _rectangle(GeoPoint a, GeoPoint b, double halfWidthMeters) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos(a.latitude * pi / 180);
    final dx = (b.longitude - a.longitude) * metersPerDegreeLon;
    final dy = (b.latitude - a.latitude) * metersPerDegreeLat;
    final length = sqrt(dx * dx + dy * dy);
    if (length == 0) {
      return [a, a, a];
    }
    final perpX = -dy / length * halfWidthMeters;
    final perpY = dx / length * halfWidthMeters;
    GeoPoint offset(GeoPoint p, double ox, double oy) => GeoPoint(
      longitude: p.longitude + ox / metersPerDegreeLon,
      latitude: p.latitude + oy / metersPerDegreeLat,
    );
    return [
      offset(a, perpX, perpY),
      offset(b, perpX, perpY),
      offset(b, -perpX, -perpY),
      offset(a, -perpX, -perpY),
    ];
  }

  List<List<GeoPoint>> _buildCorridors(GeoPoint start, GeoPoint destination) {
    final waypoints = [
      start,
      _lerp(start, destination, 0.33),
      _lerp(start, destination, 0.66),
      destination,
    ];
    final corridors = <List<GeoPoint>>[];
    for (var i = 0; i < waypoints.length - 1; i++) {
      final segStart = _lerp(waypoints[i], waypoints[i + 1], 0.1);
      final segEnd = _lerp(waypoints[i], waypoints[i + 1], 0.9);
      corridors.add(_rectangle(segStart, segEnd, 12));
    }
    return corridors;
  }

  List<Zombie> _spawnZombies(GeoPoint start, GeoPoint destination) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos(start.latitude * pi / 180);
    final dx = (destination.longitude - start.longitude) * metersPerDegreeLon;
    final dy = (destination.latitude - start.latitude) * metersPerDegreeLat;
    final length = sqrt(dx * dx + dy * dy);

    GeoPoint spawnPoint() {
      final t = 0.25 + _random.nextDouble() * 0.5;
      final base = _lerp(start, destination, t);
      final lateral = (_random.nextDouble() - 0.5) * 80;
      final perpX = length == 0 ? 0.0 : -dy / length * lateral;
      final perpY = length == 0 ? 0.0 : dx / length * lateral;
      return GeoPoint(
        longitude: base.longitude + perpX / metersPerDegreeLon,
        latitude: base.latitude + perpY / metersPerDegreeLat,
      );
    }

    return [
      for (var i = 0; i < _zombieCount; i++)
        () {
          final spawn = spawnPoint();
          return Zombie(id: i, position: spawn, homeArea: spawn);
        }(),
    ];
  }

  bool _pointInPolygon(GeoPoint point, List<GeoPoint> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersect =
          ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zombie Mode')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final location = _myLocation;
    final center = _initialCenter;
    if (location == null || center == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_locationNotice ?? 'Waiting for GPS…'),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        MapWidget(
          styleUri: MapStyleService.tactical,
          viewport: CameraViewportState(
            center: center,
            zoom: MapStyleService.defaultZoom,
          ),
          viewportController: _viewportController,
          onMapCreated: _onMapCreated,
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _ZombieHud(
            status: _status,
            zombiesRemaining: _zombies.length,
            huntingCount: _zombies
                .where((z) => z.aiState == ZombieAiState.hunting)
                .length,
            elapsedSeconds: _elapsedSeconds,
            inSafeZone: _inSafeZone,
            locationNotice: _locationNotice,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            onPressed: _recenter,
            tooltip: 'Recenter',
            child: const Icon(Icons.my_location),
          ),
        ),
        if (_status == ZombieGameStatus.won || _status == ZombieGameStatus.lost)
          _ZombieResultOverlay(
            won: _status == ZombieGameStatus.won,
            elapsedSeconds: _elapsedSeconds,
            onPlayAgain: _reset,
            onHome: () => context.go('/'),
          ),
      ],
    );
  }
}

class _ZombieHud extends StatelessWidget {
  const _ZombieHud({
    required this.status,
    required this.zombiesRemaining,
    required this.huntingCount,
    required this.elapsedSeconds,
    required this.inSafeZone,
    required this.locationNotice,
  });

  final ZombieGameStatus status;
  final int zombiesRemaining;
  final int huntingCount;
  final int elapsedSeconds;
  final bool inSafeZone;
  final String? locationNotice;

  @override
  Widget build(BuildContext context) {
    final headline = switch (status) {
      ZombieGameStatus.settingDestination =>
        'Tap the map to choose your destination',
      ZombieGameStatus.playing =>
        'Reach the green marker · $zombiesRemaining zombies · ${elapsedSeconds}s',
      ZombieGameStatus.won => 'You escaped!',
      ZombieGameStatus.lost => 'Caught!',
    };

    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (status == ZombieGameStatus.playing) ...[
            const SizedBox(height: 4),
            Text(
              huntingCount > 0
                  ? "You've been spotted! $huntingCount hunting you"
                  : 'Unnoticed — move carefully',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: huntingCount > 0
                    ? NexusTheme.danger
                    : NexusTheme.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (status == ZombieGameStatus.playing && !inSafeZone) ...[
            const SizedBox(height: 4),
            Text(
              'Off the safe path — head for a green zone',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NexusTheme.warning),
            ),
          ],
          if (locationNotice != null) ...[
            const SizedBox(height: 4),
            Text(
              locationNotice!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NexusTheme.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZombieResultOverlay extends StatelessWidget {
  const _ZombieResultOverlay({
    required this.won,
    required this.elapsedSeconds,
    required this.onPlayAgain,
    required this.onHome,
  });

  final bool won;
  final int elapsedSeconds;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    won ? Icons.flag_circle : Icons.coronavirus,
                    size: 48,
                    color: won ? NexusTheme.success : NexusTheme.danger,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    won ? 'You escaped!' : 'Caught!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text('Time: ${elapsedSeconds}s'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onPlayAgain,
                    child: const Text('Play Again'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onHome, child: const Text('Home')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
