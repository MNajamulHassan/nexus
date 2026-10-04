import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/game/join_code.dart';

void main() {
  test('normalizes whitespace and case', () {
    expect(JoinCode.normalize('  ab12cd  '), 'AB12CD');
    expect(JoinCode.normalize('ab 12 cd'), 'AB12CD');
  });

  test('rejects malformed codes before RPC', () {
    expect(JoinCode.validate(''), isNotNull);
    expect(JoinCode.validate('abc'), isNotNull);
    expect(JoinCode.validate('ABC12'), isNotNull);
    expect(JoinCode.validate('ABC12!'), isNotNull);
    expect(JoinCode.validate('AB12CD'), isNull);
    expect(JoinCode.validate('  ab12cd '), isNull);
  });
}
