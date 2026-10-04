import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/app/app.dart';

void main() {
  testWidgets('Home screen shows title and game actions', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NexusApp()));

    expect(find.text('NEXUS'), findsOneWidget);
    expect(find.text('Create Game'), findsOneWidget);
    expect(find.text('Join Game'), findsOneWidget);
    expect(find.text('GPS Test'), findsOneWidget);
    expect(find.text('Map Test'), findsOneWidget);
  });
}
