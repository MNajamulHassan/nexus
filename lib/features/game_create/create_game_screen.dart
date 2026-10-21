import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/game/game_providers.dart';
import '../../core/maps/map_models.dart';
import '../../core/widgets/app_busy_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../../models/game.dart';
import '../../models/game_config.dart';
import 'game_settings_form.dart';

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
          GameSettingsForm(
            mode: _mode,
            onModeChanged: (mode) => setState(() => _mode = mode),
            matchDurationController: _matchDuration,
            hidingDurationController: _hidingDuration,
            catchRadiusController: _catchRadius,
            revealIntervalController: _revealInterval,
            revealDurationController: _revealDuration,
            tauntsEnabled: _tauntsEnabled,
            onTauntsChanged: (value) => setState(() => _tauntsEnabled = value),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Play area'),
          OutlinedButton(
            onPressed: _creating ? null : _selectPlayArea,
            child: const Text('Select play area'),
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
          AppBusyButton(
            busy: _creating,
            onPressed: _createLobby,
            child: const Text('Create lobby'),
          ),
        ],
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected ? 'Play area selected' : 'No play area yet'),
          const SizedBox(height: 8),
          Text(
            'Playable vertices: ${result?.playable.polygon.vertices.length ?? 0}',
          ),
          const SizedBox(height: 4),
          Text('Restricted zones: ${result?.restrictedZones.length ?? 0}'),
        ],
      ),
    );
  }
}
