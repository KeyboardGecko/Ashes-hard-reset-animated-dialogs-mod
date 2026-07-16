import 'dart:math' as math;

import 'package:animaker/features/audio_marks/application/history_controller.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/clip_mark.dart';

typedef GetDurationMs = double Function();

class MarksController {
  final GetDurationMs getDurationMs;
  final HistoryController? history;
  final ValueNotifier<List<ClipMark>> marks = ValueNotifier<List<ClipMark>>([]);
  final ValueNotifier<Set<String>> selection = ValueNotifier<Set<String>>(
    <String>{},
  );
  String? _selectionAnchorId;

  MarksController({required this.getDurationMs, this.history});

  String? get singleSelectedId =>
      selection.value.length == 1 ? selection.value.first : null;

  void setMarksSorted(List<ClipMark> list) {
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    marks.value = List<ClipMark>.from(list);
    clearSelection();
  }

  void clearSelection() {
    selection.value = <String>{};
    _selectionAnchorId = null;
  }

  void selectOnly(String id) {
    if (!marks.value.any((mark) => mark.id == id)) return;
    selection.value = {id};
    _selectionAnchorId = id;
  }

  void toggleSelection(String id) {
    if (!marks.value.any((mark) => mark.id == id)) return;
    final next = Set<String>.from(selection.value);
    if (!next.add(id)) next.remove(id);
    selection.value = next;
    _selectionAnchorId = id;
  }

  void selectRangeTo(String id) {
    final end = marks.value.indexWhere((mark) => mark.id == id);
    if (end < 0) return;
    final anchor = marks.value.indexWhere(
      (mark) => mark.id == _selectionAnchorId,
    );
    if (anchor < 0) {
      selectOnly(id);
      return;
    }
    final lo = math.min(anchor, end);
    final hi = math.max(anchor, end);
    selection.value = marks.value
        .sublist(lo, hi + 1)
        .map((mark) => mark.id)
        .toSet();
  }

  void removeSelected() {
    if (selection.value.isEmpty) return;
    final beforeM = List<ClipMark>.from(marks.value);
    final beforeS = Set<String>.from(selection.value);

    final ids = selection.value;
    final next = List<ClipMark>.from(marks.value)
      ..removeWhere((m) => ids.contains(m.id));
    marks.value = next;
    selection.value = <String>{};

    history?.record(
      beforeMarks: beforeM,
      beforeSel: beforeS,
      afterMarks: List<ClipMark>.from(marks.value),
      afterSel: Set<String>.from(selection.value),
      label: 'delete-selected',
    );
  }

  void updateLabelAtIndex(int index, String? newLabel) {
    final beforeM = List<ClipMark>.from(marks.value);
    final beforeS = Set<String>.from(selection.value);

    final old = marks.value;
    if (index < 0 || index >= old.length) return;
    final cleaned = newLabel?.trim() ?? ''; // '' вместо null
    final current = old[index];
    final frameChoices = current.frameChoices == null
        ? null
        : List<String>.from(current.frameChoices!);
    if (frameChoices != null && frameChoices.isNotEmpty) {
      final selected = current.selectedFrameChoiceIndex.clamp(
        0,
        frameChoices.length - 1,
      );
      frameChoices[selected] = cleaned;
    }
    final updated = current.copyWith(
      label: cleaned,
      frameChoices: frameChoices,
    );
    final next = List<ClipMark>.from(old)..[index] = updated;
    marks.value = next;

    history?.record(
      beforeMarks: beforeM,
      beforeSel: beforeS,
      afterMarks: List<ClipMark>.from(marks.value),
      afterSel: Set<String>.from(selection.value),
      label: 'label',
    );
  }

  String addAt(double ms, {String? label, int? color, double epsilon = 20.0}) {
    final beforeM = List<ClipMark>.from(marks.value);
    final beforeS = Set<String>.from(selection.value);

    final list = List<ClipMark>.from(marks.value);
    final i = list.indexWhere((m) => (m.startMs - ms).abs() < epsilon);
    if (i != -1) {
      final existing = list[i];
      if ((label != null && label.trim().isNotEmpty) || color != null) {
        list[i] = existing.copyWith(
          label: (label == null || label.trim().isEmpty)
              ? existing.label
              : label.trim(),
          color: color ?? existing.color,
        );
        marks.value = list;
      }
      selection.value = {existing.id};
      history?.record(
        beforeMarks: beforeM,
        beforeSel: beforeS,
        afterMarks: List<ClipMark>.from(marks.value),
        afterSel: Set<String>.from(selection.value),
        label: 'select-existing',
      );
      return existing.id;
    }
    final normalized = (label ?? '').trim();

    final mark = ClipMark(
      id: genId(),
      startMs: ms,
      label: normalized,
      color: color,
    );
    int lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].startMs < mark.startMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    list.insert(lo, mark);
    marks.value = list;
    selection.value = {mark.id};

    history?.record(
      beforeMarks: beforeM,
      beforeSel: beforeS,
      afterMarks: List<ClipMark>.from(marks.value),
      afterSel: Set<String>.from(selection.value),
      label: 'add',
    );
    return mark.id;
  }

  String addMarkAt(
    double ms, {
    String? label,
    int? color,
    double epsilon = 20.0,
  }) => addAt(ms, label: label, color: color, epsilon: epsilon);

  void applyRangeSelection(double fromMs, double toMs) {
    final lo = math.min(fromMs, toMs), hi = math.max(fromMs, toMs);
    final ids = marks.value
        .where((m) => m.startMs >= lo && m.startMs <= hi)
        .map((m) => m.id)
        .toSet();
    selection.value = ids;
    _selectionAnchorId = ids.isEmpty
        ? null
        : marks.value.firstWhere((mark) => ids.contains(mark.id)).id;
  }

  void commitGroupMove(double deltaMs) {
    if (selection.value.isEmpty || deltaMs == 0) return;
    final beforeM = List<ClipMark>.from(marks.value);
    final beforeS = Set<String>.from(selection.value);

    final maxMs = getDurationMs();
    final list = List<ClipMark>.from(marks.value);
    for (int i = 0; i < list.length; i++) {
      final m = list[i];
      if (selection.value.contains(m.id)) {
        final next = (m.startMs + deltaMs).clamp(0.0, maxMs);
        list[i] = m.copyWith(startMs: next);
      }
    }
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    marks.value = list;

    history?.record(
      beforeMarks: beforeM,
      beforeSel: beforeS,
      afterMarks: List<ClipMark>.from(marks.value),
      afterSel: Set<String>.from(selection.value),
      label: 'move',
    );
  }

  void remove(ClipMark m) {
    final beforeM = List<ClipMark>.from(marks.value);
    final beforeS = Set<String>.from(selection.value);

    final list = List<ClipMark>.from(marks.value)..remove(m);
    marks.value = list;
    if (selection.value.contains(m.id)) {
      selection.value = Set<String>.from(selection.value)..remove(m.id);
    }

    history?.record(
      beforeMarks: beforeM,
      beforeSel: beforeS,
      afterMarks: List<ClipMark>.from(marks.value),
      afterSel: Set<String>.from(selection.value),
      label: 'remove',
    );
  }
}
