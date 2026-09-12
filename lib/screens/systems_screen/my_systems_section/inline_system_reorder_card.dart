import 'package:flutter/material.dart';

/// Touch drag/drop and the lifted-card treatment shared by both systems views.
class InlineSystemReorderCard extends StatelessWidget {
  const InlineSystemReorderCard({
    super.key,
    required this.enabled,
    required this.folderName,
    required this.lifted,
    required this.onLift,
    required this.onMoveHere,
    required this.child,
    this.onDrop,
    this.onDragUpdate,
  });

  final bool enabled;
  final String? folderName;
  final bool lifted;
  final VoidCallback onLift;
  final VoidCallback onMoveHere;
  final VoidCallback? onDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || folderName == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != folderName,
        onAcceptWithDetails: (_) => onMoveHere(),
        builder: (context, candidates, rejected) {
          final highlighted = lifted || candidates.isNotEmpty;
          return LongPressDraggable<String>(
            data: folderName!,
            maxSimultaneousDrags: 1,
            onDragStarted: onLift,
            onDragUpdate: (details) =>
                onDragUpdate?.call(details.globalPosition),
            onDragEnd: (_) => onDrop?.call(),
            feedback: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Material(
                color: Colors.transparent,
                elevation: 16,
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: child),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: Matrix4.translationValues(0, highlighted ? -8 : 0, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: highlighted
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
                boxShadow: highlighted
                    ? const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
