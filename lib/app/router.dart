import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/gps_test/gps_test_screen.dart';
import '../features/home/home_screen.dart';
import '../features/map/map_screen.dart';
import '../features/map_editor/map_editor_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
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
        path: '/map-editor',
        name: 'mapEditor',
        builder: (context, state) => const MapEditorScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
