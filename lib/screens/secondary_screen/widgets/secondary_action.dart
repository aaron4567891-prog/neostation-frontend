import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A controller-focusable counterpart to [GestureDetector] for controls shown
/// by the secondary Flutter engine.
class LaunchOnTopIntent extends Intent {
  const LaunchOnTopIntent();
}

class SecondaryAction extends StatefulWidget {
  const SecondaryAction({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onLaunchOnTop,
    this.behavior,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onLaunchOnTop;
  final HitTestBehavior? behavior;
  final bool autofocus;

  @override
  State<SecondaryAction> createState() => _SecondaryActionState();
}

class _SecondaryActionState extends State<SecondaryAction> {
  bool _focused = false;

  void _activate() {
    widget.onTap?.call();
  }

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
        SingleActivator(LogicalKeyboardKey.gameButtonY): LaunchOnTopIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
        ),
        SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
          TraversalDirection.left,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
          TraversalDirection.right,
        ),
      },
      actions: <Type, Action<Intent>>{
        LaunchOnTopIntent: CallbackAction<LaunchOnTopIntent>(
          onInvoke: (_) {
            widget.onLaunchOnTop?.call();
            return null;
          },
        ),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      // Show the selected control even when focus was acquired after a touch.
      // onShowFocusHighlight stays false in Flutter's touch highlight mode.
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap == null ? null : _activate,
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
