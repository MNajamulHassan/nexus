import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/debug_config.dart';
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
  Timer? _introTimer;
  Timer? _catchBannerTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<LocationResult>? _locationSub;
  bool _navigatedAway = false;
  bool _showIntro = true;
  bool _showLegend = true;
  String? _catchBanner;

  DateTime? _lastRealFixSentAt;
  DateTime? _lastReportOkAt;
  String? _lastReportError;
  DateTime? _seekerSightingLastSeenAt;

  GeoPoint? _selfLastDrawnPosition;
  GeoPoint? _seekerLastDrawnPosition;
  final Map<String, GeoPoint> _hiderLastDrawnPositions = {};

  static const _navIconId = 'manhunt-nav-triangle';

  MapboxMap? _mapboxMap;
  PolygonAnnotationManager? _polygonManager;
  PolylineAnnotationManager? _boundaryLineManager;
  CircleAnnotationManager? _boundaryNodeManager;
  PolylineAnnotationManager? _catchRadiusManager;
  CircleAnnotationManager? _selfMarkerManager;
  PointAnnotationManager? _selfIconManager;
  CircleAnnotationManager? _hiderMarkerManager;
  CircleAnnotationManager? _seekerMarkerManager;
  PointAnnotationManager? _seekerIconManager;

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
    unawaited(_disableWakelock());
    super.dispose();
  }

  void _stopTimers() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _displayTicker?.cancel();
    _displayTicker = null;
    _introTimer?.cancel();
    _introTimer = null;
    _catchBannerTimer?.cancel();
    _catchBannerTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_locationSub?.cancel());
    _locationSub = null;
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Best-effort; nothing to surface if the platform call fails.
    }
  }

  Future<void> _bootstrap() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Best-effort; the match still works if the screen can sleep.
    }
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
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_sendHeartbeat()),
      );
      unawaited(_tick());
      _introTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) {
          setState(() => _showIntro = false);
        }
      });
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
    final previouslyEliminated = _players
        .where((p) => p.isEliminated)
        .map((p) => p.playerId)
        .toSet();
    setState(() {
      _game = game;
      _players = players;
    });
    final newlyEliminated = players
        .where((p) => p.isEliminated && !previouslyEliminated.contains(p.playerId))
        .toList();
    if (newlyEliminated.isNotEmpty) {
      final name =
          _profiles[newlyEliminated.first.playerId]?.displayName ?? 'A hider';
      _showCatchBanner('$name was caught!');
    }

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
          if (seekerSighting != null) {
            _seekerSighting = seekerSighting;
            _seekerSightingLastSeenAt = DateTime.now();
          } else {
            // The seeker's last fix may just be briefly stale (e.g. a
            // stationary device), not actually gone — keep showing it for
            // a grace window instead of vanishing the marker instantly.
            final lastSeenAt = _seekerSightingLastSeenAt;
            if (lastSeenAt == null ||
                DateTime.now().difference(lastSeenAt) >
                    const Duration(seconds: 45)) {
              _seekerSighting = null;
            }
          }
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
    unawaited(_drawCatchRadius());
  }

  Future<void> _catchHider(String hiderId) async {
    await ref.read(gameRepositoryProvider).attemptCatch(widget.gameId, hiderId);
    unawaited(_tick());
  }

  void _showCatchBanner(String message) {
    _catchBannerTimer?.cancel();
    setState(() => _catchBanner = message);
    _catchBannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _catchBanner = null);
      }
    });
  }

  void _goToResults() {
    if (_navigatedAway) {
      return;
    }
    _navigatedAway = true;
    _stopTimers();
    unawaited(_disableWakelock());
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
          _lastRealFixSentAt = DateTime.now();
          unawaited(_reportLocation(location));
          unawaited(_drawCatchRadius());
        case LocationError(:final message):
          setState(() => _locationNotice = message);
      }
    });
  }

  /// Keeps the server's last-known fix fresh for a device that hasn't
  /// moved enough to trigger a new GPS fix (distanceFilter-gated stream),
  /// so `server_received_at` doesn't go stale just from standing still.
  Future<void> _sendHeartbeat() async {
    if (!mounted || _navigatedAway) {
      return;
    }
    final location = _myLocation;
    if (location == null) {
      return;
    }
    final accuracy = location.accuracyMeters;
    if (accuracy == null || accuracy > 100) {
      return;
    }
    final lastReal = _lastRealFixSentAt;
    if (lastReal != null &&
        DateTime.now().difference(lastReal) < const Duration(seconds: 4)) {
      return;
    }
    await _reportLocation(location);
  }

  Future<void> _reportLocation(AppLocation location) async {
    try {
      await ref
          .read(gameRepositoryProvider)
          .reportLocation(widget.gameId, location);
      if (mounted) {
        setState(() {
          _lastReportOkAt = DateTime.now();
          _lastReportError = null;
        });
      }
    } catch (error) {
      // Next fix/heartbeat retries; a dropped update is not fatal, but it's
      // no longer swallowed outright — the debug overlay can surface it.
      if (mounted) {
        setState(() => _lastReportError = '$error');
      }
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;
    // The built-in scale bar/compass overlap the HUD card; this game needs
    // neither.
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    await _registerNavIcon(map);

    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    _boundaryLineManager = await map.annotations
        .createPolylineAnnotationManager();
    _boundaryNodeManager = await map.annotations
        .createCircleAnnotationManager();
    _catchRadiusManager = await map.annotations
        .createPolylineAnnotationManager();
    _selfMarkerManager = await map.annotations.createCircleAnnotationManager();
    _selfIconManager = await map.annotations.createPointAnnotationManager();
    _hiderMarkerManager = await map.annotations.createCircleAnnotationManager();
    _seekerMarkerManager = await map.annotations
        .createCircleAnnotationManager();
    _seekerIconManager = await map.annotations.createPointAnnotationManager();

    await _drawZones();
    final location = _myLocation;
    if (location != null) {
      await _showSelfMarker(location);
    }
    await _redrawHiders();
    await _redrawSeekerMarker();
    await _drawCatchRadius();
  }

  /// Renders a simple upward-pointing triangle to a raster image once and
  /// registers it as a tintable (SDF) style icon — reused for both the
  /// "you" marker (rotated to heading) and the seeker marker (rotated 180°
  /// to point down), matching the reference design's arrow/triangle shapes
  /// instead of plain circles.
  Future<void> _registerNavIcon(MapboxMap map) async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = Path()
      ..moveTo(size / 2, 0)
      ..lineTo(size - 6, size - 4)
      ..lineTo(size / 2, size * 0.68)
      ..lineTo(6, size - 4)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final styleImage = await StyleImage.fromImage(image);
    await map.addImage(_navIconId, 1.0, styleImage, sdf: true);
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
      final color = isPlayable ? NexusTheme.accent : NexusTheme.restricted;
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

  /// Glowing halo + a rotated nav-triangle icon on top — "you" rotates to
  /// GPS travel heading; the seeker marker (below) is always rotated to
  /// point straight down, matching the reference design.
  Future<void> _createNavMarker(
    CircleAnnotationManager glowManager,
    PointAnnotationManager iconManager,
    Point geometry,
    Color color,
    double rotationDegrees,
  ) async {
    await glowManager.create(
      CircleAnnotationOptions(
        geometry: geometry,
        circleColor: color.toARGB32(),
        circleRadius: 22,
        circleBlur: 1,
        circleOpacity: 0.35,
      ),
    );
    await iconManager.create(
      PointAnnotationOptions(
        geometry: geometry,
        iconImage: _navIconId,
        iconColor: color.toARGB32(),
        iconRotate: rotationDegrees,
        iconSize: 1.0,
      ),
    );
  }

  Future<void> _showSelfMarker(AppLocation location) async {
    final glowManager = _selfMarkerManager;
    final iconManager = _selfIconManager;
    if (glowManager == null || iconManager == null) {
      return;
    }
    final point = _stableGeoPoint(
      _selfLastDrawnPosition,
      GeoPoint(longitude: location.longitude, latitude: location.latitude),
      location.accuracyMeters,
    );
    _selfLastDrawnPosition = point;
    await glowManager.deleteAll();
    await iconManager.deleteAll();
    final color = _myPlayer?.isSeeker == true
        ? NexusTheme.danger
        : NexusTheme.accent;
    await _createNavMarker(
      glowManager,
      iconManager,
      PolygonService.toPoint(point),
      color,
      location.headingDegrees ?? 0,
    );
  }

  /// Suppresses pure GPS jitter: a new fix within min(accuracy, 10)m of the
  /// last position actually drawn is treated as "didn't move," so markers
  /// don't visibly jump around a stationary device's noise.
  GeoPoint _stableGeoPoint(
    GeoPoint? lastDrawn,
    GeoPoint next,
    double? accuracyMeters,
  ) {
    if (lastDrawn == null) {
      return next;
    }
    final threshold = math.min(accuracyMeters ?? 10, 10);
    final moved = _distanceMeters(
      lastDrawn.latitude,
      lastDrawn.longitude,
      next.latitude,
      next.longitude,
    );
    return moved < threshold ? lastDrawn : next;
  }

  /// Simple equirectangular approximation — matches the one already used
  /// by [_geodesicCircle] below. Good enough at match-sized distances.
  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * math.cos(lat1 * math.pi / 180);
    final dLat = (lat2 - lat1) * metersPerDegreeLat;
    final dLon = (lon2 - lon1) * metersPerDegreeLon;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  Future<void> _redrawHiders() async {
    final manager = _hiderMarkerManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    final seen = <String>{};
    final stillTracked = <String>{};
    for (final sighting in _sightings) {
      seen.add(sighting.playerId);
      stillTracked.add(sighting.playerId);
      final point = _stableGeoPoint(
        _hiderLastDrawnPositions[sighting.playerId],
        GeoPoint(longitude: sighting.longitude, latitude: sighting.latitude),
        sighting.accuracyMeters,
      );
      _hiderLastDrawnPositions[sighting.playerId] = point;
      await _createGlowMarker(
        manager,
        PolygonService.toPoint(point),
        NexusTheme.accent,
        hollow: true,
      );
    }
    // A hider close enough to catch is visible too, even outside a reveal
    // window — you're already standing next to them.
    for (final candidate in _catchCandidates) {
      if (!seen.add(candidate.hiderId)) {
        continue;
      }
      stillTracked.add(candidate.hiderId);
      final point = _stableGeoPoint(
        _hiderLastDrawnPositions[candidate.hiderId],
        GeoPoint(longitude: candidate.longitude, latitude: candidate.latitude),
        null, // CatchCandidate carries no accuracy figure.
      );
      _hiderLastDrawnPositions[candidate.hiderId] = point;
      await _createGlowMarker(
        manager,
        PolygonService.toPoint(point),
        NexusTheme.accent,
        hollow: true,
      );
    }
    _hiderLastDrawnPositions.removeWhere((id, _) => !stillTracked.contains(id));
  }

  Future<void> _redrawSeekerMarker() async {
    final glowManager = _seekerMarkerManager;
    final iconManager = _seekerIconManager;
    if (glowManager == null || iconManager == null) {
      return;
    }
    final seeker = _seekerSighting;
    if (seeker == null) {
      _seekerLastDrawnPosition = null;
      await glowManager.deleteAll();
      await iconManager.deleteAll();
      return;
    }
    final point = _stableGeoPoint(
      _seekerLastDrawnPosition,
      GeoPoint(longitude: seeker.longitude, latitude: seeker.latitude),
      null, // SeekerSighting carries no accuracy figure.
    );
    _seekerLastDrawnPosition = point;
    await glowManager.deleteAll();
    await iconManager.deleteAll();
    await _createNavMarker(
      glowManager,
      iconManager,
      PolygonService.toPoint(point),
      NexusTheme.danger,
      180,
    );
  }

  Future<void> _drawCatchRadius() async {
    final manager = _catchRadiusManager;
    if (manager == null) {
      return;
    }
    await manager.deleteAll();
    final location = _myLocation;
    final game = _game;
    if (location == null ||
        game == null ||
        game.status != 'ACTIVE' ||
        _myPlayer?.isSeeker != true) {
      return;
    }
    final center = GeoPoint(
      longitude: location.longitude,
      latitude: location.latitude,
    );
    final ring = PolygonService.closedRing(
      _geodesicCircle(center, game.catchRadiusMeters),
    );
    final line = PolygonService.toLineString(ring);
    if (line == null) {
      return;
    }
    await manager.create(
      PolylineAnnotationOptions(
        geometry: line,
        lineColor: NexusTheme.danger.toARGB32(),
        lineWidth: 8,
        lineBlur: 6,
        lineOpacity: 0.3,
      ),
    );
    await manager.create(
      PolylineAnnotationOptions(
        geometry: line,
        lineColor: NexusTheme.danger.toARGB32(),
        lineWidth: 1.5,
        lineOpacity: 0.8,
      ),
    );
  }

  List<GeoPoint> _geodesicCircle(
    GeoPoint center,
    double radiusMeters, {
    int segments = 48,
  }) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon =
        111320.0 * math.cos(center.latitude * math.pi / 180);
    return [
      for (var i = 0; i < segments; i++)
        () {
          final angle = 2 * math.pi * i / segments;
          final dx = radiusMeters * math.cos(angle);
          final dy = radiusMeters * math.sin(angle);
          return GeoPoint(
            longitude: center.longitude + dx / metersPerDegreeLon,
            latitude: center.latitude + dy / metersPerDegreeLat,
          );
        }(),
    ];
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

  Future<void> _zoomBy(double delta) async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }
    final camera = await map.getCameraState();
    _viewportController.moveTo(
      CameraViewportState(
        center: camera.center,
        zoom: camera.zoom + delta,
        bearing: camera.bearing,
        pitch: camera.pitch,
      ),
      transition: const FlyViewportTransition(duration: Duration(milliseconds: 250)),
    );
  }

  Future<void> _resetNorth() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }
    final camera = await map.getCameraState();
    _viewportController.moveTo(
      CameraViewportState(
        center: camera.center,
        zoom: camera.zoom,
        bearing: 0,
        pitch: camera.pitch,
      ),
      transition: const FlyViewportTransition(duration: Duration(milliseconds: 300)),
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

  /// `acc` own GPS accuracy, `sent` seconds since the last successful
  /// report, `marker` age of the other role's last-known position (seeker
  /// sighting for a hider; freshest hider sighting for a seeker), and the
  /// last report error, if any.
  String _gpsDebugLine() {
    final accuracy = _myLocation?.accuracyMeters;
    final accuracyText = accuracy == null
        ? '—'
        : '${accuracy.toStringAsFixed(0)}m';

    final okAt = _lastReportOkAt;
    final reportAgeText = okAt == null
        ? '—'
        : '${DateTime.now().difference(okAt).inSeconds}s';

    final markerAge = _otherRoleMarkerAgeSeconds;
    final markerText = markerAge == null ? '—' : '${markerAge}s';

    final error = _lastReportError;
    final errorText = error == null
        ? 'none'
        : (error.length > 36 ? '${error.substring(0, 36)}…' : error);

    return 'acc $accuracyText · sent $reportAgeText ago · marker $markerText · $errorText';
  }

  int? get _otherRoleMarkerAgeSeconds {
    if (_myPlayer?.isHider == true) {
      final timestamp = _seekerSighting?.clientTimestamp;
      return timestamp == null
          ? null
          : DateTime.now().difference(timestamp).inSeconds;
    }
    if (_myPlayer?.isSeeker == true && _sightings.isNotEmpty) {
      final newest = _sightings
          .map((s) => s.clientTimestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      return DateTime.now().difference(newest).inSeconds;
    }
    return null;
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
    // No system AppBar during the match — the reference design is a
    // full-bleed tactical map with no title bar at all.
    return Scaffold(body: _buildBody());
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

    final insets = MediaQuery.paddingOf(context);

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
          top: insets.top + 10,
          left: 12,
          right: 12,
          child: AnimatedOpacity(
            opacity: _showIntro ? 0 : 1,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            child: IgnorePointer(
              ignoring: _showIntro,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                      const SizedBox(width: 8),
                      _LegendPanel(
                        myRole: _myPlayer?.role,
                        shown: _showLegend,
                        onToggle: () =>
                            setState(() => _showLegend = !_showLegend),
                      ),
                    ],
                  ),
                  if (showGpsDebug) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _gpsDebugLine(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_catchBanner != null)
          Positioned(
            top: insets.top + 90,
            left: 12,
            right: 12,
            child: _CatchBanner(key: ValueKey(_catchBanner), message: _catchBanner!),
          ),
        if (_catchCandidates.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: insets.bottom + 16,
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
          left: 16,
          bottom: insets.bottom + 16,
          child: _GlassSquareButton(
            icon: Icons.navigation_outlined,
            tooltip: 'Reset north',
            onPressed: _resetNorth,
          ),
        ),
        Positioned(
          right: 16,
          bottom: insets.bottom + 16,
          child: Column(
            children: [
              _ZoomPill(onZoomIn: () => _zoomBy(1), onZoomOut: () => _zoomBy(-1)),
              const SizedBox(height: 10),
              _GlassSquareButton(
                icon: Icons.my_location,
                tooltip: 'Recenter',
                onPressed: _recenter,
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showIntro,
            child: AnimatedOpacity(
              opacity: _showIntro ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: ColoredBox(
                color: NexusTheme.background.withValues(alpha: 0.85),
                child: Center(
                  child: AnimatedScale(
                    scale: _showIntro ? 1 : 0.35,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    child: _IntroTimerCard(
                      secondsRemaining: _secondsRemaining,
                      hidingPhase: _game?.status == 'HIDING_PHASE',
                    ),
                  ),
                ),
              ),
            ),
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

/// Big centered countdown shown for ~1s right after the match screen
/// appears, then scaled/faded down into the compact corner HUD.
class _IntroTimerCard extends StatelessWidget {
  const _IntroTimerCard({
    required this.secondsRemaining,
    required this.hidingPhase,
  });

  final int secondsRemaining;
  final bool hidingPhase;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          NexusTheme.appName,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: NexusTheme.accent,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _formatClock(secondsRemaining),
          style: NexusTheme.readout.copyWith(
            fontSize: 64,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hidingPhase ? 'HIDING PHASE' : 'HUNT BEGINS',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white70,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Transient banner animated in when a hider gets caught.
class _CatchBanner extends StatefulWidget {
  const _CatchBanner({super.key, required this.message});

  final String message;

  @override
  State<_CatchBanner> createState() => _CatchBannerState();
}

class _CatchBannerState extends State<_CatchBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: _slide,
        child: AppCard(
          color: NexusTheme.danger.withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flash_on, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small round button that shows/hides the legend panel — it stays visible
/// so the legend is never permanently lost.
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            NexusTheme.appName,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: NexusTheme.accent,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: subtitleColor,
            ),
          ),
          const SizedBox(height: 6),
          const ColoredBox(
            color: NexusTheme.hairline,
            child: SizedBox(height: 1, width: double.infinity),
          ),
          const SizedBox(height: 6),
          Text(
            clockLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 1.5,
              color: Colors.white54,
            ),
          ),
          Text(
            _formatClock(secondsRemaining),
            style: NexusTheme.readout.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (status == 'ACTIVE' && myRole == 'SEEKER' && revealActive) ...[
            const SizedBox(height: 4),
            Text(
              'Sightings: $sightingsCount',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
          if (visibilityNotice != null) ...[
            const SizedBox(height: 4),
            Text(
              visibilityNotice!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: NexusTheme.danger,
              ),
            ),
          ],
          if (locationNotice != null) ...[
            const SizedBox(height: 4),
            Text(
              locationNotice!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: NexusTheme.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Static legend explaining the map's markers and zones — "YOU" adapts its
/// color to whichever role you're actually playing this match. The toggle
/// to collapse it lives inside the card itself (its header's close icon);
/// collapsed, it's just a small round button in the same spot.
class _LegendPanel extends StatelessWidget {
  const _LegendPanel({
    required this.myRole,
    required this.shown,
    required this.onToggle,
  });

  final String? myRole;
  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!shown) {
      return Material(
        color: NexusTheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onToggle,
          tooltip: 'Show legend',
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
          icon: const Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.white70,
          ),
        ),
      );
    }

    final youColor = myRole == 'SEEKER' ? NexusTheme.danger : NexusTheme.accent;
    final youRoleLabel = switch (myRole) {
      'SEEKER' => 'SEEKER',
      'HIDER' => 'HIDER',
      _ => '',
    };

    // "YOU" already states your own role — don't also list a separate
    // identical-looking row for it below (that was the "legend isn't
    // accurate" duplicate: a seeker would see a red triangle twice).
    final otherRoleRow = myRole == 'SEEKER'
        ? _LegendRow(swatch: _LegendRing(color: NexusTheme.accent), label: 'HIDER')
        : _LegendRow(
            swatch: _LegendTriangle(color: NexusTheme.danger),
            label: 'SEEKER',
          );

    return AppCard(
      color: NexusTheme.surface.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LEGEND',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: NexusTheme.dimText,
                ),
              ),
              GestureDetector(
                onTap: onToggle,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 13, color: Colors.white54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _LegendRow(
            swatch: _LegendTriangle(color: youColor),
            label: 'YOU',
            sublabel: youRoleLabel.isEmpty ? null : youRoleLabel,
          ),
          const SizedBox(height: 6),
          otherRoleRow,
          const SizedBox(height: 6),
          _LegendRow(
            swatch: _LegendOutlineSquare(color: NexusTheme.accent),
            label: 'PLAYABLE',
          ),
          const SizedBox(height: 6),
          _LegendRow(
            swatch: _LegendFilledSquare(color: NexusTheme.restricted),
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
        SizedBox(width: 12, height: 12, child: swatch),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 1.2,
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

/// Matches the on-map nav-triangle marker shape exactly, so the legend
/// icon and the actual marker always look the same.
class _LegendTriangle extends StatelessWidget {
  const _LegendTriangle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TrianglePainter(color));
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
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

/// Dark-glass square icon button — bottom-left reset-north / bottom-right
/// recenter controls.
class _GlassSquareButton extends StatelessWidget {
  const _GlassSquareButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexusTheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: NexusTheme.accent),
      ),
    );
  }
}

/// Dark-glass vertical zoom pill with +/- separated by a divider.
class _ZoomPill extends StatelessWidget {
  const _ZoomPill({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexusTheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomIn,
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add, color: NexusTheme.accent),
          ),
          const ColoredBox(
            color: NexusTheme.hairline,
            child: SizedBox(height: 1, width: 32),
          ),
          IconButton(
            onPressed: onZoomOut,
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove, color: NexusTheme.accent),
          ),
        ],
      ),
    );
  }
}
