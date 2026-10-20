import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_models.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/widgets/app_error_state.dart';

class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(playerIdentityProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: identity.when(
            data: (_) => _BootBrand(),
            loading: () => _BootBrand(),
            error: (error, _) => AppErrorState(
              icon: Icons.wifi_off,
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
    );
  }
}

class _BootBrand extends StatelessWidget {
  const _BootBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'NEXUS',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: NexusTheme.accent,
          ),
        ),
        const SizedBox(height: 32),
        const CircularProgressIndicator(),
      ],
    );
  }
}
