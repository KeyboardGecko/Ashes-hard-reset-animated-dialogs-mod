import '../domain/entities/clip_mark.dart';

class CopiedFrame {
  const CopiedFrame({
    required this.durationMs,
    required this.label,
    required this.color,
    required this.frameChoices,
    required this.durationChoicesMs,
    required this.selectedFrameChoiceIndex,
    required this.selectedDurationChoiceIndex,
    required this.locked,
    required this.optionalChancePercent,
    required this.optionalIncludedInPreview,
    required this.optionalGroupKey,
    required this.optionalSoundName,
    required this.optionalSoundPath,
    required this.optionalSoundOffsetMs,
  });

  final double durationMs;
  final String? label;
  final int? color;
  final List<String>? frameChoices;
  final List<double>? durationChoicesMs;
  final int selectedFrameChoiceIndex;
  final int selectedDurationChoiceIndex;
  final bool locked;
  final double? optionalChancePercent;
  final bool optionalIncludedInPreview;
  final String? optionalGroupKey;
  final String? optionalSoundName;
  final String? optionalSoundPath;
  final double optionalSoundOffsetMs;
}

class FrameClipboardData {
  const FrameClipboardData(this.frames);

  final List<CopiedFrame> frames;
  bool get isEmpty => frames.isEmpty;
  double get durationMs =>
      frames.fold(0, (total, frame) => total + frame.durationMs);
}

class PasteFramesResult {
  const PasteFramesResult({
    required this.marks,
    required this.selectedIds,
    required this.insertionMs,
    required this.insertedDurationMs,
  });

  final List<ClipMark> marks;
  final Set<String> selectedIds;
  final double insertionMs;
  final double insertedDurationMs;
}

FrameClipboardData copySelectedFrames(
  List<ClipMark> source,
  Set<String> selectedIds,
) {
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final copied = <CopiedFrame>[];
  for (var index = 0; index < marks.length; index++) {
    final mark = marks[index];
    if (!selectedIds.contains(mark.id)) continue;
    final fallback = index + 1 < marks.length
        ? marks[index + 1].startMs - mark.startMs
        : 100.0;
    copied.add(
      CopiedFrame(
        durationMs: (mark.durationMs ?? fallback)
            .clamp(1.0, double.infinity)
            .toDouble(),
        label: mark.label,
        color: mark.color,
        frameChoices: mark.frameChoices == null
            ? null
            : List<String>.from(mark.frameChoices!),
        durationChoicesMs: mark.durationChoicesMs == null
            ? null
            : List<double>.from(mark.durationChoicesMs!),
        selectedFrameChoiceIndex: mark.selectedFrameChoiceIndex,
        selectedDurationChoiceIndex: mark.selectedDurationChoiceIndex,
        locked: mark.lockedSequenceId != null,
        optionalChancePercent: mark.optionalChancePercent,
        optionalIncludedInPreview: mark.optionalIncludedInPreview,
        optionalGroupKey: mark.optionalChancePercent == null
            ? null
            : mark.lockedSequenceId,
        optionalSoundName: mark.optionalSoundName,
        optionalSoundPath: mark.optionalSoundPath,
        optionalSoundOffsetMs: mark.optionalSoundOffsetMs,
      ),
    );
  }
  return FrameClipboardData(copied);
}

PasteFramesResult pasteFramesAtPlayhead({
  required List<ClipMark> source,
  required FrameClipboardData clipboard,
  required double playheadMs,
  required String Function() idFactory,
  required String Function() lockIdFactory,
}) {
  final marks = List<ClipMark>.from(source)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  if (clipboard.isEmpty) {
    return PasteFramesResult(
      marks: marks,
      selectedIds: const {},
      insertionMs: playheadMs,
      insertedDurationMs: 0,
    );
  }

  var insertionIndex = marks.indexWhere((mark) => mark.startMs >= playheadMs);
  if (insertionIndex < 0) insertionIndex = marks.length;
  final insertionMs = insertionIndex < marks.length
      ? marks[insertionIndex].startMs
      : (marks.isEmpty
            ? 0.0
            : marks.last.startMs + (marks.last.durationMs ?? 100));
  final insertedDuration = clipboard.durationMs;

  final result = <ClipMark>[];
  result.addAll(marks.take(insertionIndex));
  final insertedIds = <String>{};
  var cursor = insertionMs;
  String? activeLockId;
  String? activeOptionalGroupKey;
  for (final frame in clipboard.frames) {
    if (frame.locked) {
      if (activeLockId == null ||
          frame.optionalGroupKey != activeOptionalGroupKey) {
        activeLockId = lockIdFactory();
      }
      activeOptionalGroupKey = frame.optionalGroupKey;
    } else {
      activeLockId = null;
      activeOptionalGroupKey = null;
    }
    final id = idFactory();
    insertedIds.add(id);
    result.add(
      ClipMark(
        id: id,
        startMs: cursor,
        durationMs: frame.durationMs,
        label: frame.label,
        color: frame.color,
        frameChoices: frame.frameChoices == null
            ? null
            : List<String>.from(frame.frameChoices!),
        durationChoicesMs: frame.durationChoicesMs == null
            ? null
            : List<double>.from(frame.durationChoicesMs!),
        selectedFrameChoiceIndex: frame.selectedFrameChoiceIndex,
        selectedDurationChoiceIndex: frame.selectedDurationChoiceIndex,
        lockedSequenceId: activeLockId,
        optionalChancePercent: frame.optionalChancePercent,
        optionalIncludedInPreview: frame.optionalIncludedInPreview,
        optionalSoundName: frame.optionalSoundName,
        optionalSoundPath: frame.optionalSoundPath,
        optionalSoundOffsetMs: frame.optionalSoundOffsetMs,
      ),
    );
    cursor += frame.durationMs;
  }
  result.addAll(
    marks
        .skip(insertionIndex)
        .map((mark) => mark.copyWith(startMs: mark.startMs + insertedDuration)),
  );

  return PasteFramesResult(
    marks: result,
    selectedIds: insertedIds,
    insertionMs: insertionMs,
    insertedDurationMs: insertedDuration,
  );
}
