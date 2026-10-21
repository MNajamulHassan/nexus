import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/app/theme.dart';
import 'package:nexus/features/lobby/lobby_screen.dart';
import 'package:nexus/models/game.dart';
import 'package:nexus/models/game_config.dart';

void main() {
  testWidgets('lobby body renders at 360x640 with no exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = GameRecord(
      id: 'game-1',
      hostId: 'host-1',
      joinCode: 'ABC123',
      mode: GameMode.hideAndSeek,
      status: 'LOBBY',
      createdAt: DateTime(2026, 1, 1),
      hidingDurationSeconds: 180,
      matchDurationSeconds: 1200,
      catchRadiusMeters: 20,
      revealIntervalSeconds: 600,
      revealDurationSeconds: 30,
      tauntsEnabled: true,
    );

    LobbyPlayer player(String id, String name, {bool isHost = false}) {
      return LobbyPlayer(
        player: GamePlayerRecord(
          id: 'row-$id',
          gameId: 'game-1',
          playerId: id,
          status: 'JOINED',
          joinedAt: DateTime(2026, 1, 1),
        ),
        displayName: name,
        isHost: isHost,
      );
    }

    final view = LobbyView(
      snapshot: LobbySnapshot(
        game: game,
        hostName: 'Hostie',
        players: [
          player('host-1', 'Hostie', isHost: true),
          player('user-2', 'Alice'),
          player('user-3', 'Bob'),
        ],
      ),
      realtime: LobbyRealtimeStatus.connected,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark,
        home: Scaffold(body: buildLobbyBodyForTest(view: view, isHost: true)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ABC123'), findsOneWidget);

    // The lobby body is a long ListView in a 640px viewport — later
    // content isn't built until scrolled into view (lazy sliver list),
    // not merely offstage, so each lower assertion scrolls to it first.
    final scrollable = find.byType(Scrollable).first;
    for (final finder in [
      find.text('Alice'),
      find.text('Bob'),
      find.text('Edit settings'),
      find.textContaining('Start Match'),
    ]) {
      await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(finder, findsOneWidget);
    }
  });
}
