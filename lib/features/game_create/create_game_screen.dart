import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/game/game_providers.dart';
import '../../core/maps/map_models.dart';
import '../../models/game.dart';
import '../../models/game_config.dart';

class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key});

  @override
  ConsumerState<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends ConsumerState<CreateGameScreen> {
  final _matchDuration = TextEditingController(
    text: '${GameConfig.defaultMatchDurationSeconds}',
  );
  final _hidingDuration = TextEditingController(
    text: '${GameConfig.defaultHidingDurationSeconds}',
  );
  final _catchRadius = TextEditingController(
    text: GameConfig.defaultCatchRadiusMeters.toStringAsFixed(0),
  );
  final _revealInterval = TextEditingController(
    text: '${GameConfig.defaultRevealIntervalSeconds}',
  );
  final _revealDuration = TextEditingController(
    text: '${GameConfig.defaultRevealDurationSeconds}',
  );

  GameMode _mode = GameMode.hideAndSeek;
  bool _tauntsEnabled = GameConfig.defaultTauntsEnabled;
  MapEditorResult? _mapResult;
  String? _status;
  bool _creating = false;

  @override
  void dispose() {
    _matchDuration.dispose();
    _hidingDuration.dispose();
    _catchRadius.dispose();
    _revealInterval.dispose();
    _revealDuration.dispose();
    super.dispose();
  }

  Future<void> _selectPlayArea() async {
    final result = await context.push<MapEditorResult>('/map-editor');
    if (!mounted) {
      return;
    }
    if (result == null) {
      setState(() {
        _status = _mapResult == null
            ? 'Play area not selected.'
            : 'Previous play area kept.';
      });
      return;
    }

    setState(() {
      _mapResult = result;
      _status = null;
    });
  }

  Future<void> _createLobby() async {
    FocusScope.of(context).unfocus();

    final config = _tryBuildConfig();
    if (config == null || _creating) {
      return;
    }

    setState(() {
      _creating = true;
      _status = null;
    });

    try {
      final lobby = await ref.read(lobbyServiceProvider).createLobby(config);
      if (!mounted) {
        return;
      }
      context.go('/lobby/${lobby.game.id}');
    } on LobbyException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _status = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _status = 'Could not create the lobby. $error';
      });
    }
  }

  GameConfig? _tryBuildConfig() {
    final matchDuration = _parsePositiveInt(_matchDuration.text);
    final hidingDuration = _parsePositiveInt(_hidingDuration.text);
    final catchRadius = _parseFiniteDouble(_catchRadius.text);
    final revealInterval = _parsePositiveInt(_revealInterval.text);
    final revealDuration = _parsePositiveInt(_revealDuration.text);
    final mapResult = _mapResult;

    final error = GameConfig.validate(
      mode: _mode,
      matchDurationSeconds: matchDuration,
      hidingDurationSeconds: hidingDuration,
      catchRadiusMeters: catchRadius,
      revealIntervalSeconds: revealInterval,
      revealDurationSeconds: revealDuration,
      playablePolygon: mapResult?.playable.polygon,
      restrictedPolygons: [
        for (final zone in mapResult?.restrictedZones ?? const <GameZone>[])
          zone.polygon,
      ],
    );

    if (error != null) {
      setState(() {
        _status = error;
      });
      return null;
    }

    setState(() {
      _status = null;
    });

    return GameConfig(
      mode: _mode,
      matchDurationSeconds: matchDuration!,
      hidingDurationSeconds: hidingDuration!,
      catchRadiusMeters: catchRadius!,
      revealIntervalSeconds: revealInterval!,
      revealDurationSeconds: revealDuration!,
      tauntsEnabled: _tauntsEnabled,
      playablePolygon: mapResult!.playable.polygon,
      restrictedPolygons: [
        for (final zone in mapResult.restrictedZones) zone.polygon,
      ],
    );
  }

  int? _parsePositiveInt(String raw) {
    return int.tryParse(raw.trim());
  }

  double? _parseFiniteDouble(String raw) {
    return double.tryParse(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final mapResult = _mapResult;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Game')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text('Game mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<GameMode>(
            segments: [
              for (final mode in GameMode.values)
                ButtonSegment(
                  value: mode,
                  label: Text(GameConfig.modeDisplayName(mode)),
                ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() {
                _mode = selection.first;
              });
            },
          ),
          const SizedBox(height: 24),
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _NumberField(
            controller: _matchDuration,
            label: 'Match duration (seconds)',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: _hidingDuration,
            label: 'Hiding duration (seconds)',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: _catchRadius,
            label: 'Catch radius (meters)',
            signed: false,
            decimal: true,
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: _revealInterval,
            label: 'Reveal interval (seconds)',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: _revealDuration,
            label: 'Reveal duration (seconds)',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Taunts enabled'),
            value: _tauntsEnabled,
            onChanged: (value) {
              setState(() {
                _tauntsEnabled = value;
              });
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _creating ? null : _selectPlayArea,
            child: const Text('SELECT PLAY AREA'),
          ),
          const SizedBox(height: 12),
          _PlayAreaSummary(result: mapResult),
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
          FilledButton(
            onPressed: _creating ? null : _createLobby,
            child: _creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('CREATE LOBBY'),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.signed = false,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final bool signed;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        signed: signed,
        decimal: decimal,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: NexusTheme.surface,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _PlayAreaSummary extends StatelessWidget {
  const _PlayAreaSummary({required this.result});

  final MapEditorResult? result;

  @override
  Widget build(BuildContext context) {
    final selected = result != null;

    return Material(
      color: NexusTheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Play Area: ${selected ? 'Selected' : 'Not selected'}'),
            const SizedBox(height: 8),
            Text(
              'Playable vertices: ${result?.playable.polygon.vertices.length ?? 0}',
            ),
            const SizedBox(height: 4),
            Text('Restricted Zones: ${result?.restrictedZones.length ?? 0}'),
          ],
        ),
      ),
    );
  }
}
