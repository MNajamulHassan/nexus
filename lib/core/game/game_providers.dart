import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/identity_providers.dart';
import 'game_repository.dart';
import 'lobby_service.dart';

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ref.watch(supabaseClientProvider));
});

final lobbyServiceProvider = Provider<LobbyService>((ref) {
  return LobbyService(ref.watch(gameRepositoryProvider));
});

class HomeNoticeController extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

final homeNoticeProvider = NotifierProvider<HomeNoticeController, String?>(
  HomeNoticeController.new,
);
