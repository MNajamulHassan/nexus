import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/app/theme.dart';
import 'package:nexus/features/game_create/game_settings_form.dart';
import 'package:nexus/models/game_config.dart';

void main() {
  testWidgets('mode cards render at equal height, 360 wide, no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final matchDuration = TextEditingController(text: '1200');
    final hidingDuration = TextEditingController(text: '180');
    final catchRadius = TextEditingController(text: '20');
    final revealInterval = TextEditingController(text: '600');
    final revealDuration = TextEditingController(text: '30');
    addTearDown(() {
      matchDuration.dispose();
      hidingDuration.dispose();
      catchRadius.dispose();
      revealInterval.dispose();
      revealDuration.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: GameSettingsForm(
              mode: GameMode.hideAndSeek,
              onModeChanged: (_) {},
              matchDurationController: matchDuration,
              hidingDurationController: hidingDuration,
              catchRadiusController: catchRadius,
              revealIntervalController: revealInterval,
              revealDurationController: revealDuration,
              tauntsEnabled: true,
              onTauntsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Hide & Seek'), findsOneWidget);
    expect(find.text('Infected'), findsOneWidget);
    expect(find.text('Caught hiders join seekers'), findsOneWidget);

    final hideAndSeekCard = tester.getSize(
      find
          .ancestor(
            of: find.text('Hide & Seek'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final infectedCard = tester.getSize(
      find
          .ancestor(
            of: find.text('Infected'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

    expect(hideAndSeekCard.height, infectedCard.height);
  });
}
