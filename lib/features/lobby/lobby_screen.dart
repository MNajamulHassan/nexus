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
            onPressed: () => ref
                .read(lobbyControllerProvider(widget.gameId).notifier)
                .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: lobby.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorState(
          message: error.toString(),
          onRetry: () => ref
              .read(lobbyControllerProvider(widget.gameId).notifier)
              .refresh(),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not leave. $error')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start. $error')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not cancel. $error')));
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
            'Remove ${player.displayName} from this lobby? They can rejoin '
            'later with the same join code.',
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove player. $error')),
      );
    }
  }
}

/// Exposes the lobby's layout body for widget tests without needing the
/// Riverpod/Supabase wiring the real screen pulls in via its controller.
@visibleForTesting
Widget buildLobbyBodyForTest({required LobbyView view, required bool isHost}) {
  return _LobbyBody(
    view: view,
    isHost: isHost,
    busy: false,
    onLeave: () {},
    onCancel: () {},
    onStart: () {},
    onEditSettings: () {},
    onKick: (_) {},
  );
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

    final settingsFingerprint = [
      game.mode,
      game.hidingDurationSeconds,
      game.matchDurationSeconds,
      game.catchRadiusMeters,
      game.revealIntervalSeconds,
      game.revealDurationSeconds,
      game.tauntsEnabled,
      game.seekerMode,
      game.seekerPlayerId,
    ].join('|');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _RealtimeBanner(status: view.realtime),
        const SizedBox(height: 16),
        // IntrinsicHeight gives this Row a concrete, finite height before
        // CrossAxisAlignment.stretch tries to apply it to both cards —
        // without it, the Row sits in the ListView's unbounded-height
        // context and stretch has no finite height to stretch to.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: AppCard(
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
                          await Clipboard.setData(
                            ClipboardData(text: game.joinCode),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Join code copied')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.sports_esports_outlined,
                        color: NexusTheme.accent,
                        size: 20,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        game.modeLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SettingsSummaryCard(
          fingerprint: settingsFingerprint,
          children: [
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
          OutlinedButton.icon(
            onPressed: onEditSettings,
            icon: const Icon(Icons.tune),
            label: const Text('Edit settings'),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Players (${snapshot.players.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final player in snapshot.players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: NexusTheme.surfaceRaised,
                  child: Text(
                    player.displayName.isNotEmpty
                        ? player.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: NexusTheme.accent,
                      fontFamily: NexusTheme.fontDisplay,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              player.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (player.isHost) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.workspace_premium,
                              size: 14,
                              color: NexusTheme.warning,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _StatusDot(status: player.player.status),
                          const SizedBox(width: 6),
                          Text(
                            player.player.status,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isHost && !player.isHost)
                  IconButton(
                    tooltip: 'Remove player',
                    onPressed: onKick == null ? null : () => onKick!(player),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        if (isHost)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: snapshot.players.length >= 2
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            // AnimatedCrossFade sizes itself between the two children, which
            // can go through layout in a context where only the Row's exact
            // width is known, not its height — an explicit full-width
            // wrapper on each child keeps that width concrete instead of
            // leaving it to each child's own (differing) intrinsic logic.
            firstChild: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBusyButton(
                    busy: busy,
                    onPressed: seekerReady ? onStart : null,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 22),
                        SizedBox(width: 8),
                        Text('Start Match'),
                      ],
                    ),
                  ),
                  if (!seekerReady) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Choose a seeker in Edit settings before starting.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            secondChild: SizedBox(
              width: double.infinity,
              child: AppCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_empty,
                      color: NexusTheme.dimText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Waiting for players. Need at least 2 to start.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Text(
            'Waiting for the host to start. The list updates live.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 24),
        if (isHost)
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel lobby'),
          )
        else
          AppBusyButton(
            busy: busy,
            outlined: true,
            onPressed: onLeave,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.logout, size: 20),
                SizedBox(width: 8),
                Text('Leave lobby'),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ACTIVE' => NexusTheme.success,
      'ELIMINATED' => NexusTheme.danger,
      'READY' => NexusTheme.accent,
      _ => NexusTheme.dimText,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

    // Dimmed while not fully connected, full opacity once it is — reuses
    // the same AnimatedOpacity + duration/curve pattern match_screen.dart
    // uses for its own overlay fades, instead of a bespoke transition here.
    return AnimatedOpacity(
      key: ValueKey(status),
      opacity: status == LobbyRealtimeStatus.connected ? 1 : 0.6,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Wraps the settings summary rows; briefly highlights its border whenever
/// [fingerprint] changes (i.e. the host just saved new settings), then
/// animates back to the resting hairline border after ~800ms.
class _SettingsSummaryCard extends StatefulWidget {
  const _SettingsSummaryCard({
    required this.fingerprint,
    required this.children,
  });

  final String fingerprint;
  final List<Widget> children;

  @override
  State<_SettingsSummaryCard> createState() => _SettingsSummaryCardState();
}

class _SettingsSummaryCardState extends State<_SettingsSummaryCard> {
  bool _highlighted = false;
  Timer? _resetTimer;

  @override
  void didUpdateWidget(covariant _SettingsSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fingerprint != widget.fingerprint) {
      _resetTimer?.cancel();
      setState(() => _highlighted = true);
      _resetTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _highlighted = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexusTheme.surface,
        borderRadius: BorderRadius.circular(NexusTheme.cardRadius),
        border: Border.all(
          color: _highlighted ? NexusTheme.accent : NexusTheme.hairline,
          width: _highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < widget.children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            widget.children[i],
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
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
