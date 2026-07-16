import 'dart:math';

import 'package:animaker/features/audio_marks/application/random_preview_timeline.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor preview uses the selected choices deterministically', () {
    final mark = ClipMark(
      startMs: 0,
      label: 'A',
      durationMs: 10,
      frameChoices: ['A', 'B'],
      durationChoicesMs: [10, 20],
      selectedFrameChoiceIndex: 1,
      selectedDurationChoiceIndex: 1,
    );

    final first = buildSelectedPreviewTimeline([mark]);
    final second = buildSelectedPreviewTimeline([mark]);

    expect(first.single.label, 'B');
    expect(first.single.endMs - first.single.startMs, 20);
    expect(second.single.label, 'B');
    expect(second.single.endMs - second.single.startMs, 20);
  });

  test('editor preview preserves frame positions after timeline drag', () {
    final marks = [
      ClipMark(startMs: 0, label: 'A', durationMs: 100),
      ClipMark(startMs: 450, label: 'B', durationMs: 100),
      ClipMark(startMs: 200, label: 'C', durationMs: 100),
    ];

    final pass = buildSelectedPreviewTimeline(marks);

    expect(pass.map((span) => span.label), ['A', 'C', 'B']);
    expect(pass.map((span) => span.startMs), [0, 200, 450]);
    expect(pass.map((span) => span.endMs), [100, 300, 550]);
  });

  test('resolves valid random frame and duration choices cumulatively', () {
    final marks = [
      ClipMark(
        startMs: 0,
        label: 'A',
        durationMs: 10,
        frameChoices: ['A', 'B'],
        durationChoicesMs: [10, 20],
      ),
      ClipMark(
        startMs: 10,
        label: 'C',
        durationMs: 30,
        frameChoices: ['C', 'D'],
        durationChoicesMs: [30, 40],
      ),
    ];

    final pass = buildRandomPreviewTimeline(marks, Random(7));

    expect(pass, hasLength(2));
    expect(['A', 'B'], contains(pass[0].label));
    expect(['C', 'D'], contains(pass[1].label));
    expect([10.0, 20.0], contains(pass[0].endMs - pass[0].startMs));
    expect([30.0, 40.0], contains(pass[1].endMs - pass[1].startMs));
    expect(pass[1].startMs, pass[0].endMs);
  });

  test('does not mutate authored marks', () {
    final mark = ClipMark(
      startMs: 0,
      label: 'FIRST',
      durationMs: 15,
      frameChoices: ['FIRST', 'SECOND'],
      durationChoicesMs: [15, 25],
    );

    buildRandomPreviewTimeline([mark], Random(1));

    expect(mark.label, 'FIRST');
    expect(mark.durationMs, 15);
    expect(mark.frameChoices, ['FIRST', 'SECOND']);
    expect(mark.durationChoicesMs, [15, 25]);
  });
}
