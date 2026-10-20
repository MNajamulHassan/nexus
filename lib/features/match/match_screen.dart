import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme.dart';
import '../../core/auth/auth_models.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';
import '../../core/maps/map_models.dart';
import '../../core/maps/map_style_service.dart';
import '../../core/maps/polygon_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_error_state.dart';
import '../../models/game.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  final _viewportController = ViewportController();

  String? _userId;
  bool _loading = true;
  String? _error;
  String? _locationNotice;
  String? _visibilityNotice;

  GameRecord? _game;
  List<GamePlayerRecord> _players = const [];
  List<GameZone> _zones = const [];
  List<HiderSighting> _sightings = const [];
  SeekerSighting? _seekerSighting;
  List<CatchCandidate> _catchCandidates = const [];
  Map<String, PlayerProfile> _profiles = const {};
  AppLocation? _myLocation;
  Point? _initialCenter;

  Timer? _syncTimer;
  Timer? _displayTicker;
  StreamSubscription<LocationResult>? _locationSub;
  bool _navigatedAway = false;

  PolygonAnnotationManager? _polygonManager;
  PolylineAnnotationManager? _boundaryLineManager;
  CircleAnnotationManager? _boundaryNodeManager;
  CircleAnnotationManager? _selfMarkerManager;
  CircleAnnotationManager? _hiderMarkerManager;
  CircleAnnotationManager? _seekerMarkerManager;

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
      final profiles = await repo.fetchProfiles([
        for (final player in players) player.playerId,
      ]);
      if (!mounted) {
        return;
      }

      setState(() {
        _game = game;
        _players = players;
        _zones = zones;
        _profiles = profiles;
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
    final repo = ref.read(gameRepositoryProvider);
    GameRecord game;
    List<GamePlayerRecord> players;
    try {
      // Core state: this must always land, even if the optional visibility
      // fetches below fail — otherwise a single bad RPC call permanently
      // freezes the phase/role display.
      game = await repo.syncMatchState(widget.gameId);
      players = await repo.fetchPlayers(widget.gameId);
    } catch (_) {
      return; // Transient network hiccup; the next tick retries.
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _game = game;
      _players = players;
    });

    if (game.status == 'FINISHED' || game.status == 'CLOSED') {
      _goToResults();
      return;
    }

    final userId = _userId;
    final mine = userId == null ? null : _lookup(players, userId);
    try {
      if (mine?.isSeeker == true && game.status == 'ACTIVE') {
        final sightings = await repo.fetchSeekerView(widget.gameId);
        final candidates = await repo.fetchCatchCandidates(widget.gameId);
        if (!mounted) {
          return;
        }
        setState(() {
          _sightings = sightings;
          _catchCandidates = candidates;
          _visibilityNotice = null;
        });
      } else if (mine?.isHider == true && game.status == 'ACTIVE') {
        final seekerSighting = await repo.fetchSeekerLocation(widget.gameId);
        if (!mounted) {
          return;
        }
        setState(() {
          _seekerSighting = seekerSighting;
          _visibilityNotice = null;
        });
      }
    } catch (error) {
      // Keep last-known sightings/candidates; next tick retries. Surface
      // the error instead of swallowing it outright — this is exactly the
      // kind of failure that otherwise looks like "nothing is happening."
      if (mounted) {
        setState(() => _visibilityNotice = '$error');
      }
    }
    unawaited(_redrawHiders());
    unawaited(_redrawSeekerMarker());
  }

  Future<void> _catchHider(String hiderId) async {
    await ref.read(gameRepositoryProvider).attemptCatch(widget.gameId, hiderId);
    unawaited(_tick());
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
    // The built-in scale bar/compass overlap the HUD card; this game needs
    // neither.
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));

    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    _boundaryLineManager = await map.annotations
        .createPolylineAnnotationManager();
    _boundaryNodeManager = await map.annotations
        .createCircleAnnotationManager();
    _selfMarkerManager = await map.annotations.createCircleAnnotationManager();
    _hiderMarkerManager = await map.annotations.createCircleAnnotationManager();
    _seekerMarkerManager = await map.annotations
        .createCircleAnnotationManager();

    await _drawZones();
    final location = _myLocation;
    if (location != null) {
      await _showSelfMarker(location);
    }
    await _redrawHiders();
    await _redrawSeekerMarker();
  }

  Future<void> _drawZones() async {
    final polygons = _polygonManager;
    final lines = _boundaryLineManager;
    final nodes = _boundaryNodeManager;
    if (polygons == null || lines == null || nodes == null) {
      return;
    }
    await polygons.deleteAll();
    await lines.deleteAll();
    await nodes.deleteAll();

    for (final zone in _zones) {
      final vertices = zone.polygon.vertices;
      final isPlayable = zone.type == ZoneType.playable;
      final color = isPlayable ? NexusTheme.accent : NexusTheme.danger;
      final outline = PolygonService.toLineString(
        PolygonService.closedRing(vertices),
      );

      // Restricted zones get a solid fill; the playable boundary is an
      // outline only, matching a tactical-ops map rather than a flat shape.
      if (!isPlayable) {
        final fill = PolygonService.toPolygon(vertices);
        if (fill != null) {
          await polygons.create(
            PolygonAnnotationOptions(
              geometry: fill,
              fillColor: color.toARGB32(),
              fillOpacity: 0.3,
              fillOutlineColor: color.toARGB32(),
            ),
          );
        }
      }

      if (outline != null) {
        // Glow pass (wide, blurred, translucent) under a crisp line.
        await lines.create(
          PolylineAnnotationOptions(
            geometry: outline,
            lineColor: color.toARGB32(),
            lineWidth: 10,
            lineBlur: 8,
            lineOpacity: 0.45,
          ),
        );
        await lines.create(
          PolylineAnnotationOptions(
            geometry: outline,
            lineColor: color.toARGB32(),
            lineWidth: 2,
          ),
        );
      }

      if (isPlayable) {
        for (final vertex in vertices) {
          await nodes.create(
            CircleAnnotationOptions(
              geometry: PolygonService.toPoint(vertex),
              circleColor: NexusTheme.background.toARGB32(),
              circleRadius: 4,
              circleStrokeColor: color.toARGB32(),
              circleStrokeWidth: 2,
            ),
          );
        }
      }
    }
  }

  /// Glowing marker: a wide blurred halo under a crisp dot. [hollow] draws
  /// the dot as an unfilled ring instead of a solid fill — used to tell
  /// "you" (solid) apart from a hider sighting (hollow) at the same hue.
  Future<void> _createGlowMarker(
    CircleAnnotationManager manager,
    Point geometry,
    Color color, {
    bool hollow = false,
  }) async {
    await manager.create(
      CircleAnnotationOptions(
        geometry: geometry,
        circleColor: color.toARGB32(),
        circleRadius: 20,
        circleBlur: 1,
        circleOpacity: 0.35,
      ),
    );
    await manager.create(
      CircleAnnotationOptions(
        geometry: geometry,
        circleColor: color.toARGB32(),
        circleOpacity: hollow ? 0 : 1,
        circleRadius: 8,
        circleStrokeColor: hollow ? color.toARGB32() : Colors.white.toARGB32(),
        circleStrokeWidth: hollow ? 3 : 2,
      ),
    );
  }

  Future<void> _showSelfMarker(AppLocation location) async {
    final manager = _selfMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    await _createGlowMarker(
      manager,
      PolygonService.toPoint(
        GeoPoint(longitude: location.longitude, latitude: location.latitude),
      ),
      NexusTheme.accent,
    );
  }

  Future<void> _redrawHiders() async {
    final manager = _hiderMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    for (final sighting in _sightings) {
      await _createGlowMarker(
        manager,
        PolygonService.toPoint(
          GeoPoint(
            longitude: sighting.longitude,
            latitude: sighting.latitude,
          ),
        ),
        NexusTheme.accent,
        hollow: true,
      );
    }
  }

  Future<void> _redrawSeekerMarker() async {
    final manager = _seekerMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    final seeker = _seekerSighting;
    if (seeker == null) {
      return;
    }
    await _createGlowMarker(
      manager,
      PolygonService.toPoint(
        GeoPoint(longitude: seeker.longitude, latitude: seeker.latitude),
      ),
      NexusTheme.danger,
    );
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
      return AppErrorState(message: error);
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
          onMapLoadErrorListener: (event) {
            if (mounted) {
              setState(() => _locationNotice = 'Map failed to load: ${event.message}');
            }
          },
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _BrandHud(
                  game: _game,
                  myRole: _myPlayer?.role,
                  eliminated: _myPlayer?.isEliminated ?? false,
                  revealActive: _revealActive,
                  secondsRemaining: _secondsRemaining,
                  hidersRemaining: _players
                      .where((p) => p.isHider && p.status == 'ACTIVE')
                      .length,
                  sightingsCount: _sightings.length,
                  locationNotice: _locationNotice,
                  visibilityNotice: _visibilityNotice,
                ),
              ),
              const SizedBox(width: 10),
              _LegendPanel(myRole: _myPlayer?.role),
            ],
          ),
        ),
        if (_catchCandidates.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final candidate in _catchCandidates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HoldToCatchButton(
                      key: ValueKey(candidate.hiderId),
                      label:
                          _profiles[candidate.hiderId]?.displayName ?? 'Hider',
                      distanceMeters: candidate.distanceMeters,
                      onCatch: () => _catchHider(candidate.hiderId),
                    ),
                  ),
              ],
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

