import 'game_config.dart';

class GameRecord {
  const GameRecord({
    required this.id,
    required this.hostId,
    required this.joinCode,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.hidingDurationSeconds,
    required this.matchDurationSeconds,
    required this.catchRadiusMeters,
    required this.revealIntervalSeconds,
    required this.revealDurationSeconds,
    required this.tauntsEnabled,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String hostId;
  final String joinCode;
  final GameMode mode;
  final String status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int hidingDurationSeconds;
  final int matchDurationSeconds;
  final double catchRadiusMeters;
  final int revealIntervalSeconds;
  final int revealDurationSeconds;
  final bool tauntsEnabled;

  factory GameRecord.fromRow(Map<String, dynamic> row) {
    final mode = GameConfig.modeFromWire(row['mode'] as String? ?? '');
    if (mode == null) {
      throw FormatException('Unknown game mode: ${row['mode']}');
    }

    return GameRecord(
      id: row['id'] as String,
      hostId: row['host_id'] as String,
      joinCode: row['join_code'] as String,
      mode: mode,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      startedAt: _optionalDate(row['started_at']),
      endedAt: _optionalDate(row['ended_at']),
      hidingDurationSeconds: _asInt(row['hiding_duration_seconds']),
      matchDurationSeconds: _asInt(row['match_duration_seconds']),
      catchRadiusMeters: _asDouble(row['catch_radius_meters']),
      revealIntervalSeconds: _asInt(row['reveal_interval_seconds']),
      revealDurationSeconds: _asInt(row['reveal_duration_seconds']),
      tauntsEnabled: row['taunts_enabled'] as bool? ?? true,
    );
  }

  String get modeLabel => GameConfig.modeDisplayName(mode);
}

class GamePlayerRecord {
  const GamePlayerRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.status,
    required this.joinedAt,
    this.role,
    this.caughtAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String status;
  final DateTime joinedAt;
  final String? role;
  final DateTime? caughtAt;

  bool get isSeeker => role == 'SEEKER';
  bool get isHider => role == 'HIDER';
  bool get isEliminated => status == 'ELIMINATED';

  factory GamePlayerRecord.fromRow(Map<String, dynamic> row) {
    return GamePlayerRecord(
      id: row['id'] as String,
      gameId: row['game_id'] as String,
      playerId: row['player_id'] as String,
      status: row['status'] as String,
      joinedAt: DateTime.parse(row['joined_at'] as String),
      role: row['role'] as String?,
      caughtAt: _optionalDate(row['caught_at']),
    );
  }
}

/// A hider's location as surfaced to the seeker, only during a reveal window.
class HiderSighting {
  const HiderSighting({
    required this.playerId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.clientTimestamp,
  });

  final String playerId;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime clientTimestamp;

  factory HiderSighting.fromRow(Map<String, dynamic> row) {
    return HiderSighting(
      playerId: row['player_id'] as String,
      latitude: _asDouble(row['latitude']),
      longitude: _asDouble(row['longitude']),
      accuracyMeters: row['accuracy_meters'] == null
          ? null
          : _asDouble(row['accuracy_meters']),
      clientTimestamp: DateTime.parse(row['client_timestamp'] as String),
    );
  }
}

/// The seeker's live position, always visible to hiders while the hunt is
/// active — the opposite of [HiderSighting], which is reveal-window-gated.
class SeekerSighting {
  const SeekerSighting({
    required this.latitude,
    required this.longitude,
    required this.clientTimestamp,
  });

  final double latitude;
  final double longitude;
  final DateTime clientTimestamp;

  factory SeekerSighting.fromRow(Map<String, dynamic> row) {
    return SeekerSighting(
      latitude: _asDouble(row['latitude']),
      longitude: _asDouble(row['longitude']),
      clientTimestamp: DateTime.parse(row['client_timestamp'] as String),
    );
  }
}

/// A hider the seeker is currently close enough to catch, per the server's
/// proximity check. Never carries raw coordinates — only distance.
class CatchCandidate {
  const CatchCandidate({required this.hiderId, required this.distanceMeters});

  final String hiderId;
  final double distanceMeters;

  factory CatchCandidate.fromRow(Map<String, dynamic> row) {
    return CatchCandidate(
      hiderId: row['hider_id'] as String,
      distanceMeters: _asDouble(row['distance_meters']),
    );
  }
}

class LobbyPlayer {
  const LobbyPlayer({
    required this.player,
    required this.displayName,
    required this.isHost,
  });

  final GamePlayerRecord player;
  final String displayName;
  final bool isHost;
}

class LobbySnapshot {
  const LobbySnapshot({
    required this.game,
    required this.hostName,
    required this.players,
  });

  final GameRecord game;
  final String hostName;
  final List<LobbyPlayer> players;
}

enum LobbyRealtimeStatus { connecting, connected, reconnecting, error }

class LobbyView {
  const LobbyView({
    required this.snapshot,
    required this.realtime,
    this.cancelled = false,
  });

  final LobbySnapshot snapshot;
  final LobbyRealtimeStatus realtime;
  final bool cancelled;

  LobbyView copyWith({
    LobbySnapshot? snapshot,
    LobbyRealtimeStatus? realtime,
    bool? cancelled,
  }) {
    return LobbyView(
      snapshot: snapshot ?? this.snapshot,
      realtime: realtime ?? this.realtime,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

enum LobbyErrorKind {
  validation,
  create,
  join,
  zones,
  cancel,
  load,
  auth,
  network,
  match,
  unknown,
}

class LobbyException implements Exception {
  const LobbyException({required this.kind, required this.message});

  final LobbyErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String);
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.parse(value.toString());
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.parse(value.toString());
}
