import 'package:animaker/features/audio_marks/application/history_controller.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('undo and redo execute asynchronous editor actions', () async {
    var metadata = 'after';
    var appliedMarks = <ClipMark>[];
    final history = HistoryController(
      apply: (marks, selection) => appliedMarks = marks,
    );
    final mark = ClipMark(id: 'one', startMs: 0, label: 'FRAME');

    history.recordAction(
      marks: [mark],
      selection: {'one'},
      undo: () async => metadata = 'before',
      redo: () async => metadata = 'after',
      label: 'editor state',
    );

    expect(await history.undo(), isTrue);
    expect(metadata, 'before');
    expect(appliedMarks.single.id, 'one');
    expect(await history.redo(), isTrue);
    expect(metadata, 'after');
  });

  test('editor actions remain ordered with ordinary mark edits', () async {
    var metadata = false;
    var appliedMarks = <ClipMark>[];
    final history = HistoryController(
      apply: (marks, selection) => appliedMarks = marks,
    );
    final first = ClipMark(id: 'one', startMs: 0, label: 'A');
    final second = ClipMark(id: 'two', startMs: 100, label: 'B');

    history.recordAction(
      marks: [first],
      selection: const {},
      undo: () => metadata = false,
      redo: () => metadata = true,
    );
    metadata = true;
    history.record(
      beforeMarks: [first],
      beforeSel: const {},
      afterMarks: [first, second],
      afterSel: const {},
    );

    await history.undo();
    expect(appliedMarks.map((mark) => mark.id), ['one']);
    expect(metadata, isTrue);
    await history.undo();
    expect(metadata, isFalse);
  });
}
