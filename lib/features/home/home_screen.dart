import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              Text(
                'NEXUS',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () {},
                child: const Text('Create Game'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {},
                child: const Text('Join Game'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/gps-test'),
                child: const Text('GPS Test'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
