import 'package:animaker/features/audio_marks/application/optional_audio_timeline.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extends the last block frame and shifts following frames', () {
    final marks = [
      ClipMark(
        id: 'a',
        startMs: 0,
        durationMs: 100,
        durationChoicesMs: [100],
        lockedSequenceId: 'locked',
        optionalSoundOffsetMs: 50,
      ),
      ClipMark(
        id: 'b',
        startMs: 100,
        durationMs: 100,
        durationChoicesMs: [100],
        lockedSequenceId: 'locked',
        optionalSoundOffsetMs: 50,
      ),
      ClipMark(id: 'after', startMs: 200, durationMs: 100),
    ];

    final result = fitOptionalAudioGroup(
      marks: marks,
      groupId: 'locked',
      audioDurationMs: 300,
    );

    expect(result.extensionMs, 150);
    expect(result.marks[1].durationMs, 250);
    expect(result.marks[1].durationChoicesMs, [250]);
    expect(result.marks[2].startMs, 350);
  });

  test('uses the shortest duration variant as the safety bound', () {
    final marks = [
      ClipMark(
        id: 'a',
        startMs: 0,
        durationMs: 200,
        durationChoicesMs: [100, 200],
        selectedDurationChoiceIndex: 1,
        lockedSequenceId: 'locked',
      ),
    ];

    final result = fitOptionalAudioGroup(
      marks: marks,
      groupId: 'locked',
      audioDurationMs: 150,
    );

    expect(result.extensionMs, 50);
    expect(result.marks.single.durationChoicesMs, [150, 250]);
    expect(result.marks.single.durationMs, 250);
  });

  test('leaves a block unchanged when the audio already fits', () {
    final marks = [
      ClipMark(
        id: 'a',
        startMs: 0,
        durationMs: 500,
        durationChoicesMs: [500],
        lockedSequenceId: 'locked',
        optionalSoundOffsetMs: 100,
      ),
    ];

    final result = fitOptionalAudioGroup(
      marks: marks,
      groupId: 'locked',
      audioDurationMs: 300,
    );

    expect(result.extensionMs, 0);
    expect(result.marks, marks);
  });
}
