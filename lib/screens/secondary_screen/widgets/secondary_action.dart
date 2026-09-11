import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A controller-focusable counterpart to [GestureDetector] for controls shown
/// by the secondary Flutter engine.
class SecondaryAction extends StatefulWidget {
  const SecondaryAction({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior? behavior;
  final bool autofocus;

  @override
  State<SecondaryAction> createState() => _SecondaryActionState();
}

class _SecondaryActionState extends State<SecondaryAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: _focused
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
