import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animaker/models/timeline_clip_model.dart';

class AnimationPreview extends StatelessWidget {
  final Duration currentPosition;
  final List<TimelineClipModel> timelineClips;
  final File? defaultImageFile; // ✅ добавлено

  const AnimationPreview({
    super.key,
    required this.currentPosition,
    required this.timelineClips,
    this.defaultImageFile, // ✅ добавлено
  });

  @override
  Widget build(BuildContext context) {
    final currentFrame = _getCurrentFrame(
      currentPosition.inMilliseconds.toDouble(),
    );

    final imageToShow =
        currentFrame ?? defaultImageFile; // ✅ используем запасное

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            // border: Border.all(color: Colors.blueGrey, width: 2),
            // borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(8),
          child: Center(
            child: imageToShow != null
                ? Transform.scale(
                    scale: 2.0,
                    child: Image.file(imageToShow, fit: BoxFit.contain),
                  )
                : const Text(
                    'No active frame',
                    style: TextStyle(color: Colors.white54),
                  ),
          ),
        ),
        Container(),
      ],
    );
  }

  File? _getCurrentFrame(double currentMs) {
    for (final clip in timelineClips) {
      final start = clip.startMs;
      final end = start + clip.durationMs;
      if (currentMs >= start && currentMs <= end) {
        return clip.imageFile;
      }
    }
    return null;
  }
}
