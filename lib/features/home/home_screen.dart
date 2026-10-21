import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/widgets/app_card.dart';

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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        actions: [
          // Debug-only shortcuts to screens with no real entry point of
          // their own — never shown in a release build.
          if (kDebugMode)
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
      body: Stack(
        children: [
          const Positioned.fill(child: _TopographicBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ListView(
                children: [
                  const SizedBox(height: 32),
                  const _LogoBadge(),
                  const SizedBox(height: 20),
                  Text(
                    NexusTheme.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Real places. Real hide and seek.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexusTheme.dimText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const AppCard(
                    child: Row(
                      children: [
                        Icon(Icons.public, color: NexusTheme.accent),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Real locations — use real-world maps to hide, '
                            'seek and outsmart.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 250),
                    crossFadeState: displayName != null
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Column(
                      children: [
                        Text(
                          displayName ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/choose-name'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Name'),
                        ),
                      ],
                    ),
                    secondChild: const SizedBox(height: 48),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.push('/create-game'),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Create Game'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/join-game'),
                    icon: const Icon(Icons.login),
                    label: const Text('Join Game'),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => context.push('/zombie-mode'),
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Zombie Mode (Solo)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A location pin inside a glowing cyan ring — stands in for a proper app
/// icon without adding an image asset.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NexusTheme.surface,
          border: Border.all(color: NexusTheme.accent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: NexusTheme.accent.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.location_on,
          color: NexusTheme.accent,
          size: 36,
        ),
      ),
    );
  }
}

/// A faint radial vignette plus a few concentric rings, evoking a
/// topographic map without loading any image asset.
class _TopographicBackground extends StatelessWidget {
  const _TopographicBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.6),
          radius: 1.2,
          colors: [NexusTheme.surfaceRaised, NexusTheme.background],
        ),
      ),
      child: CustomPaint(painter: _ContourPainter()),
    );
  }
}

class _ContourPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NexusTheme.hairline.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = Offset(size.width * 0.5, size.height * 0.28);
    for (var i = 1; i <= 5; i++) {
      canvas.drawCircle(center, i * size.width * 0.28, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) => false;
}
