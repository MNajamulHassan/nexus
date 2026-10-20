import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/identity_providers.dart';
import '../../core/widgets/app_busy_button.dart';

class ChooseNameScreen extends ConsumerStatefulWidget {
  const ChooseNameScreen({super.key});

  @override
  ConsumerState<ChooseNameScreen> createState() => _ChooseNameScreenState();
}

class _ChooseNameScreenState extends ConsumerState<ChooseNameScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(playerIdentityProvider).value;
    final existing = current?.profile.displayName ?? '';
    _controller = TextEditingController(
      text: ProfileRules.isPlaceholder(existing) ? '' : existing,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final validation = ProfileRules.validate(_controller.text);
    if (validation != null) {
      setState(() {
        _error = validation;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(playerIdentityProvider.notifier)
          .updateDisplayName(_controller.text);
      if (!mounted) {
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } on IdentityException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = 'Could not save your name. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = context.canPop();

    return Scaffold(
      appBar: AppBar(
        title: Text(canLeave ? 'Edit Name' : 'Choose Name'),
        automaticallyImplyLeading: canLeave,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              'This name is shown to other players in the lobby.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              enabled: !_saving,
              maxLength: ProfileRules.maxLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            AppBusyButton(
              busy: _saving,
              onPressed: _save,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
