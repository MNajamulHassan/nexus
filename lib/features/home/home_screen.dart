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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListView(
            children: [
              const SizedBox(height: 72),
              Text(
                'NEXUS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
              ),
              if (displayName != null) ...[
                const SizedBox(height: 16),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => context.push('/choose-name'),
                  child: const Text('Edit Name'),
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
                onPressed: () => context.push('/gps-test'),
                child: const Text('GPS Test'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/map-test'),
                child: const Text('Map Test'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/map-editor'),
                child: const Text('Map Editor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
