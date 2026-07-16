import 'package:animaker/features/audio_marks/application/frame_clipboard.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copy keeps chronological order and authored variants', () {
    final clipboard = copySelectedFrames(
      [
        ClipMark(
          id: 'b',
          startMs: 100,
          durationMs: 20,
          label: 'B',
          frameChoices: ['B', 'B2'],
          durationChoicesMs: [20, 30],
          selectedFrameChoiceIndex: 1,
          selectedDurationChoiceIndex: 1,
          lockedSequenceId: 'lock',
        ),
        ClipMark(id: 'a', startMs: 0, durationMs: 10, label: 'A'),
      ],
      {'a', 'b'},
    );

    expect(clipboard.frames.map((frame) => frame.label), ['A', 'B']);
    expect(clipboard.frames.last.frameChoices, ['B', 'B2']);
    expect(clipboard.frames.last.durationChoicesMs, [20, 30]);
    expect(clipboard.frames.last.selectedFrameChoiceIndex, 1);
    expect(clipboard.frames.last.selectedDurationChoiceIndex, 1);
    expect(clipboard.frames.last.locked, isTrue);
  });

  test('paste inserts before the next frame and shifts following frames', () {
    final source = [
      ClipMark(id: 'a', startMs: 0, durationMs: 100, label: 'A'),
      ClipMark(id: 'b', startMs: 100, durationMs: 100, label: 'B'),
      ClipMark(id: 'c', startMs: 200, durationMs: 100, label: 'C'),
    ];
    final clipboard = copySelectedFrames(source, {'b', 'c'});
    var id = 0;
    final result = pasteFramesAtPlayhead(
      source: source,
      clipboard: clipboard,
      playheadMs: 50,
      idFactory: () => 'new_${id++}',
      lockIdFactory: () => 'new_lock',
    );

    expect(result.insertionMs, 100);
    expect(result.insertedDurationMs, 200);
    expect(result.marks.map((mark) => mark.label), ['A', 'B', 'C', 'B', 'C']);
    expect(result.marks.map((mark) => mark.startMs), [0, 100, 200, 300, 400]);
    expect(result.selectedIds, {'new_0', 'new_1'});
  });

  test('paste preserves locked runs and gives them new group ids', () {
    final source = [
      ClipMark(id: 'a', startMs: 0, durationMs: 10, lockedSequenceId: 'old_1'),
      ClipMark(id: 'b', startMs: 10, durationMs: 10, lockedSequenceId: 'old_1'),
      ClipMark(id: 'c', startMs: 20, durationMs: 10),
      ClipMark(id: 'd', startMs: 30, durationMs: 10, lockedSequenceId: 'old_2'),
    ];
    final clipboard = copySelectedFrames(source, {'a', 'b', 'c', 'd'});
    var id = 0;
    var lock = 0;
    final result = pasteFramesAtPlayhead(
      source: const [],
      clipboard: clipboard,
      playheadMs: 500,
      idFactory: () => 'new_${id++}',
      lockIdFactory: () => 'lock_${lock++}',
    );

    expect(result.insertionMs, 0);
    expect(result.marks[0].lockedSequenceId, 'lock_0');
    expect(result.marks[1].lockedSequenceId, 'lock_0');
    expect(result.marks[2].lockedSequenceId, isNull);
    expect(result.marks[3].lockedSequenceId, 'lock_1');
  });
}
