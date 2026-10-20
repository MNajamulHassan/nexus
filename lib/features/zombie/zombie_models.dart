import 'dart:math';

import '../../core/location/distance.dart';
import '../../core/maps/map_models.dart';

enum ZombieGameStatus { settingDestination, playing, won, lost }

/// Manhunt-style awareness: zombies don't beeline at you from the start.
/// They patrol until they detect you, investigate your last known spot for
/// a while after losing you, then give up and resume patrolling.
enum ZombieAiState { patrol, investigating, hunting }

class Zombie {
  Zombie({required this.id, required this.position, required this.homeArea})
    : patrolTarget = position;

  static const _patrolSpeedMeters = 1.5;
  static const _investigateSpeedMeters = 3.0;
  static const _huntSpeedMeters = 5.5;
  static const _patrolRadiusMeters = 35.0;
  static const _searchTicks = 5;
  static const _reachedWaypointMeters = 3.0;

  final int id;
  GeoPoint position;
  ZombieAiState aiState = ZombieAiState.patrol;

  /// Center the zombie patrols around while it hasn't noticed the player —
  /// its spawn point, so it doesn't wander off toward a map corner.
  final GeoPoint homeArea;
  GeoPoint patrolTarget;
  GeoPoint? lastKnownPlayerPosition;
  int _searchTicksRemaining = 0;

  final Random _random = Random();

  /// Advances this zombie by one AI tick. [detectionRadiusMeters] is the
  /// effective sight range for this tick — the caller shrinks it when the
  /// player is standing in a safe corridor, so corridors double as cover.
  void tick({
    required GeoPoint playerPosition,
    required double detectionRadiusMeters,
  }) {
    final distanceToPlayer = haversineMeters(
      position.latitude,
      position.longitude,
      playerPosition.latitude,
      playerPosition.longitude,
    );

    if (distanceToPlayer <= detectionRadiusMeters) {
      aiState = ZombieAiState.hunting;
      lastKnownPlayerPosition = playerPosition;
      _searchTicksRemaining = _searchTicks;
    } else if (aiState != ZombieAiState.patrol) {
      _searchTicksRemaining--;
      aiState = _searchTicksRemaining > 0
          ? ZombieAiState.investigating
          : ZombieAiState.patrol;
    }

    switch (aiState) {
      case ZombieAiState.hunting:
        position = _stepToward(position, playerPosition, _huntSpeedMeters);
      case ZombieAiState.investigating:
        final target = lastKnownPlayerPosition ?? patrolTarget;
        position = _stepToward(position, target, _investigateSpeedMeters);
      case ZombieAiState.patrol:
        _patrol();
    }
  }

  void _patrol() {
    final toTarget = haversineMeters(
      position.latitude,
      position.longitude,
      patrolTarget.latitude,
      patrolTarget.longitude,
    );
    if (toTarget <= _reachedWaypointMeters) {
      final angle = _random.nextDouble() * 2 * pi;
      final radius = _random.nextDouble() * _patrolRadiusMeters;
      patrolTarget = _offsetMeters(
        homeArea,
        radius * cos(angle),
        radius * sin(angle),
      );
      return;
    }
    position = _stepToward(position, patrolTarget, _patrolSpeedMeters);
  }

  static GeoPoint _stepToward(GeoPoint from, GeoPoint to, double stepMeters) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos(from.latitude * pi / 180);
    final dx = (to.longitude - from.longitude) * metersPerDegreeLon;
    final dy = (to.latitude - from.latitude) * metersPerDegreeLat;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance <= stepMeters || distance == 0) {
      return to;
    }
    final ratio = stepMeters / distance;
    return GeoPoint(
      longitude: from.longitude + (dx * ratio) / metersPerDegreeLon,
      latitude: from.latitude + (dy * ratio) / metersPerDegreeLat,
    );
  }

  static GeoPoint _offsetMeters(
    GeoPoint origin,
    double eastMeters,
    double northMeters,
  ) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos(origin.latitude * pi / 180);
    return GeoPoint(
      longitude: origin.longitude + eastMeters / metersPerDegreeLon,
      latitude: origin.latitude + northMeters / metersPerDegreeLat,
    );
  }
}
