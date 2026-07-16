import '../../language_anim/domain/language_anim_models.dart';
import '../domain/entities/clip_mark.dart';

List<AthmTrackEntry> buildAthmTrackFromMarks(List<ClipMark> source) {
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final result = <AthmTrackEntry>[];
  var index = 0;
  while (index < marks.length) {
    final locked = marks[index].lockedSequenceId != null;
    final segments = <AthmSegment>[];
    do {
      final mark = marks[index];
      final nextStart = index + 1 < marks.length
          ? marks[index + 1].startMs
          : null;
      final duration = nextStart == null
          ? (mark.durationMs ?? 100.0)
          : (nextStart - mark.startMs).clamp(1.0, double.infinity).toDouble();
      final frames = List<String>.from(
        mark.frameChoices ?? [mark.label ?? 'FRAME'],
      );
      if (frames.isEmpty) frames.add(mark.label ?? 'FRAME');
      if (frames.length == 1) {
        frames[0] = (mark.label?.trim().isNotEmpty ?? false)
            ? mark.label!.trim()
            : frames[0];
      }
      final durations = List<double>.from(mark.durationChoicesMs ?? [duration]);
      if (durations.isEmpty) durations.add(duration);
      if (durations.length == 1) durations[0] = duration;
      segments.add(
        AthmSegment(frameChoices: frames, durationChoicesMs: durations),
      );
      index++;
    } while (locked &&
        index < marks.length &&
        marks[index].lockedSequenceId != null);

    if (locked) {
      result.add(AthmLockedSequence(segments));
    } else {
      result.addAll(segments.map(AthmSegmentEntry.new));
    }
  }
  return result;
}
