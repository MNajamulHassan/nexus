import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_models.dart';
import '../../core/game/game_providers.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_error_state.dart';
import '../../models/game.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _loading = true;
  String? _error;
  GameRecord? _game;
  List<GamePlayerRecord> _players = const [];
  Map<String, PlayerProfile> _profiles = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(gameRepositoryProvider);
      final game = await repo.fetchGame(widget.gameId);
      final players = await repo.fetchPlayers(widget.gameId);
      final profiles = await repo.fetchProfiles([
        for (final player in players) player.playerId,
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _game = game;
        _players = players;
        _profiles = profiles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return AppErrorState(
        message: error,
        secondaryAction: OutlinedButton(
          onPressed: () => context.go('/'),
          child: const Text('Back to home'),
        ),
      );
    }

    final game = _game!;
    final startedAt = game.startedAt;
    final activeAt = startedAt?.add(
      Duration(seconds: game.hidingDurationSeconds),
    );
    final endedAt = game.endedAt ?? DateTime.now();

    final hidersRemaining = _players
        .where((p) => p.isHider && p.status == 'ACTIVE')
        .length;
    final seekerWon = hidersRemaining == 0;

    final seeker = _players.where((p) => p.isSeeker).firstOrNull;
    final hiders = [..._players.where((p) => p.isHider)]
      ..sort((a, b) {
        final survivedA = _survivedSeconds(a, activeAt, endedAt);
        final survivedB = _survivedSeconds(b, activeAt, endedAt);
        return survivedB.compareTo(survivedA);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        AppCard(
          child: Column(
            children: [
              Text(
                seekerWon ? 'Seeker wins' : 'Hiders win',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: seekerWon ? NexusTheme.danger : NexusTheme.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                seekerWon
                    ? 'Every hider was caught.'
                    : 'Time ran out before all hiders were caught.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (seeker != null) ...[
          Text('Seeker', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _PlayerTile(
            name: _profiles[seeker.playerId]?.displayName ?? 'Player',
            subtitle: seekerWon ? 'Caught everyone' : 'Ran out of time',
            icon: Icons.search,
          ),
          const SizedBox(height: 24),
        ],
        Text(
          'Hiders (${hiders.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final hider in hiders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlayerTile(
              name: _profiles[hider.playerId]?.displayName ?? 'Player',
              subtitle: hider.caughtAt != null
                  ? 'Caught after ${_formatDuration(_survivedSeconds(hider, activeAt, endedAt))}'
                  : 'Survived the whole match',
              icon: hider.caughtAt != null
                  ? Icons.flash_on
                  : Icons.verified_user,
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Back to home'),
        ),
      ],
    );
  }

  int _survivedSeconds(
    GamePlayerRecord player,
    DateTime? activeAt,
    DateTime endedAt,
  ) {
    if (activeAt == null) {
      return 0;
    }
    final end = player.caughtAt ?? endedAt;
    final seconds = end.difference(activeAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    if (minutes <= 0) {
      return '${remaining}s';
    }
    return '${minutes}m ${remaining}s';
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.name,
    required this.subtitle,
    required this.icon,
  });

  final String name;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: NexusTheme.accent),
        title: Text(name),
        subtitle: Text(subtitle),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
