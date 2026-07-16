import 'dart:math';

import '../domain/entities/clip_mark.dart';

class RandomPreviewSpan {
  const RandomPreviewSpan({
    required this.startMs,
    required this.endMs,
    required this.label,
  });

  final double startMs;
  final double endMs;
  final String? label;
}

/// Builds the concrete pass selected in the editor for each step.
///
/// Unlike [buildRandomPreviewTimeline], this never rerolls while playback is
/// running. Selection indices are editor/project metadata; LANGUAGE_ANIM still
/// keeps every authored alternative for the game runtime.
List<RandomPreviewSpan> buildSelectedPreviewTimeline(List<ClipMark> source) {
  if (source.isEmpty) return const [];
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final result = <RandomPreviewSpan>[];

  for (var index = 0; index < marks.length; index++) {
    final mark = marks[index];
    final frames = mark.frameChoices
        ?.where((value) => value.trim().isNotEmpty)
        .toList();
    final frameIndex = frames == null || frames.isEmpty
        ? 0
        : mark.selectedFrameChoiceIndex.clamp(0, frames.length - 1);
    final label = frames != null && frames.isNotEmpty
        ? frames[frameIndex].trim()
        : mark.label?.trim();

    final choices = mark.durationChoicesMs
        ?.where((value) => value.isFinite && value > 0)
        .toList();
    final fallbackDuration =
        mark.durationMs ??
        (index + 1 < marks.length
            ? marks[index + 1].startMs - mark.startMs
            : 100.0);
    final durationIndex = choices == null || choices.isEmpty
        ? 0
        : mark.selectedDurationChoiceIndex.clamp(0, choices.length - 1);
    final duration = choices != null && choices.isNotEmpty
        ? choices[durationIndex]
        : fallbackDuration.clamp(1.0, double.infinity).toDouble();

    result.add(
      RandomPreviewSpan(
        startMs: mark.startMs,
        endMs: mark.startMs + duration,
        label: label == null || label.isEmpty ? null : label,
      ),
    );
  }
  return result;
}

/// Resolves one concrete pass of an ATHM track.
///
/// Frame and duration choices are intentionally picked independently, matching
/// the v3 ZScript runtime. The authored [ClipMark] values are never mutated.
List<RandomPreviewSpan> buildRandomPreviewTimeline(
  List<ClipMark> source,
  Random random,
) {
  if (source.isEmpty) return const [];
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final result = <RandomPreviewSpan>[];
  var cursor = marks.first.startMs;

  for (var index = 0; index < marks.length; index++) {
    final mark = marks[index];
    final frames = mark.frameChoices
        ?.where((value) => value.trim().isNotEmpty)
        .toList();
    final label = frames != null && frames.isNotEmpty
        ? frames[random.nextInt(frames.length)].trim()
        : mark.label?.trim();

    final choices = mark.durationChoicesMs
        ?.where((value) => value.isFinite && value > 0)
        .toList();
    final fallbackDuration =
        mark.durationMs ??
        (index + 1 < marks.length
            ? marks[index + 1].startMs - mark.startMs
            : 100.0);
    final duration = choices != null && choices.isNotEmpty
        ? choices[random.nextInt(choices.length)]
        : fallbackDuration.clamp(1.0, double.infinity).toDouble();

    result.add(
      RandomPreviewSpan(
        startMs: cursor,
        endMs: cursor + duration,
        label: label == null || label.isEmpty ? null : label,
      ),
    );
    cursor += duration;
  }
  return result;
}
