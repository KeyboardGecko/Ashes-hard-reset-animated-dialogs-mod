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
  var skippedDuration = 0.0;

  for (var index = 0; index < marks.length;) {
    final mark = marks[index];
    if (mark.optionalChancePercent != null && !mark.optionalIncludedInPreview) {
      final groupId = mark.lockedSequenceId;
      do {
        skippedDuration += _selectedDuration(marks, index);
        index++;
      } while (index < marks.length &&
          marks[index].optionalChancePercent != null &&
          marks[index].lockedSequenceId == groupId);
      continue;
    }
    final frames = mark.frameChoices
        ?.where((value) => value.trim().isNotEmpty)
        .toList();
    final frameIndex = frames == null || frames.isEmpty
        ? 0
        : mark.selectedFrameChoiceIndex.clamp(0, frames.length - 1);
    final label = frames != null && frames.isNotEmpty
        ? frames[frameIndex].trim()
        : mark.label?.trim();

    final duration = _selectedDuration(marks, index);

    result.add(
      RandomPreviewSpan(
        startMs: mark.startMs - skippedDuration,
        endMs: mark.startMs - skippedDuration + duration,
        label: label == null || label.isEmpty ? null : label,
      ),
    );
    index++;
  }
  return result;
}

/// Resolves one concrete pass of an ATHM track.
///
/// Frame and duration choices are intentionally picked independently, matching
/// the v4 ZScript runtime. The authored [ClipMark] values are never mutated.
List<RandomPreviewSpan> buildRandomPreviewTimeline(
  List<ClipMark> source,
  Random random,
) {
  if (source.isEmpty) return const [];
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final result = <RandomPreviewSpan>[];
  var cursor = marks.first.startMs;
  final optionalDecisions = <String, bool>{};

  for (var index = 0; index < marks.length;) {
    final mark = marks[index];
    if (mark.optionalChancePercent != null) {
      final groupId = mark.lockedSequenceId ?? mark.id;
      final include = optionalDecisions.putIfAbsent(
        groupId,
        () => random.nextDouble() * 100 < mark.optionalChancePercent!,
      );
      if (!include) {
        do {
          index++;
        } while (index < marks.length &&
            marks[index].optionalChancePercent != null &&
            marks[index].lockedSequenceId == groupId);
        continue;
      }
    }
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
    index++;
  }
  return result;
}

double _selectedDuration(List<ClipMark> marks, int index) {
  final mark = marks[index];
  final choices = mark.durationChoicesMs
      ?.where((value) => value.isFinite && value > 0)
      .toList();
  final fallback =
      mark.durationMs ??
      (index + 1 < marks.length
          ? marks[index + 1].startMs - mark.startMs
          : 100.0);
  if (choices == null || choices.isEmpty) {
    return fallback.clamp(1.0, double.infinity).toDouble();
  }
  final selected = mark.selectedDurationChoiceIndex.clamp(
    0,
    choices.length - 1,
  );
  return choices[selected];
}
