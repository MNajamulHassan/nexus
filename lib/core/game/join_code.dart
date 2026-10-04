abstract final class JoinCode {
  static final _allowed = RegExp(r'^[A-Z0-9]{6}$');

  /// Trim, drop internal whitespace, then uppercase.
  static String normalize(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static String? validate(String raw) {
    final code = normalize(raw);
    if (code.isEmpty) {
      return 'Enter a 6-character join code.';
    }
    if (!_allowed.hasMatch(code)) {
      return 'Join codes are 6 letters or numbers.';
    }
    return null;
  }
}
