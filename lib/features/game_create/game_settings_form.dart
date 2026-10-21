import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../../models/game_config.dart';

/// Mode/Timing/Catch radius/Reveal windows fields shared by Create Game and
/// the lobby's Edit Settings sheet. Zones and seeker selection are not part
/// of this widget — each caller handles those itself.
class GameSettingsForm extends StatelessWidget {
  const GameSettingsForm({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.matchDurationController,
    required this.hidingDurationController,
    required this.catchRadiusController,
    required this.revealIntervalController,
    required this.revealDurationController,
    required this.tauntsEnabled,
    required this.onTauntsChanged,
    this.enabled = true,
  });

  final GameMode mode;
  final ValueChanged<GameMode> onModeChanged;
  final TextEditingController matchDurationController;
  final TextEditingController hidingDurationController;
  final TextEditingController catchRadiusController;
  final TextEditingController revealIntervalController;
  final TextEditingController revealDurationController;
  final bool tauntsEnabled;
  final ValueChanged<bool> onTauntsChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Mode', icon: Icons.sports_esports_outlined),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                title: 'Hide & Seek',
                subtitle: 'Hiders vs Seekers',
                icon: Icons.visibility_off_outlined,
                selected: mode == GameMode.hideAndSeek,
                onTap: enabled
                    ? () => onModeChanged(GameMode.hideAndSeek)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                title: 'Infected',
                subtitle: 'Caught hiders join the seekers',
                icon: Icons.coronavirus_outlined,
                selected: mode == GameMode.infected,
                onTap: enabled ? () => onModeChanged(GameMode.infected) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Timing', icon: Icons.timer_outlined),
        AppCard(
          child: Column(
            children: [
              GameSettingsNumberField(
                controller: matchDurationController,
                label: 'Match duration (seconds)',
                enabled: enabled,
              ),
              const SizedBox(height: 12),
              GameSettingsNumberField(
                controller: hidingDurationController,
                label: 'Hiding duration (seconds)',
                enabled: enabled,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Catch radius', icon: Icons.radar),
        AppCard(
          child: GameSettingsNumberField(
            controller: catchRadiusController,
            label: 'Catch radius (meters)',
            decimal: true,
            enabled: enabled,
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Reveal windows', icon: Icons.visibility_outlined),
        AppCard(
          child: Column(
            children: [
              GameSettingsNumberField(
                controller: revealIntervalController,
                label: 'Reveal interval (seconds)',
                enabled: enabled,
              ),
              const SizedBox(height: 12),
              GameSettingsNumberField(
                controller: revealDurationController,
                label: 'Reveal duration (seconds)',
                enabled: enabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Taunts enabled'),
                value: tauntsEnabled,
                onChanged: enabled ? onTauntsChanged : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One of the two selectable mode cards. The border/background animate
/// between the selected and unselected look instead of snapping.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? NexusTheme.accent : NexusTheme.dimText;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? NexusTheme.accent.withValues(alpha: 0.12)
              : NexusTheme.surface,
          borderRadius: BorderRadius.circular(NexusTheme.cardRadius),
          border: Border.all(
            color: selected ? NexusTheme.accent : NexusTheme.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? NexusTheme.accent : NexusTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class GameSettingsNumberField extends StatelessWidget {
  const GameSettingsNumberField({
    super.key,
    required this.controller,
    required this.label,
    this.decimal = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool decimal;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(labelText: label),
    );
  }
}
