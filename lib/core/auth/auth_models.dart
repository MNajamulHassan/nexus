class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.displayName,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final DateTime createdAt;

  factory PlayerProfile.fromRow(Map<String, dynamic> row) {
    return PlayerProfile(
      id: row['id'] as String,
      displayName: (row['display_name'] as String?)?.trim() ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

class PlayerIdentity {
  const PlayerIdentity({required this.userId, required this.profile});

  final String userId;
  final PlayerProfile profile;

  bool get needsDisplayName => ProfileRules.isPlaceholder(profile.displayName);
}

enum IdentityErrorKind {
  anonymousAuthDisabled,
  network,
  auth,
  profileQuery,
  profileUpdate,
  invalidName,
  unknown,
}

class IdentityException implements Exception {
  const IdentityException({required this.kind, required this.message});

  final IdentityErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

abstract final class ProfileRules {
  static const defaultDisplayName = 'Player';
  static const minLength = 2;
  static const maxLength = 24;

  static bool isPlaceholder(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ||
        trimmed.toLowerCase() == defaultDisplayName.toLowerCase();
  }

  static String? validate(String raw) {
    final name = raw.trim();
    if (name.isEmpty) {
      return 'Enter a display name.';
    }
    if (name.length < minLength || name.length > maxLength) {
      return 'Name must be $minLength to $maxLength characters.';
    }
    if (isPlaceholder(name)) {
      return 'Choose a name other than $defaultDisplayName.';
    }
    return null;
  }
}
