import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/identity_providers.dart';
import '../features/game_create/create_game_screen.dart';
import '../features/gps_test/gps_test_screen.dart';
import '../features/home/home_screen.dart';
import '../features/join_game/join_game_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/map/map_screen.dart';
import '../features/map_editor/map_editor_screen.dart';
import '../features/match/match_screen.dart';
import '../features/onboarding/boot_screen.dart';
import '../features/onboarding/choose_name_screen.dart';
import '../features/results/results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(playerIdentityProvider, (_, _) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/boot',
    refreshListenable: refresh,
    redirect: (context, state) {
      final identity = ref.read(playerIdentityProvider);
      final location = state.matchedLocation;

      if (identity.isLoading || identity.hasError) {
        return location == '/boot' ? null : '/boot';
      }

      final session = identity.requireValue;
      if (session.needsDisplayName) {
        return location == '/choose-name' ? null : '/choose-name';
      }

      if (location == '/boot') {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/boot',
        name: 'boot',
        builder: (context, state) => const BootScreen(),
      ),
      GoRoute(
        path: '/choose-name',
        name: 'chooseName',
        builder: (context, state) => const ChooseNameScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/gps-test',
        name: 'gpsTest',
        builder: (context, state) => const GpsTestScreen(),
      ),
      GoRoute(
        path: '/map-test',
        name: 'mapTest',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/create-game',
        name: 'createGame',
        builder: (context, state) => const CreateGameScreen(),
      ),
      GoRoute(
        path: '/join-game',
        name: 'joinGame',
        builder: (context, state) => const JoinGameScreen(),
      ),
      GoRoute(
        path: '/lobby/:gameId',
        name: 'lobby',
        builder: (context, state) {
          final gameId = state.pathParameters['gameId'] ?? '';
          return LobbyScreen(gameId: gameId);
        },
      ),
      GoRoute(
        path: '/map-editor',
        name: 'mapEditor',
        builder: (context, state) => const MapEditorScreen(),
      ),
      GoRoute(
        path: '/match/:gameId',
        name: 'match',
        builder: (context, state) {
          final gameId = state.pathParameters['gameId'] ?? '';
          return MatchScreen(gameId: gameId);
        },
      ),
      GoRoute(
        path: '/results/:gameId',
        name: 'results',
        builder: (context, state) {
          final gameId = state.pathParameters['gameId'] ?? '';
          return ResultsScreen(gameId: gameId);
        },
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
