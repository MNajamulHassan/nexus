import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';
import 'auth_service.dart';
import 'profile_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final playerIdentityProvider =
    AsyncNotifierProvider<PlayerIdentityController, PlayerIdentity>(
      PlayerIdentityController.new,
    );

class PlayerIdentityController extends AsyncNotifier<PlayerIdentity> {
  @override
  Future<PlayerIdentity> build() {
    return _bootstrap();
  }

  Future<PlayerIdentity> _bootstrap() async {
    final user = await ref.read(authServiceProvider).ensureSignedIn();
    final profile = await ref.read(profileRepositoryProvider).loadCurrent(user.id);
    return PlayerIdentity(userId: user.id, profile: profile);
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }

  /// Updates the current user's display name. Failures do not clear the session.
  Future<void> updateDisplayName(String raw) async {
    final current = await future;
    final profile = await ref
        .read(profileRepositoryProvider)
        .updateDisplayName(userId: current.userId, displayName: raw);
    state = AsyncData(PlayerIdentity(userId: current.userId, profile: profile));
  }
}
