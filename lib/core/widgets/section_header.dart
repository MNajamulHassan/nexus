import 'package:flutter/material.dart';

/// Labels a group of related fields (e.g. Create Game's Mode/Timing/Catch
/// Radius groups) without resorting to a tracked-out all-caps eyebrow. An
/// optional leading icon keeps every section visually anchored.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    final icon = this.icon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: icon == null
          ? Text(label, style: style)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(label, style: style),
              ],
            ),
    );
  }
}
