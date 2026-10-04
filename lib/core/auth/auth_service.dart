import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';

class AuthService {
  const AuthService(this._client);

  final SupabaseClient _client;

  /// Reuses a persisted session when one exists; otherwise signs in anonymously.
  /// [User.id] is the canonical player id.
  Future<User> ensureSignedIn() async {
    try {
      final existing = await _existingSession();
      if (existing != null) {
        return existing.user;
      }

      final response = await _client.auth.signInAnonymously();
      final user =
          response.session?.user ?? response.user ?? _client.auth.currentUser;
      if (user == null) {
        throw const IdentityException(
          kind: IdentityErrorKind.auth,
          message: 'Anonymous sign-in did not return a user.',
        );
      }
      return user;
    } on IdentityException {
      rethrow;
    } on AuthException catch (error) {
      throw mapAuthException(error);
    } on SocketException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Network error while signing in. Check your connection.',
      );
    } on TimeoutException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Sign-in timed out. Check your connection.',
      );
    } catch (error) {
      throw IdentityException(
        kind: IdentityErrorKind.unknown,
        message: 'Sign-in failed. $error',
      );
    }
  }

  Future<Session?> _existingSession() async {
    final current = _client.auth.currentSession;
    if (current == null) {
      return null;
    }

    try {
      return await _client.auth.getSession() ?? current;
    } on AuthException {
      if (current.isExpired) {
        return null;
      }
      return current;
    }
  }

  static IdentityException mapAuthException(AuthException error) {
    final code = error.code?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();
    final anonymousDisabled =
        code == 'anonymous_provider_disabled' ||
        (message.contains('anonymous') &&
            (message.contains('disabled') || message.contains('not enabled')));

    if (anonymousDisabled) {
      return const IdentityException(
        kind: IdentityErrorKind.anonymousAuthDisabled,
        message:
            'Anonymous sign-in is disabled. Enable the Anonymous provider '
            'in the Supabase Auth settings for this project.',
      );
    }

    if (error is AuthRetryableFetchException) {
      return const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Network error while signing in. Check your connection.',
      );
    }

    return IdentityException(
      kind: IdentityErrorKind.auth,
      message: error.message.isEmpty ? 'Authentication failed.' : error.message,
    );
  }
}
