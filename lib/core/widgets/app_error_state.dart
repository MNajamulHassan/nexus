import 'package:flutter/material.dart';

/// Icon + message + retry — the shape every screen's error state already
/// reimplemented independently (boot, lobby, map editor, map test, gps test).
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.error_outline,
    this.secondaryAction,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: 8),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}
