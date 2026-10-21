import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        const SectionHeader('Mode'),
        AppCard(
          child: SegmentedButton<GameMode>(
            segments: [
              for (final value in GameMode.values)
                ButtonSegment(
                  value: value,
                  label: Text(GameConfig.modeDisplayName(value)),
                ),
            ],
            selected: {mode},
            onSelectionChanged: enabled
                ? (selection) => onModeChanged(selection.first)
                : null,
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Timing'),
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
        const SectionHeader('Catch radius'),
        AppCard(
          child: GameSettingsNumberField(
            controller: catchRadiusController,
            label: 'Catch radius (meters)',
            decimal: true,
            enabled: enabled,
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Reveal windows'),
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
