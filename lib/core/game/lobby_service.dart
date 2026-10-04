import '../../models/game.dart';
import '../../models/game_config.dart';
import 'game_repository.dart';
import 'join_code.dart';

class LobbyService {
  const LobbyService(this._repository);

  final GameRepository _repository;

  Future<LobbySnapshot> createLobby(GameConfig config) async {
    final validation = config.validateSelf();
    if (validation != null) {
      throw LobbyException(kind: LobbyErrorKind.validation, message: validation);
    }

    final game = await _repository.createGame(config);

    try {
      await _repository.replaceGameZones(gameId: game.id, config: config);
    } catch (zoneError) {
      var cancelled = false;
      try {
        await _repository.cancelLobby(game.id);
        cancelled = true;
      } catch (_) {
        cancelled = false;
      }

      if (cancelled) {
        throw LobbyException(
          kind: LobbyErrorKind.zones,
          message:
              'The play area could not be saved, so the incomplete lobby '
              'was removed. Try Create Lobby again. $zoneError',
        );
      }

      throw LobbyException(
        kind: LobbyErrorKind.zones,
        message:
            'The play area could not be saved. Lobby ${game.joinCode} was '
            'left without a valid area. Apply the cancel_lobby migration '
            'or discard this lobby and try again. $zoneError',
      );
    }

    return loadLobby(game.id);
  }

  /// Calls join_game. Existing membership is success and returns that game id.
  Future<String> joinLobby(String rawCode) async {
    final invalid = JoinCode.validate(rawCode);
    if (invalid != null) {
      throw LobbyException(kind: LobbyErrorKind.validation, message: invalid);
    }

    final membership = await _repository.joinGame(JoinCode.normalize(rawCode));
    return membership.gameId;
  }

  Future<void> leaveLobby(String gameId) {
    return _repository.leaveGame(gameId);
  }

  Future<void> cancelLobby(String gameId) {
    return _repository.cancelLobby(gameId);
  }

  Future<bool> lobbyExists(String gameId) async {
    return await _repository.fetchGameOrNull(gameId) != null;
  }

  Future<LobbySnapshot> loadLobby(String gameId) async {
    final game = await _repository.fetchGame(gameId);
    final players = await _repository.fetchPlayers(gameId);
    final profiles = await _repository.fetchProfiles([
      game.hostId,
      for (final player in players) player.playerId,
    ]);

    final hostName = profiles[game.hostId]?.displayName ?? 'Host';
    return LobbySnapshot(
      game: game,
      hostName: hostName,
      players: [
        for (final player in players)
          LobbyPlayer(
            player: player,
            displayName: profiles[player.playerId]?.displayName ?? 'Player',
            isHost: player.playerId == game.hostId,
          ),
      ],
    );
  }
}
