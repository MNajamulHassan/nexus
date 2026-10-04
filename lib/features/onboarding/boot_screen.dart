import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/identity_providers.dart';

class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(playerIdentityProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: identity.when(
              data: (_) => const CircularProgressIndicator(),
              loading: () => const CircularProgressIndicator(),
              error: (error, _) => _BootError(
                message: error is IdentityException
                    ? error.message
                    : 'Could not start Nexus. $error',
                onRetry: () {
                  ref.read(playerIdentityProvider.notifier).retry();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
