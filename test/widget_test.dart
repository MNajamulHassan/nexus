import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/app/app.dart';
import 'package:nexus/core/auth/auth_models.dart';
import 'package:nexus/core/auth/identity_providers.dart';

class _ReadyIdentityController extends PlayerIdentityController {
  @override
  Future<PlayerIdentity> build() async {
    return PlayerIdentity(
      userId: 'test-user',
      profile: PlayerProfile(
        id: 'test-user',
        displayName: 'Tester',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }
}

void main() {
  testWidgets('Home screen shows title and game actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerIdentityProvider.overrideWith(_ReadyIdentityController.new),
        ],
        child: const NexusApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MANHUNT'), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
    expect(find.text('Edit Name'), findsOneWidget);
    expect(find.text('Create Game'), findsOneWidget);
    expect(find.text('Join Game'), findsOneWidget);
    expect(find.text('Zombie Mode (Solo)'), findsOneWidget);

    await tester.tap(find.byTooltip('Debug tools'));
    await tester.pumpAndSettle();

    expect(find.text('GPS Test'), findsOneWidget);
    expect(find.text('Map Test'), findsOneWidget);
    expect(find.text('Map Editor'), findsOneWidget);
  });
}
