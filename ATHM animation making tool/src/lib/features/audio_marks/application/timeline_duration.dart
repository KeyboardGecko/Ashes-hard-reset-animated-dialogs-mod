import 'dart:math' as math;

import '../domain/entities/clip_mark.dart';

double selectedTrackEndMs(List<ClipMark> marks) => marks.fold<double>(
  1,
  (maximum, mark) => math.max(maximum, mark.startMs + (mark.durationMs ?? 1)),
);

double effectiveTimelineDurationMs({
  required double selectedTrackEndMs,
  double? explicitMinimumMs,
  double audioEndMs = 0,
}) =>
    math.max(selectedTrackEndMs, math.max(explicitMinimumMs ?? 0, audioEndMs));

class TimelineResizeResult {
  const TimelineResizeResult({required this.marks, required this.durationMs});

  final List<ClipMark> marks;
  final double durationMs;
}

/// Resizes the animation end. When the requested end crosses the end of the
/// last frame, that frame is trimmed instead of leaving an invisible minimum
/// at its previous end.
TimelineResizeResult resizeTimelineEnd({
  required List<ClipMark> source,
  required double requestedDurationMs,
  double audioEndMs = 0,
}) {
  final requested = math.max(1.0, math.max(requestedDurationMs, audioEndMs));
  if (source.isEmpty) {
    return TimelineResizeResult(marks: const [], durationMs: requested);
  }

  var endIndex = 0;
  var trackEnd = -double.infinity;
  for (var index = 0; index < source.length; index++) {
    final mark = source[index];
    final end = mark.startMs + (mark.durationMs ?? 1.0);
    if (end >= trackEnd) {
      trackEnd = end;
      endIndex = index;
    }
  }
  if (requested >= trackEnd) {
    return TimelineResizeResult(
      marks: List<ClipMark>.from(source),
      durationMs: requested,
    );
  }

  final last = source[endIndex];
  var otherTrackEnd = 1.0;
  for (var index = 0; index < source.length; index++) {
    if (index == endIndex) continue;
    final mark = source[index];
    otherTrackEnd = math.max(
      otherTrackEnd,
      mark.startMs + (mark.durationMs ?? 1.0),
    );
  }
  final minimumEnd = math.max(
    audioEndMs,
    math.max(otherTrackEnd, last.startMs + 1.0),
  );
  final resizedEnd = math.max(requested, minimumEnd);
  final resizedDuration = resizedEnd - last.startMs;
  final choices = last.durationChoicesMs == null
      ? null
      : List<double>.from(last.durationChoicesMs!);
  if (choices != null && choices.isNotEmpty) {
    final selected = last.selectedDurationChoiceIndex.clamp(
      0,
      choices.length - 1,
    );
    choices[selected] = resizedDuration;
  }

  final marks = List<ClipMark>.from(source);
  marks[endIndex] = last.copyWith(
    durationMs: resizedDuration,
    durationChoicesMs: choices,
  );
  return TimelineResizeResult(marks: marks, durationMs: resizedEnd);
}
