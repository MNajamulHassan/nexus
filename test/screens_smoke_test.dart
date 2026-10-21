import 'package:flutter/material.dart';
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
  testWidgets('Home, Join Game and Create Game render at 360x640 with no '
      'exception', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerIdentityProvider.overrideWith(_ReadyIdentityController.new),
        ],
        child: const NexusApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Join Game'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Join'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Create Game'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Below the fold in the Create Game ListView at this screen height.
    await tester.scrollUntilVisible(
      find.text('Create lobby'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Create lobby'), findsOneWidget);
  });
}
