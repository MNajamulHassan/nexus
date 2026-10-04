import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/game/lobby_controller.dart';
import '../../models/game.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final lobby = ref.watch(lobbyControllerProvider(widget.gameId));
    final userId = ref.watch(playerIdentityProvider).value?.userId;

    ref.listen(lobbyControllerProvider(widget.gameId), (previous, next) {
      final view = next.value;
      if (view?.cancelled != true) {
        return;
      }
      final cancelledByHost =
          userId == null || view!.snapshot.game.hostId != userId;
      if (cancelledByHost) {
        ref
            .read(homeNoticeProvider.notifier)
            .show('The host cancelled this lobby.');
      }
      if (context.mounted) {
        context.go('/');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(lobbyControllerProvider(widget.gameId).notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: lobby.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LobbyError(
          message: error.toString(),
          onRetry: () =>
              ref.read(lobbyControllerProvider(widget.gameId).notifier).refresh(),
        ),
        data: (view) {
          final isHost = userId != null && view.snapshot.game.hostId == userId;
          return _LobbyBody(
            view: view,
            isHost: isHost,
            busy: _busy,
            onLeave: _busy ? null : () => _leave(),
            onCancel: _busy ? null : () => _confirmCancel(),
          );
        },
      ),
    );
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await ref.read(lobbyControllerProvider(widget.gameId).notifier).leave();
      if (!mounted) {
        return;
      }
      context.go('/');
    } on LobbyException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not leave. $error')));
    }
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel lobby?'),
          content: const Text(
            'This removes the lobby for every player. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep lobby'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancel lobby'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(lobbyControllerProvider(widget.gameId).notifier).cancel();
      if (!mounted) {
        return;
      }
      context.go('/');
    } on LobbyException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel. $error')));
    }
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.view,
    required this.isHost,
    required this.busy,
    required this.onLeave,
    required this.onCancel,
  });

  final LobbyView view;
  final bool isHost;
  final bool busy;
  final VoidCallback? onLeave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final snapshot = view.snapshot;
    final game = snapshot.game;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _RealtimeBanner(status: view.realtime),
        const SizedBox(height: 16),
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
            _SummaryRow(label: 'Status', value: game.status),
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
            subtitle: Text(
              player.isHost
                  ? 'Host · ${player.player.status}'
                  : player.player.status,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Waiting for players. The list updates live.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (isHost)
          OutlinedButton(
            onPressed: onCancel,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel Lobby'),
          )
        else
          OutlinedButton(
            onPressed: onLeave,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Leave Lobby'),
          ),
      ],
    );
  }
}

class _RealtimeBanner extends StatelessWidget {
  const _RealtimeBanner({required this.status});

  final LobbyRealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      LobbyRealtimeStatus.connected => ('Connected', Colors.greenAccent),
      LobbyRealtimeStatus.connecting => ('Connecting…', Colors.amberAccent),
      LobbyRealtimeStatus.reconnecting => (
        'Reconnecting',
        Colors.amberAccent,
      ),
      LobbyRealtimeStatus.error => ('Error', Colors.redAccent),
    };

    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
