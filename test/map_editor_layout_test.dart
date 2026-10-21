import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/app/theme.dart';
import 'package:nexus/features/map_editor/map_editor_screen.dart';

void main() {
  testWidgets(
    'editor controls panel stays within 35% of a 360x640 screen, '
    'leaving the map area at least 70%',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const mapAreaKey = ValueKey('map-area');
      const controlsKey = ValueKey('controls-area');

      await tester.pumpWidget(
        MaterialApp(
          theme: NexusTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(
                  child: ColoredBox(key: mapAreaKey, color: Colors.black),
                ),
                KeyedSubtree(
                  key: controlsKey,
                  child: buildEditorControlsForTest(
                    status: 'Tap the map to add points.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      const screenHeight = 640.0;
      final mapHeight = tester.getSize(find.byKey(mapAreaKey)).height;
      final controlsHeight = tester.getSize(find.byKey(controlsKey)).height;

      expect(controlsHeight, lessThanOrEqualTo(screenHeight * 0.35));
      expect(mapHeight, greaterThanOrEqualTo(screenHeight * 0.6));

      // Every action from the old full-width Wrap is still reachable —
      // the action row scrolls horizontally, so later items aren't built
      // until scrolled into view (lazy list, not merely offstage).
      final actionScrollable = find.descendant(
        of: find.byKey(controlsKey),
        matching: find.byType(Scrollable),
      );
      for (final label in [
        'Playable',
        'Restricted',
        'Complete',
        'Undo',
        'Cancel',
        'Clear',
        'Delete zone',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          80,
          scrollable: actionScrollable,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Confirm Area'), findsOneWidget);
    },
  );
}
