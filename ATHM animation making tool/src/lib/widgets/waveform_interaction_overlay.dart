import 'package:flutter/material.dart';

class WaveformInteractionOverlay extends StatelessWidget {
  final Widget child;
  final void Function(Offset globalPosition, BuildContext context)
  onTapSeekFromGlobal;
  final ScrollController scrollController;
  final bool isDragging;
  final void Function(bool) onDragChange;

  const WaveformInteractionOverlay({
    super.key,
    required this.child,
    required this.onTapSeekFromGlobal,
    required this.scrollController,
    required this.isDragging,
    required this.onDragChange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (!isDragging) {
          onTapSeekFromGlobal(details.globalPosition, context);
        }
      },
      onPanStart: (_) => onDragChange(true),
      onPanUpdate: (details) {
        scrollController.jumpTo(
          (scrollController.offset - details.delta.dx).clamp(
            0.0,
            scrollController.position.maxScrollExtent,
          ),
        );
      },
      onPanEnd: (_) => onDragChange(false),
      child: child,
    );
  }
}