/// Hold for ~5 continuous seconds to catch a nearby hider. Releasing early
/// cancels the attempt; the server still validates the catch regardless.
class _HoldToCatchButton extends StatefulWidget {
  const _HoldToCatchButton({
    super.key,
    required this.label,
    required this.distanceMeters,
    required this.onCatch,
  });

  final String label;
  final double distanceMeters;
  final Future<void> Function() onCatch;

  @override
  State<_HoldToCatchButton> createState() => _HoldToCatchButtonState();
}

class _HoldToCatchButtonState extends State<_HoldToCatchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..addStatusListener(_onStatus);
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (_busy) {
      return;
    }
    _controller.forward(from: 0);
  }

  void _cancel() {
    if (_busy) {
      return;
    }
    _controller.reverse();
  }

  Future<void> _onStatus(AnimationStatus status) async {
    if (status != AnimationStatus.completed || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onCatch();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _controller.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _busy ? null : _controller.value,
                  color: NexusTheme.danger,
                  backgroundColor: NexusTheme.hairline,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Hold to catch ${widget.label} · ${widget.distanceMeters.round()}m',
              style: NexusTheme.readout.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatClock(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Tactical-ops style HUD: brand mark, a short status line, and a large
/// countdown clock — modeled directly on the reference the user provided.
class _BrandHud extends StatelessWidget {
  const _BrandHud({
    required this.game,
    required this.myRole,
    required this.eliminated,
    required this.revealActive,
    required this.secondsRemaining,
    required this.hidersRemaining,
    required this.sightingsCount,
    required this.locationNotice,
    required this.visibilityNotice,
  });

  final GameRecord? game;
  final String? myRole;
  final bool eliminated;
  final bool revealActive;
  final int secondsRemaining;
  final int hidersRemaining;
  final int sightingsCount;
  final String? locationNotice;
  final String? visibilityNotice;

  @override
  Widget build(BuildContext context) {
    final status = game?.status;

    final (subtitle, subtitleColor) = switch (status) {
      'HIDING_PHASE' => (
        myRole == 'SEEKER' ? 'HIDING PHASE' : 'HIDE NOW',
        NexusTheme.warning,
      ),
      'ACTIVE' => (
        eliminated
            ? 'SPECTATING'
            : myRole == 'SEEKER'
                ? (revealActive
                    ? 'HIDERS VISIBLE'
                    : 'HUNTING · $hidersRemaining HIDING')
                : (revealActive ? 'YOU ARE EXPOSED' : 'HIDDEN'),
        eliminated
            ? Colors.white70
            : (revealActive ? NexusTheme.danger : NexusTheme.accent),
      ),
      _ => ('STARTING', Colors.white70),
    };

    final clockLabel = status == 'HIDING_PHASE'
        ? 'HIDING ENDS IN'
        : 'MATCH ENDS IN';

    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.9),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NEXUS',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: NexusTheme.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
              color: subtitleColor,
            ),
          ),
          const SizedBox(height: 10),
          ColoredBox(color: NexusTheme.hairline, child: const SizedBox(height: 1, width: double.infinity)),
          const SizedBox(height: 10),
          Text(
            clockLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 2,
              color: Colors.white54,
            ),
          ),
          Text(
            _formatClock(secondsRemaining),
            style: NexusTheme.readout.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (status == 'ACTIVE' && myRole == 'SEEKER' && revealActive) ...[
            const SizedBox(height: 8),
            Text(
              'Sightings: $sightingsCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (visibilityNotice != null) ...[
            const SizedBox(height: 4),
            Text(
              visibilityNotice!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NexusTheme.danger),
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

/// Static legend explaining the map's markers and zones — "YOU" adapts its
/// color to whichever role you're actually playing this match.
class _LegendPanel extends StatelessWidget {
  const _LegendPanel({required this.myRole});

  final String? myRole;

  @override
  Widget build(BuildContext context) {
    final youColor = myRole == 'SEEKER' ? NexusTheme.danger : NexusTheme.accent;
    final youRoleLabel = switch (myRole) {
      'SEEKER' => 'SEEKER',
      'HIDER' => 'HIDER',
      _ => '',
    };

    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendRow(
            swatch: _LegendDot(color: youColor),
            label: 'YOU',
            sublabel: youRoleLabel.isEmpty ? null : youRoleLabel,
          ),
          const SizedBox(height: 8),
          _LegendRow(
            swatch: _LegendDot(color: NexusTheme.danger),
            label: 'SEEKER',
          ),
          const SizedBox(height: 8),
          _LegendRow(
            swatch: _LegendRing(color: NexusTheme.accent),
            label: 'HIDER',
          ),
          const SizedBox(height: 8),
          _LegendRow(
            swatch: _LegendOutlineSquare(color: NexusTheme.accent),
            label: 'PLAYABLE AREA',
          ),
          const SizedBox(height: 8),
          _LegendRow(
            swatch: _LegendFilledSquare(color: NexusTheme.danger),
            label: 'RESTRICTED',
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.swatch, required this.label, this.sublabel});

  final Widget swatch;
  final String label;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, height: 16, child: swatch),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (sublabel != null)
              Text(
                sublabel!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: Colors.white54,
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendRing extends StatelessWidget {
  const _LegendRing({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

class _LegendOutlineSquare extends StatelessWidget {
  const _LegendOutlineSquare({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(decoration: BoxDecoration(border: Border.all(color: color, width: 2)));
  }
}

class _LegendFilledSquare extends StatelessWidget {
  const _LegendFilledSquare({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.35),
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}
