import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/game/game_providers.dart';
import '../../models/game.dart';

class JoinGameScreen extends ConsumerStatefulWidget {
  const JoinGameScreen({super.key});

  @override
  ConsumerState<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends ConsumerState<JoinGameScreen> {
  final _code = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    if (_joining) {
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final gameId = await ref.read(lobbyServiceProvider).joinLobby(_code.text);
      if (!mounted) {
        return;
      }
      context.go('/lobby/$gameId');
    } on LobbyException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _joining = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _joining = false;
        _error = 'Could not join the lobby. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Game')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Text(
            'Enter the 6-character code from the host.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            enabled: !_joining,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _join(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              _UpperCaseTextFormatter(),
            ],
            decoration: const InputDecoration(
              labelText: 'Join code',
              counterText: '',
              filled: true,
              fillColor: NexusTheme.surface,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _joining ? null : _join,
            child: _joining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Join'),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
