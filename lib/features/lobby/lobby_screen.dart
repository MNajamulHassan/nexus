import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/game/lobby_controller.dart';
import '../../core/widgets/app_busy_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_error_state.dart';
import '../../models/game.dart';
import 'edit_settings_sheet.dart';

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
      if (view == null) {
        return;
      }

      if (view.cancelled) {
        // Whether this was the host cancelling, or me being kicked, I'm no
        // longer the host observing my own action here — if I am the host,
        // I already know and navigated myself away via _confirmCancel.
        final notHost = userId == null || view.snapshot.game.hostId != userId;
        if (notHost) {
          unawaited(_showCancelledOrKickedNotice());
        }
        if (context.mounted) {
          context.go('/');
        }
        return;
      }

      final status = view.snapshot.game.status;
      if (status == 'FINISHED' || status == 'CLOSED') {
        if (context.mounted) {
          context.go('/results/${widget.gameId}');
        }
        return;
      }
      if (status == 'STARTING' ||
          status == 'HIDING_PHASE' ||
          status == 'ACTIVE') {
        if (context.mounted) {
          context.go('/match/${widget.gameId}');
        }
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
        error: (error, _) => AppErrorState(
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
            onStart: _busy ? null : () => _start(),
            onEditSettings: _busy ? null : () => _openEditSettings(view),
            onKick: _busy ? null : (player) => _confirmKick(player),
          );
        },
      ),
    );
  }

  Future<void> _showCancelledOrKickedNotice() async {
    // Read both providers now, before navigating away: `ref` itself stops
    // being safe to use once this widget is disposed, but the controller
    // instance read here is a plain long-lived object independent of this
    // widget, so calling .show() on it later (after the await, by which
    // point we've very likely already navigated off this screen) is fine.
    final repo = ref.read(gameRepositoryProvider);
    final noticeController = ref.read(homeNoticeProvider.notifier);

    var message = 'The host cancelled this lobby.';
    try {
      final kicked = await repo.wasKicked(widget.gameId);
      if (kicked) {
        message = 'You were removed from the lobby.';
      }
    } catch (_) {
      // Fall back to the cancel message.
    }
    noticeController.show(message);
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

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(gameRepositoryProvider).startGame(widget.gameId);
      if (!mounted) {
        return;
      }
      context.go('/match/${widget.gameId}');
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
      ).showSnackBar(SnackBar(content: Text('Could not start. $error')));
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

  Future<void> _openEditSettings(LobbyView view) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => EditSettingsSheet(
        gameId: widget.gameId,
        game: view.snapshot.game,
        players: view.snapshot.players,
      ),
    );
  }

  Future<void> _confirmKick(LobbyPlayer player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove player?'),
          content: Text(
            'Remove ${player.displayName} from this lobby? They cannot '
            'rejoin with the same code.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep player'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
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
      await ref
          .read(gameRepositoryProvider)
          .kickPlayer(widget.gameId, player.player.playerId);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await ref.read(lobbyControllerProvider(widget.gameId).notifier).refresh();
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
      ).showSnackBar(SnackBar(content: Text('Could not remove player. $error')));
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
    required this.onStart,
    required this.onEditSettings,
    required this.onKick,
  });

  final LobbyView view;
  final bool isHost;
  final bool busy;
  final VoidCallback? onLeave;
  final VoidCallback? onCancel;
  final VoidCallback? onStart;
  final VoidCallback? onEditSettings;
  final void Function(LobbyPlayer player)? onKick;

  @override
  Widget build(BuildContext context) {
    final snapshot = view.snapshot;
    final game = snapshot.game;
    String? seekerName;
    if (game.seekerIsManual) {
      for (final player in snapshot.players) {
        if (player.player.playerId == game.seekerPlayerId) {
          seekerName = player.displayName;
          break;
        }
      }
    }
    final seekerReady =
        !game.seekerIsManual ||
        snapshot.players.any((p) => p.player.playerId == game.seekerPlayerId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _RealtimeBanner(status: view.realtime),
        const SizedBox(height: 16),
        Text('Join code', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  game.joinCode,
                  style: NexusTheme.readout.copyWith(
                    fontSize: 28,
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
            _SummaryRow(
              label: 'Seeker',
              value: game.seekerIsManual
                  ? (seekerName ?? 'Choose player (not chosen)')
                  : 'Random',
            ),
          ],
        ),
        if (isHost) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onEditSettings,
            child: const Text('Edit settings'),
          ),
        ],
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
            trailing: isHost && !player.isHost
                ? IconButton(
                    tooltip: 'Remove player',
                    onPressed: onKick == null ? null : () => onKick!(player),
                    icon: const Icon(Icons.person_remove_outlined),
                  )
                : null,
          ),
        const SizedBox(height: 16),
        Text(
          'Waiting for players. The list updates live.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (isHost) ...[
          AppBusyButton(
            busy: busy,
            onPressed: snapshot.players.length >= 2 && seekerReady
                ? onStart
                : null,
            child: const Text('Start Match'),
          ),
          if (snapshot.players.length < 2) ...[
            const SizedBox(height: 8),
            Text(
              'Need at least 2 players to start.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!seekerReady) ...[
            const SizedBox(height: 8),
            Text(
              'Choose a seeker in Edit settings before starting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onCancel,
            child: const Text('Cancel lobby'),
          ),
        ] else
          AppBusyButton(
            busy: busy,
            outlined: true,
            onPressed: onLeave,
            child: const Text('Leave lobby'),
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
      LobbyRealtimeStatus.connected => ('Connected', NexusTheme.success),
      LobbyRealtimeStatus.connecting => ('Connecting…', NexusTheme.warning),
      LobbyRealtimeStatus.reconnecting => ('Reconnecting', NexusTheme.warning),
      LobbyRealtimeStatus.error => ('Error', NexusTheme.danger),
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
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
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

