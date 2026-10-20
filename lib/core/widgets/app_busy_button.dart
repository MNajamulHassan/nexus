import 'package:flutter/material.dart';

/// Primary/outlined button that swaps its label for a spinner while busy —
/// the pattern duplicated in Create Game, Join Game, Choose Name, Lobby.
class AppBusyButton extends StatelessWidget {
  const AppBusyButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.child,
    this.outlined = false,
  });

  final bool busy;
  final VoidCallback? onPressed;
  final Widget child;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    final content = busy ? spinner : child;
    final pressed = busy ? null : onPressed;
    return outlined
        ? OutlinedButton(onPressed: pressed, child: content)
        : FilledButton(onPressed: pressed, child: content);
  }
}
