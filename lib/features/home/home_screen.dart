import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(playerIdentityProvider).value;
    final displayName = identity?.profile.displayName;

    ref.listen<String?>(homeNoticeProvider, (previous, next) {
      if (next == null) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
      ref.read(homeNoticeProvider.notifier).clear();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Debug tools',
            icon: const Icon(Icons.more_vert),
            onSelected: (route) => context.push(route),
            itemBuilder: (context) => const [
              PopupMenuItem(value: '/gps-test', child: Text('GPS Test')),
              PopupMenuItem(value: '/map-test', child: Text('Map Test')),
              PopupMenuItem(value: '/map-editor', child: Text('Map Editor')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListView(
            children: [
              const SizedBox(height: 48),
              Text(
                'NEXUS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (displayName != null) ...[
                const SizedBox(height: 16),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/choose-name'),
                    child: const Text('Edit Name'),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.push('/create-game'),
                child: const Text('Create Game'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/join-game'),
                child: const Text('Join Game'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/zombie-mode'),
                child: const Text('Zombie Mode (Solo)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
