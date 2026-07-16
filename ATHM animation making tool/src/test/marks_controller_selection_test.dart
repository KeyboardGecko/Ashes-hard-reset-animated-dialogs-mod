import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:animaker/features/audio_marks/domain/services/marks_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MarksController controller;
  late List<ClipMark> marks;

  setUp(() {
    controller = MarksController(getDurationMs: () => 1000);
    marks = [
      ClipMark(id: 'a', startMs: 0),
      ClipMark(id: 'b', startMs: 100),
      ClipMark(id: 'c', startMs: 200),
      ClipMark(id: 'd', startMs: 300),
    ];
    controller.setMarksSorted(marks);
  });

  test('replacing marks clears stale selection', () {
    controller.selectOnly('b');
    controller.setMarksSorted([ClipMark(id: 'x', startMs: 0)]);

    expect(controller.selection.value, isEmpty);
  });

  test('toggle selection adds and removes individual marks', () {
    controller.selectOnly('a');
    controller.toggleSelection('c');
    expect(controller.selection.value, {'a', 'c'});

    controller.toggleSelection('a');
    expect(controller.selection.value, {'c'});
  });

  test('shift-style range uses the last selection anchor', () {
    controller.selectOnly('b');
    controller.selectRangeTo('d');

    expect(controller.selection.value, {'b', 'c', 'd'});
  });

  test('marquee selection uses mark start positions', () {
    controller.applyRangeSelection(90, 210);

    expect(controller.selection.value, {'b', 'c'});
  });

  test('renaming a label updates the selected frame variant', () {
    controller.setMarksSorted([
      ClipMark(
        id: 'variants',
        startMs: 0,
        label: 'B',
        frameChoices: ['A', 'B', 'C'],
        selectedFrameChoiceIndex: 1,
      ),
    ]);

    controller.updateLabelAtIndex(0, 'NEW_FRAME');

    final updated = controller.marks.value.single;
    expect(updated.label, 'NEW_FRAME');
    expect(updated.frameChoices, ['A', 'NEW_FRAME', 'C']);
  });
}
