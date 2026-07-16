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
