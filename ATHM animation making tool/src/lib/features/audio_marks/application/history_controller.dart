import 'dart:async';

import '../domain/entities/clip_mark.dart';

typedef HistoryAction = FutureOr<void> Function();

class _State {
  final List<ClipMark> marks;
  final Set<String> selection;
  const _State(this.marks, this.selection);
}

class _Entry {
  final _State before, after;
  final String? label;
  final HistoryAction? undoAction;
  final HistoryAction? redoAction;
  const _Entry(
    this.before,
    this.after, {
    this.label,
    this.undoAction,
    this.redoAction,
  });
}

class HistoryController {
  final void Function(List<ClipMark> marks, Set<String> selection) _apply;
  final List<_Entry> _undo = [];
  final List<_Entry> _redo = [];
  bool _applying = false;
  int maxDepth;

  HistoryController({
    required void Function(List<ClipMark>, Set<String>) apply,
    this.maxDepth = 30,
  }) : _apply = apply;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void record({
    required List<ClipMark> beforeMarks,
    required Set<String> beforeSel,
    required List<ClipMark> afterMarks,
    required Set<String> afterSel,
    String? label,
  }) {
    if (_applying) return;
    _undo.add(
      _Entry(
        _State(List<ClipMark>.from(beforeMarks), Set<String>.from(beforeSel)),
        _State(List<ClipMark>.from(afterMarks), Set<String>.from(afterSel)),
        label: label,
      ),
    );
    _redo.clear();
    if (_undo.length > maxDepth) _undo.removeAt(0);
  }

  void recordAction({
    required List<ClipMark> marks,
    required Set<String> selection,
    required HistoryAction undo,
    required HistoryAction redo,
    String? label,
  }) {
    if (_applying) return;
    final state = _State(
      List<ClipMark>.from(marks),
      Set<String>.from(selection),
    );
    _undo.add(
      _Entry(state, state, label: label, undoAction: undo, redoAction: redo),
    );
    _redo.clear();
    if (_undo.length > maxDepth) _undo.removeAt(0);
  }

  Future<bool> undo() async {
    if (!canUndo || _applying) return false;
    final e = _undo.removeLast();
    _redo.add(e);
    await _withApply(() async {
      _apply(e.before.marks, e.before.selection);
      await e.undoAction?.call();
    });
    return true;
  }

  Future<bool> redo() async {
    if (!canRedo || _applying) return false;
    final e = _redo.removeLast();
    _undo.add(e);
    await _withApply(() async {
      _apply(e.after.marks, e.after.selection);
      await e.redoAction?.call();
    });
    return true;
  }

  Future<void> _withApply(HistoryAction fn) async {
    _applying = true;
    try {
      await fn();
    } finally {
      _applying = false;
    }
  }
}
