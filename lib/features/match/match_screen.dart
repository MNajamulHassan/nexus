import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';
import '../../core/maps/map_models.dart';
import '../../core/maps/map_style_service.dart';
import '../../core/maps/polygon_service.dart';
import '../../models/game.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  static const _restrictedColor = Color(0xFFFF1744);
  static const _hiderColor = Color(0xFFFF5252);

  final _viewportController = ViewportController();

  String? _userId;
  bool _loading = true;
  String? _error;
  String? _locationNotice;

  GameRecord? _game;
  List<GamePlayerRecord> _players = const [];
  List<GameZone> _zones = const [];
  List<HiderSighting> _sightings = const [];
  AppLocation? _myLocation;
  Point? _initialCenter;

  Timer? _syncTimer;
  Timer? _displayTicker;
  StreamSubscription<LocationResult>? _locationSub;
  bool _navigatedAway = false;

  PolygonAnnotationManager? _polygonManager;
  CircleAnnotationManager? _selfMarkerManager;
  CircleAnnotationManager? _hiderMarkerManager;
  CircleAnnotation? _selfMarker;

  @override
  void initState() {
    super.initState();
    _userId = ref.read(playerIdentityProvider).value?.userId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _stopTimers();
    _viewportController.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _displayTicker?.cancel();
    _displayTicker = null;
    unawaited(_locationSub?.cancel());
    _locationSub = null;
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(gameRepositoryProvider);
      final game = await repo.fetchGame(widget.gameId);
      final players = await repo.fetchPlayers(widget.gameId);
      final zones = await repo.fetchZones(widget.gameId);
      if (!mounted) {
        return;
      }

      setState(() {
        _game = game;
        _players = players;
        _zones = zones;
        _loading = false;
      });

      if (game.status == 'FINISHED' || game.status == 'CLOSED') {
        _goToResults();
        return;
      }

      _startLocationStream();
      _displayTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
      unawaited(_tick());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _tick() async {
    if (!mounted || _navigatedAway) {
      return;
    }
    try {
      final repo = ref.read(gameRepositoryProvider);
      final game = await repo.syncMatchState(widget.gameId);
      final players = await repo.fetchPlayers(widget.gameId);
      final userId = _userId;
      final mine = userId == null ? null : _lookup(players, userId);

      var sightings = const <HiderSighting>[];
      if (mine?.isSeeker == true && game.status == 'ACTIVE') {
        sightings = await repo.fetchSeekerView(widget.gameId);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _game = game;
        _players = players;
        _sightings = sightings;
      });
      unawaited(_redrawHiders());

      if (game.status == 'FINISHED' || game.status == 'CLOSED') {
        _goToResults();
      }
    } catch (_) {
      // Transient network hiccup; the next tick retries.
    }
  }

  void _goToResults() {
    if (_navigatedAway) {
      return;
    }
    _navigatedAway = true;
    _stopTimers();
    if (mounted) {
      context.go('/results/${widget.gameId}');
    }
  }

  GamePlayerRecord? _lookup(List<GamePlayerRecord> players, String userId) {
    for (final player in players) {
      if (player.playerId == userId) {
        return player;
      }
    }
    return null;
  }

  GamePlayerRecord? get _myPlayer {
    final userId = _userId;
    if (userId == null) {
      return null;
    }
    return _lookup(_players, userId);
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
          final point = PolygonService.toPoint(
            GeoPoint(longitude: location.longitude, latitude: location.latitude),
          );
          setState(() {
            _myLocation = location;
            _locationNotice = null;
            _initialCenter ??= point;
          });
          unawaited(_showSelfMarker(location));
          unawaited(_reportLocation(location));
        case LocationError(:final message):
          setState(() => _locationNotice = message);
      }
    });
  }

  Future<void> _reportLocation(AppLocation location) async {
    try {
      await ref
          .read(gameRepositoryProvider)
          .reportLocation(widget.gameId, location);
    } catch (_) {
      // Next fix retries; a dropped update is not fatal.
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    _selfMarkerManager = await map.annotations.createCircleAnnotationManager();
    _hiderMarkerManager = await map.annotations.createCircleAnnotationManager();

    await _drawZones();
    final location = _myLocation;
    if (location != null) {
      await _showSelfMarker(location);
    }
    await _redrawHiders();
  }

  Future<void> _drawZones() async {
    final manager = _polygonManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    for (final zone in _zones) {
      final geometry = PolygonService.toPolygon(zone.polygon.vertices);
      if (geometry == null) {
        continue;
      }
      final isPlayable = zone.type == ZoneType.playable;
      final color = isPlayable ? NexusTheme.accent : _restrictedColor;
      await manager.create(
        PolygonAnnotationOptions(
          geometry: geometry,
          fillColor: color.toARGB32(),
          fillOpacity: isPlayable ? 0.06 : 0.26,
          fillOutlineColor: color.toARGB32(),
        ),
      );
    }
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

  Future<void> _redrawHiders() async {
    final manager = _hiderMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    for (final sighting in _sightings) {
      await manager.create(
        CircleAnnotationOptions(
          geometry: PolygonService.toPoint(
            GeoPoint(
              longitude: sighting.longitude,
              latitude: sighting.latitude,
            ),
          ),
          circleColor: _hiderColor.toARGB32(),
          circleRadius: 9,
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
      transition: const FlyViewportTransition(duration: Duration(milliseconds: 600)),
    );
  }

  DateTime? get _activeAt {
    final game = _game;
    final startedAt = game?.startedAt;
    if (game == null || startedAt == null) {
      return null;
    }
    return startedAt.add(Duration(seconds: game.hidingDurationSeconds));
  }

  DateTime? get _endAt {
    final activeAt = _activeAt;
    final game = _game;
    if (activeAt == null || game == null) {
      return null;
    }
    return activeAt.add(Duration(seconds: game.matchDurationSeconds));
  }

  bool get _revealActive {
    final game = _game;
    final activeAt = _activeAt;
    if (game == null || activeAt == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(activeAt).inSeconds;
    if (elapsed < 0) {
      return false;
    }
    return (elapsed % game.revealIntervalSeconds) < game.revealDurationSeconds;
  }

  int get _secondsRemaining {
    final game = _game;
    if (game == null) {
      return 0;
    }
    final target = game.status == 'HIDING_PHASE' ? _activeAt : _endAt;
    if (target == null) {
      return 0;
    }
    final remaining = target.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hide & Seek'),
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }

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
          child: _MatchHud(
            game: _game,
            myRole: _myPlayer?.role,
            eliminated: _myPlayer?.isEliminated ?? false,
            revealActive: _revealActive,
            secondsRemaining: _secondsRemaining,
            hidersRemaining: _players
                .where((p) => p.isHider && p.status == 'ACTIVE')
                .length,
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
      ],
    );
  }
}

class _MatchHud extends StatelessWidget {
  const _MatchHud({
    required this.game,
    required this.myRole,
    required this.eliminated,
    required this.revealActive,
    required this.secondsRemaining,
    required this.hidersRemaining,
    required this.locationNotice,
  });

  final GameRecord? game;
  final String? myRole;
  final bool eliminated;
  final bool revealActive;
  final int secondsRemaining;
  final int hidersRemaining;
  final String? locationNotice;

  @override
  Widget build(BuildContext context) {
    final status = game?.status;
    final roleLabel = switch (myRole) {
      'SEEKER' => 'Seeker',
      'HIDER' => 'Hider',
      _ => 'Player',
    };

    final (headline, color) = switch (status) {
      'HIDING_PHASE' => (
        myRole == 'SEEKER'
            ? 'Hiding phase — wait $secondsRemaining s'
            : 'Hide! $secondsRemaining s left',
        Colors.amberAccent,
      ),
      'ACTIVE' => (
        eliminated
            ? 'You were caught — spectating'
            : myRole == 'SEEKER'
                ? (revealActive
                    ? 'REVEAL ACTIVE — hiders visible!'
                    : 'Hunting — $hidersRemaining hiding')
                : (revealActive
                    ? 'You are exposed!'
                    : 'Hidden — stay safe'),
        eliminated
            ? Colors.white70
            : (revealActive ? Colors.redAccent : NexusTheme.accent),
      ),
      _ => ('Starting…', Colors.white70),
    };

    return Material(
      color: NexusTheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headline,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              status == 'ACTIVE'
                  ? 'Role: $roleLabel · Match ends in $secondsRemaining s'
                  : 'Role: $roleLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (locationNotice != null) ...[
              const SizedBox(height: 4),
              Text(
                locationNotice!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
