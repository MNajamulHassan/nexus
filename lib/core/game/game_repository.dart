import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/game.dart';
import '../../models/game_config.dart';
import '../auth/auth_models.dart';
import '../location/location_models.dart';
import '../maps/map_models.dart';
import '../maps/polygon_service.dart';
import 'lobby_realtime.dart';

class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;
  final Map<String, RealtimeChannel> _lobbyChannels = {};

  static String lobbyChannelName(String gameId) => 'lobby:$gameId';

  Future<GameRecord> createGame(GameConfig config) async {
    try {
      final raw = await _client.rpc(
        'create_game',
        params: {
          'p_mode': config.modeWireValue,
          'p_hiding_duration_seconds': config.hidingDurationSeconds,
          'p_match_duration_seconds': config.matchDurationSeconds,
          'p_catch_radius_meters': config.catchRadiusMeters,
          'p_reveal_interval_seconds': config.revealIntervalSeconds,
          'p_reveal_duration_seconds': config.revealDurationSeconds,
          'p_taunts_enabled': config.tauntsEnabled,
          'p_settings': <String, dynamic>{},
        },
      );
      return GameRecord.fromRow(_asRow(raw, 'create_game'));
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.create, 'Could not create the lobby.');
    }
  }

  Future<void> replaceGameZones({
    required String gameId,
    required GameConfig config,
  }) async {
    try {
      await _client.rpc(
        'replace_game_zones',
        params: {
          'p_game_id': gameId,
          'p_zones': _zonesPayload(config),
        },
      );
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(
        error,
        LobbyErrorKind.zones,
        'Could not save the play area.',
      );
    }
  }

  Future<GamePlayerRecord> joinGame(String joinCode) async {
    if (_client.auth.currentUser == null) {
      throw const LobbyException(
        kind: LobbyErrorKind.auth,
        message: 'You are not signed in. Restart the app and try again.',
      );
    }

    try {
      final raw = await _client.rpc(
        'join_game',
        params: {'p_join_code': joinCode},
      );
      final membership = GamePlayerRecord.fromRow(_asRow(raw, 'join_game'));
      await _broadcastLobbyChanged(membership.gameId, 'joined');
      return membership;
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _mapJoin(error);
    }
  }

  Future<void> leaveGame(String gameId) async {
    if (_client.auth.currentUser == null) {
      throw const LobbyException(
        kind: LobbyErrorKind.auth,
        message: 'You are not signed in. Restart the app and try again.',
      );
    }

    try {
      await _client.rpc('leave_game', params: {'p_game_id': gameId});
      await _broadcastLobbyChanged(gameId, 'left');
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _mapLeave(error);
    }
  }

  Future<void> cancelLobby(String gameId) async {
    try {
      await _client.rpc('cancel_lobby', params: {'p_game_id': gameId});
      await _broadcastLobbyChanged(gameId, 'cancelled');
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(
        error,
        LobbyErrorKind.cancel,
        'Could not remove the incomplete lobby.',
      );
    }
  }

  Future<GameRecord> fetchGame(String gameId) async {
    try {
      final row = await _client
          .from('games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (row == null) {
        throw const LobbyException(
          kind: LobbyErrorKind.cancel,
          message: 'This lobby was cancelled.',
        );
      }
      return GameRecord.fromRow(row);
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.load, 'Could not load the lobby.');
    }
  }

  Future<GameRecord?> fetchGameOrNull(String gameId) async {
    try {
      final row = await _client
          .from('games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return GameRecord.fromRow(row);
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.load, 'Could not load the lobby.');
    }
  }

  LobbyRealtimeSubscription subscribeLobby({
    required String gameId,
    required void Function() onChange,
    required void Function() onGameDeleted,
    required void Function(LobbyRealtimeStatus status) onStatus,
  }) {
    final topic = lobbyChannelName(gameId);
    final previous = _lobbyChannels.remove(topic);
    if (previous != null) {
      unawaited(_client.removeChannel(previous));
    }

    final channel = _client
        .channel(topic)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'game_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: gameId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              onGameDeleted();
            } else {
              onChange();
            }
          },
        )
        .onBroadcast(
          event: 'lobby_changed',
          callback: (payload) {
            if (_broadcastReason(payload) == 'cancelled') {
              onGameDeleted();
            } else {
              onChange();
            }
          },
        );

    _lobbyChannels[topic] = channel;
    onStatus(LobbyRealtimeStatus.connecting);
    channel.subscribe((status, error) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          onStatus(LobbyRealtimeStatus.connected);
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.channelError:
          onStatus(
            error == null
                ? LobbyRealtimeStatus.reconnecting
                : LobbyRealtimeStatus.error,
          );
        case RealtimeSubscribeStatus.closed:
          onStatus(LobbyRealtimeStatus.reconnecting);
      }
    });

    return LobbyRealtimeSubscription(() async {
      _lobbyChannels.remove(topic);
      await _client.removeChannel(channel);
    });
  }

  Future<void> _broadcastLobbyChanged(String gameId, String reason) async {
    final topic = lobbyChannelName(gameId);
    final payload = {'reason': reason, 'game_id': gameId};
    final existing = _lobbyChannels[topic];
    if (existing != null) {
      try {
        await existing.sendBroadcastMessage(
          event: 'lobby_changed',
          payload: payload,
        );
      } catch (_) {}
      return;
    }

    final ephemeral = _client.channel(topic);
    try {
      final joined = Completer<void>();
      ephemeral.subscribe((status, error) {
        if (joined.isCompleted) {
          return;
        }
        if (status == RealtimeSubscribeStatus.subscribed) {
          joined.complete();
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          joined.completeError(error ?? status);
        }
      });
      await joined.future.timeout(const Duration(seconds: 2));
      await ephemeral.sendBroadcastMessage(
        event: 'lobby_changed',
        payload: payload,
      );
    } catch (_) {
      // Postgres changes or the lobby poll still refresh other devices.
    } finally {
      await _client.removeChannel(ephemeral);
    }
  }

  String? _broadcastReason(Map<String, dynamic> payload) {
    final direct = payload['reason'];
    if (direct is String) {
      return direct;
    }
    final nested = payload['payload'];
    if (nested is Map && nested['reason'] is String) {
      return nested['reason'] as String;
    }
    return null;
  }

  Future<List<GamePlayerRecord>> fetchPlayers(String gameId) async {
    try {
      final rows = await _client
          .from('game_players')
          .select()
          .eq('game_id', gameId)
          .order('joined_at');
      return [
        for (final row in rows as List<dynamic>)
          GamePlayerRecord.fromRow(Map<String, dynamic>.from(row as Map)),
      ];
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.load, 'Could not load lobby players.');
    }
  }

  Future<Map<String, PlayerProfile>> fetchProfiles(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) {
      return const {};
    }

    try {
      final rows = await _client
          .from('profiles')
          .select()
          .inFilter('id', unique);
      return {
        for (final row in rows as List<dynamic>)
          (row as Map)['id'] as String: PlayerProfile.fromRow(
            Map<String, dynamic>.from(row),
          ),
      };
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.load, 'Could not load player names.');
    }
  }

  Future<GameRecord> startGame(String gameId) async {
    try {
      final raw = await _client.rpc('start_game', params: {'p_game_id': gameId});
      return GameRecord.fromRow(_asRow(raw, 'start_game'));
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.match, 'Could not start the match.');
    }
  }

  Future<GameRecord> syncMatchState(String gameId) async {
    try {
      final raw = await _client.rpc(
        'sync_match_state',
        params: {'p_game_id': gameId},
      );
      return GameRecord.fromRow(_asRow(raw, 'sync_match_state'));
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.match, 'Could not sync the match.');
    }
  }

  Future<List<HiderSighting>> fetchSeekerView(String gameId) async {
    try {
      final rows = await _client.rpc(
        'fetch_seeker_view',
        params: {'p_game_id': gameId},
      );
      return [
        for (final row in rows as List<dynamic>)
          HiderSighting.fromRow(Map<String, dynamic>.from(row as Map)),
      ];
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.match, 'Could not load sightings.');
    }
  }

  Future<void> reportLocation(String gameId, AppLocation location) async {
    try {
      await _client.rpc(
        'upsert_player_location',
        params: {
          'p_game_id': gameId,
          'p_latitude': location.latitude,
          'p_longitude': location.longitude,
          'p_accuracy_meters': location.accuracyMeters ?? 9999.0,
          'p_speed': location.speedMetersPerSecond,
          'p_client_timestamp': location.timestamp.toUtc().toIso8601String(),
        },
      );
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.match, 'Could not report location.');
    }
  }

  Future<List<GameZone>> fetchZones(String gameId) async {
    try {
      final rows = await _client.rpc(
        'fetch_game_zones',
        params: {'p_game_id': gameId},
      );
      final zones = <GameZone>[];
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final type = switch (map['type'] as String?) {
          'PLAYABLE' => ZoneType.playable,
          'RESTRICTED' => ZoneType.restricted,
          _ => null,
        };
        if (type == null) {
          continue;
        }
        final vertices = _verticesFromGeoJson(map['geojson'] as String);
        zones.add(
          GameZone(
            id: map['id'] as String,
            type: type,
            polygon: MapPolygon(id: map['id'] as String, vertices: vertices),
            name: map['name'] as String?,
          ),
        );
      }
      return zones;
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.match, 'Could not load the play area.');
    }
  }

  List<GeoPoint> _verticesFromGeoJson(String geojson) {
    final decoded = jsonDecode(geojson) as Map<String, dynamic>;
    final rings = decoded['coordinates'] as List<dynamic>;
    final ring = (rings.first as List<dynamic>)
        .map((pair) {
          final coords = pair as List<dynamic>;
          return GeoPoint(
            longitude: (coords[0] as num).toDouble(),
            latitude: (coords[1] as num).toDouble(),
          );
        })
        .toList();
    if (ring.length > 1 &&
        ring.first.longitude == ring.last.longitude &&
        ring.first.latitude == ring.last.latitude) {
      ring.removeLast();
    }
    return ring;
  }

  List<Map<String, dynamic>> _zonesPayload(GameConfig config) {
    return [
      {
        'type': 'PLAYABLE',
        'name': 'Playable area',
        'geometry': PolygonService.toGeoJsonPolygon(
          config.playablePolygon.vertices,
        ),
        'rules': <String, dynamic>{},
      },
      for (var i = 0; i < config.restrictedPolygons.length; i++)
        {
          'type': 'RESTRICTED',
          'name': 'Restricted ${i + 1}',
          'geometry': PolygonService.toGeoJsonPolygon(
            config.restrictedPolygons[i].vertices,
          ),
          'rules': <String, dynamic>{},
        },
    ];
  }

  Map<String, dynamic> _asRow(dynamic raw, String rpc) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is List && raw.isNotEmpty) {
      return _asRow(raw.first, rpc);
    }
    throw LobbyException(
      kind: LobbyErrorKind.create,
      message: '$rpc did not return a game row.',
    );
  }

  LobbyException _map(Object error, LobbyErrorKind kind, String fallback) {
    if (error is SocketException || error is TimeoutException) {
      return LobbyException(
        kind: LobbyErrorKind.network,
        message: 'Network error. Check your connection and try again.',
      );
    }
    if (error is PostgrestException) {
      final detail = error.message.trim();
      return LobbyException(
        kind: kind,
        message: detail.isEmpty ? fallback : '$fallback $detail',
      );
    }
    return LobbyException(kind: kind, message: '$fallback $error');
  }

  LobbyException _mapJoin(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return const LobbyException(
        kind: LobbyErrorKind.network,
        message: 'Network error. Check your connection and try again.',
      );
    }

    if (error is PostgrestException) {
      final detail = error.message.toLowerCase();
      if (detail.contains('not authenticated') ||
          detail.contains('profile required')) {
        return const LobbyException(
          kind: LobbyErrorKind.auth,
          message: 'You are not signed in. Restart the app and try again.',
        );
      }
      if (detail.contains('not found')) {
        return const LobbyException(
          kind: LobbyErrorKind.join,
          message: 'No lobby uses that code.',
        );
      }
      if (detail.contains('not joinable')) {
        return const LobbyException(
          kind: LobbyErrorKind.join,
          message: 'That lobby has already started.',
        );
      }
      final message = error.message.trim();
      return LobbyException(
        kind: LobbyErrorKind.join,
        message: message.isEmpty ? 'Could not join the lobby.' : message,
      );
    }

    return LobbyException(
      kind: LobbyErrorKind.join,
      message: 'Could not join the lobby. $error',
    );
  }

  LobbyException _mapLeave(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return const LobbyException(
        kind: LobbyErrorKind.network,
        message: 'Network error. Check your connection and try again.',
      );
    }
    if (error is PostgrestException) {
      final detail = error.message.toLowerCase();
      if (detail.contains('not authenticated')) {
        return const LobbyException(
          kind: LobbyErrorKind.auth,
          message: 'You are not signed in. Restart the app and try again.',
        );
      }
      if (detail.contains('host cannot leave')) {
        return const LobbyException(
          kind: LobbyErrorKind.cancel,
          message: 'Hosts cancel the lobby instead of leaving.',
        );
      }
      if (detail.contains('after the match')) {
        return const LobbyException(
          kind: LobbyErrorKind.join,
          message: 'Cannot leave after the match has started.',
        );
      }
      final message = error.message.trim();
      return LobbyException(
        kind: LobbyErrorKind.load,
        message: message.isEmpty ? 'Could not leave the lobby.' : message,
      );
    }
    return LobbyException(
      kind: LobbyErrorKind.load,
      message: 'Could not leave the lobby. $error',
    );
  }
}
