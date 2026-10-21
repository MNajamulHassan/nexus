import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/game_providers.dart';
import '../../core/widgets/app_busy_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../../models/game.dart';
import '../../models/game_config.dart';
import '../game_create/game_settings_form.dart';

/// Host-only. Reuses [GameSettingsForm] (the same fields Create Game uses)
/// plus a seeker-mode control. Zones are not editable here — that stays
/// replace_game_zones/the map editor, unrelated to this RPC.
class EditSettingsSheet extends ConsumerStatefulWidget {
  const EditSettingsSheet({
    super.key,
    required this.gameId,
    required this.game,
    required this.players,
  });

  final String gameId;
  final GameRecord game;
  final List<LobbyPlayer> players;

  @override
  ConsumerState<EditSettingsSheet> createState() => _EditSettingsSheetState();
}

class _EditSettingsSheetState extends ConsumerState<EditSettingsSheet> {
  late final TextEditingController _matchDuration;
  late final TextEditingController _hidingDuration;
  late final TextEditingController _catchRadius;
  late final TextEditingController _revealInterval;
  late final TextEditingController _revealDuration;

  late GameMode _mode;
  late bool _tauntsEnabled;
  late String _seekerMode;
  String? _seekerPlayerId;

  String? _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final game = widget.game;
    _matchDuration = TextEditingController(
      text: '${game.matchDurationSeconds}',
    );
    _hidingDuration = TextEditingController(
      text: '${game.hidingDurationSeconds}',
    );
    _catchRadius = TextEditingController(
      text: game.catchRadiusMeters.toStringAsFixed(0),
    );
    _revealInterval = TextEditingController(
      text: '${game.revealIntervalSeconds}',
    );
    _revealDuration = TextEditingController(
      text: '${game.revealDurationSeconds}',
    );
    _mode = game.mode;
    _tauntsEnabled = game.tauntsEnabled;
    _seekerMode = game.seekerMode;
    _seekerPlayerId = game.seekerPlayerId;
  }

  @override
  void dispose() {
    _matchDuration.dispose();
    _hidingDuration.dispose();
    _catchRadius.dispose();
    _revealInterval.dispose();
    _revealDuration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) {
      return;
    }

    final matchDuration = int.tryParse(_matchDuration.text.trim());
    final hidingDuration = int.tryParse(_hidingDuration.text.trim());
    final catchRadius = double.tryParse(_catchRadius.text.trim());
    final revealInterval = int.tryParse(_revealInterval.text.trim());
    final revealDuration = int.tryParse(_revealDuration.text.trim());

    final error = GameConfig.validateSettings(
      mode: _mode,
      matchDurationSeconds: matchDuration,
      hidingDurationSeconds: hidingDuration,
      catchRadiusMeters: catchRadius,
      revealIntervalSeconds: revealInterval,
      revealDurationSeconds: revealDuration,
    );
    if (error != null) {
      setState(() => _status = error);
      return;
    }
    if (_seekerMode == 'MANUAL' && _seekerPlayerId == null) {
      setState(() => _status = 'Choose a seeker.');
      return;
    }

    setState(() {
      _saving = true;
      _status = null;
    });

    try {
      await ref
          .read(gameRepositoryProvider)
          .updateGameSettings(
            gameId: widget.gameId,
            mode: _mode,
            hidingDurationSeconds: hidingDuration!,
            matchDurationSeconds: matchDuration!,
            catchRadiusMeters: catchRadius!,
            revealIntervalSeconds: revealInterval!,
            revealDurationSeconds: revealDuration!,
            tauntsEnabled: _tauntsEnabled,
            seekerMode: _seekerMode,
            seekerPlayerId: _seekerMode == 'MANUAL' ? _seekerPlayerId : null,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on LobbyException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _status = e.message;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _status = 'Could not save settings. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Text(
                'Edit settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              GameSettingsForm(
                mode: _mode,
                onModeChanged: (mode) => setState(() => _mode = mode),
                matchDurationController: _matchDuration,
                hidingDurationController: _hidingDuration,
                catchRadiusController: _catchRadius,
                revealIntervalController: _revealInterval,
                revealDurationController: _revealDuration,
                tauntsEnabled: _tauntsEnabled,
                onTauntsChanged: (value) =>
                    setState(() => _tauntsEnabled = value),
                enabled: !_saving,
              ),
              const SizedBox(height: 20),
              const SectionHeader('Seeker'),
              AppCard(
                child: RadioGroup<String>(
                  groupValue: _seekerMode,
                  onChanged: _saving
                      ? (_) {}
                      : (value) => setState(() => _seekerMode = value!),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Random'),
                        value: 'RANDOM',
                      ),
                      const RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Choose player'),
                        value: 'MANUAL',
                      ),
                      if (_seekerMode == 'MANUAL') ...[
                        const Divider(height: 1),
                        RadioGroup<String>(
                          groupValue: _seekerPlayerId,
                          onChanged: _saving
                              ? (_) {}
                              : (value) =>
                                  setState(() => _seekerPlayerId = value),
                          child: Column(
                            children: [
                              for (final player in widget.players)
                                RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    player.isHost
                                        ? '${player.displayName} (Host)'
                                        : player.displayName,
                                  ),
                                  value: player.player.playerId,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              AppBusyButton(
                busy: _saving,
                onPressed: _save,
                child: const Text('Save settings'),
              ),
            ],
          );
        },
      ),
    );
  }
}
