import 'package:flutter/material.dart';

/// Flat ops-panel surface — the one card shape used everywhere instead of
/// each screen hand-rolling its own `Material`/`borderRadius`/`Padding`.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Override the themed surface color — e.g. a translucent HUD overlay
  /// sitting on top of a map.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(color: color, child: Padding(padding: padding, child: child));
  }
}
