import 'package:animaker/models/timeline_clip_model.dart';
import 'package:flutter/material.dart';

class TimelineClip extends StatefulWidget {
  final TimelineClipModel clip;
  final double pxPerMs;
  final Function(double newStart, double newDuration) onUpdate;
  final List<TimelineClipModel> allClips;
  final VoidCallback? onDelete;
  final VoidCallback? onStartEdit;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.pxPerMs,
    required this.onUpdate,
    required this.allClips,
    this.onDelete,
    this.onStartEdit,
  });

  @override
  State<TimelineClip> createState() => _TimelineClipState();
}

class _TimelineClipState extends State<TimelineClip> {
  late double localStart;
  late double localDuration;
  String? activeHandle; // 'left' | 'right' | null

  static const double _handleWidth = 10.0;

  @override
  void initState() {
    super.initState();
    localStart = widget.clip.startMs;
    localDuration = widget.clip.durationMs;
  }

  void _updateClip() {
    widget.onUpdate(localStart, localDuration);
  }

  @override
  Widget build(BuildContext context) {
    final left = localStart * widget.pxPerMs;
    final width = localDuration * widget.pxPerMs;

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: width,
      child: GestureDetector(
        onSecondaryTap: () {
          if (widget.onDelete != null) {
            widget.onDelete!();
          }
        },
        onPanStart: (details) {
          final dx = details.localPosition.dx;
          widget.onStartEdit
              ?.call(); // 👈 вызываем только в начале редактирования

          setState(() {
            if (dx <= _handleWidth) {
              activeHandle = 'left';
            } else if (dx >= width - _handleWidth) {
              activeHandle = 'right';
            } else {
              activeHandle = null;
            }
          });
        },
        onPanUpdate: (details) {
          if (activeHandle == 'left') {
            setState(() {
              final delta = details.delta.dx / widget.pxPerMs;
              localStart += delta;
              localDuration -= delta;
              if (localDuration < 50) localDuration = 50;
              if (localStart < 0) localStart = 0;
            });
          } else if (activeHandle == 'right') {
            setState(() {
              localDuration += details.delta.dx / widget.pxPerMs;
              if (localDuration < 50) localDuration = 50;
            });
          } else {
            final proposedStart =
                localStart + details.delta.dx / widget.pxPerMs;

            final adjustedStart = getNonOverlappingStartMs(
              current: widget.clip,
              proposedStartMs: proposedStart,
              durationMs: localDuration,
              allClips: widget.allClips,
            );

            setState(() {
              localStart = adjustedStart;
            });
          }

          _updateClip();
        },
        onPanEnd: (_) {
          setState(() {
            activeHandle = null;
          });
        },
        child: Stack(
          children: [
            // фон и картинка
            Container(
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.3),
                border: Border.all(color: Colors.blueGrey),
                image: DecorationImage(
                  image: FileImage(widget.clip.imageFile),
                  fit: BoxFit.none,
                  repeat: ImageRepeat.repeatX,
                ),
              ),
            ),

            // левая ручка
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _handleWidth,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(
                  color: activeHandle == 'left'
                      ? Colors.white30
                      : Colors.transparent,
                ),
              ),
            ),

            // правая ручка
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _handleWidth,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(
                  color: activeHandle == 'right'
                      ? Colors.white30
                      : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double getNonOverlappingStartMs({
  required TimelineClipModel current,
  required double proposedStartMs,
  required double durationMs,
  required List<TimelineClipModel> allClips,
  double paddingMs = 0,
}) {
  double newStart = proposedStartMs;
  final newEnd = newStart + durationMs;

  for (final other in allClips) {
    if (other == current) continue;
    final otherStart = other.startMs;
    final otherEnd = other.startMs + other.durationMs;

    if (newEnd > otherStart && newStart < otherStart) {
      newStart = otherStart - durationMs - paddingMs;
    } else if (newStart < otherEnd && newEnd > otherEnd) {
      newStart = otherEnd + paddingMs;
    }
  }

  return newStart.clamp(0.0, double.infinity);
}
