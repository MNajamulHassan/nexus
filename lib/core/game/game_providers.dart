import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game.dart';
import '../auth/identity_providers.dart';
import 'game_repository.dart';
import 'lobby_service.dart';

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ref.watch(supabaseClientProvider));
});

final lobbyServiceProvider = Provider<LobbyService>((ref) {
  return LobbyService(ref.watch(gameRepositoryProvider));
});

final lobbyProvider = FutureProvider.family<LobbySnapshot, String>((
  ref,
  gameId,
) {
  return ref.watch(lobbyServiceProvider).loadLobby(gameId);
});
