import 'package:animaker/features/audio_marks/application/marks_to_athm_track.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClipMark mark(String id, double start, {bool locked = false}) => ClipMark(
    id: id,
    startMs: start,
    durationMs: 100,
    label: id.toUpperCase(),
    lockedSequenceId: locked ? 'lock_$id' : null,
  );

  test('adjacent locked frames merge even when toggled separately', () {
    final track = buildAthmTrackFromMarks([
      mark('a', 0),
      mark('b', 100, locked: true),
      mark('c', 200, locked: true),
      mark('d', 300),
    ]);

    expect(track, hasLength(3));
    expect(track[1], isA<AthmLockedSequence>());
    expect((track[1] as AthmLockedSequence).segments, hasLength(2));
  });

  test('non-adjacent locked frames remain separate sequences', () {
    final track = buildAthmTrackFromMarks([
      mark('a', 0, locked: true),
      mark('b', 100),
      mark('c', 200, locked: true),
    ]);

    expect(track.whereType<AthmLockedSequence>(), hasLength(2));
  });

  test('optional locked frames become one weighted track entry', () {
    final first = mark('a', 0, locked: true)..optionalChancePercent = 35;
    final second = mark('b', 100, locked: true)
      ..lockedSequenceId = first.lockedSequenceId
      ..optionalChancePercent = 35;
    final track = buildAthmTrackFromMarks([
      ClipMark(startMs: 0, durationMs: 100, label: 'BASE'),
      first.copyWith(startMs: 100),
      second.copyWith(startMs: 200),
    ]);

    final optional = track.whereType<AthmOptionalLockedSequence>().single;
    expect(optional.chancePercent, 35);
    expect(optional.items, hasLength(2));
  });

  test('saving can resolve editor labels to assigned image names', () {
    final track = buildAthmTrackFromMarks([
      ClipMark(startMs: 0, durationMs: 100, label: 'f'),
    ], resolveFrameName: (label) => label == 'f' ? 'ANDF' : label);

    final segment = (track.single as AthmSegmentEntry).segment;
    expect(segment.frameChoices, ['ANDF']);
  });
}
