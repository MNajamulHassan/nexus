import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';

class ProfileRepository {
  const ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'profiles';

  /// Loads the trigger-created profile. Inserts only if the row is missing.
  Future<PlayerProfile> loadCurrent(String userId) async {
    try {
      final existing = await _fetch(userId);
      if (existing != null) {
        return existing;
      }

      // The auth.users trigger usually wins; wait briefly for it.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final afterWait = await _fetch(userId);
      if (afterWait != null) {
        return afterWait;
      }

      return await _insertPlaceholder(userId);
    } on IdentityException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _queryFailure(error);
    } on SocketException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Network error while loading your profile.',
      );
    } on TimeoutException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Timed out while loading your profile.',
      );
    } catch (error) {
      throw IdentityException(
        kind: IdentityErrorKind.profileQuery,
        message: 'Could not load your profile. $error',
      );
    }
  }

  Future<PlayerProfile> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    final validation = ProfileRules.validate(displayName);
    if (validation != null) {
      throw IdentityException(
        kind: IdentityErrorKind.invalidName,
        message: validation,
      );
    }

    try {
      final row = await _client
          .from(_table)
          .update({'display_name': displayName.trim()})
          .eq('id', userId)
          .select()
          .single();
      return PlayerProfile.fromRow(row);
    } on IdentityException {
      rethrow;
    } on PostgrestException catch (error) {
      throw IdentityException(
        kind: IdentityErrorKind.profileUpdate,
        message: 'Could not save your name. ${error.message}',
      );
    } on SocketException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Network error while saving your name.',
      );
    } on TimeoutException {
      throw const IdentityException(
        kind: IdentityErrorKind.network,
        message: 'Timed out while saving your name.',
      );
    } catch (error) {
      throw IdentityException(
        kind: IdentityErrorKind.profileUpdate,
        message: 'Could not save your name. $error',
      );
    }
  }

  Future<PlayerProfile?> _fetch(String userId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return PlayerProfile.fromRow(row);
  }

  Future<PlayerProfile> _insertPlaceholder(String userId) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'id': userId,
            'display_name': ProfileRules.defaultDisplayName,
          })
          .select()
          .single();
      return PlayerProfile.fromRow(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        final raced = await _fetch(userId);
        if (raced != null) {
          return raced;
        }
      }
      throw _queryFailure(error);
    }
  }

  IdentityException _queryFailure(PostgrestException error) {
    return IdentityException(
      kind: IdentityErrorKind.profileQuery,
      message: 'Could not load your profile. ${error.message}',
    );
  }
}
