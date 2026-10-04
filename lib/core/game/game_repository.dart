import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/game.dart';
import '../../models/game_config.dart';
import '../auth/auth_models.dart';
import '../maps/polygon_service.dart';

class GameRepository {
  const GameRepository(this._client);

  final SupabaseClient _client;

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

  Future<void> cancelLobby(String gameId) async {
    try {
      await _client.rpc('cancel_lobby', params: {'p_game_id': gameId});
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
      final row = await _client.from('games').select().eq('id', gameId).single();
      return GameRecord.fromRow(row);
    } on LobbyException {
      rethrow;
    } catch (error) {
      throw _map(error, LobbyErrorKind.load, 'Could not load the lobby.');
    }
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
}
