import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/game/game_providers.dart';
import '../../models/game.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lobby = ref.watch(lobbyProvider(gameId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(lobbyProvider(gameId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: lobby.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LobbyError(
          message: error.toString(),
          onRetry: () => ref.invalidate(lobbyProvider(gameId)),
        ),
        data: (snapshot) => _LobbyBody(snapshot: snapshot),
      ),
    );
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({required this.snapshot});

  final LobbySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final game = snapshot.game;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text('Join code', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Material(
          color: NexusTheme.surface,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    game.joinCode,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy join code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: game.joinCode));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Join code copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SummaryCard(
          children: [
            _SummaryRow(label: 'Game mode', value: game.modeLabel),
            _SummaryRow(label: 'Host', value: snapshot.hostName),
            _SummaryRow(label: 'Status', value: 'Waiting for players'),
            _SummaryRow(
              label: 'Match duration',
              value: '${game.matchDurationSeconds}s',
            ),
            _SummaryRow(
              label: 'Hiding duration',
              value: '${game.hidingDurationSeconds}s',
            ),
            _SummaryRow(
              label: 'Catch radius',
              value: '${game.catchRadiusMeters}m',
            ),
            _SummaryRow(
              label: 'Reveal interval',
              value: '${game.revealIntervalSeconds}s',
            ),
            _SummaryRow(
              label: 'Reveal duration',
              value: '${game.revealDurationSeconds}s',
            ),
            _SummaryRow(
              label: 'Taunts',
              value: game.tauntsEnabled ? 'Enabled' : 'Disabled',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Players (${snapshot.players.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final player in snapshot.players)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(player.displayName),
            subtitle: Text(player.isHost ? 'Host · ${player.player.status}' : player.player.status),
          ),
        const SizedBox(height: 16),
        Text(
          'Waiting for players. Tap refresh to update the list.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexusTheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LobbyError extends StatelessWidget {
  const _LobbyError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
