// import 'dart:math' as math;

// class ClipMark {
//   final String id;
//   final double startMs;
//   final String? label;
//   final int? color; // ARGB int (e.g. 0xFF2196F3)

//   const ClipMark({
//     required this.id,
//     required this.startMs,
//     this.label,
//     this.color,
//   });

//   ClipMark copyWith({String? id, double? startMs, String? label, int? color}) {
//     return ClipMark(
//       id: id ?? this.id,
//       startMs: startMs ?? this.startMs,
//       label: label == null
//           ? this.label
//           : (label.trim().isEmpty ? null : label.trim()),
//       color: color ?? this.color,
//     );
//   }
// }

// /// Простенький генератор id (достаточно уникален для локального UI)
// String genId() {
//   final t = DateTime.now().microsecondsSinceEpoch;
//   final r = math.Random().nextInt(1 << 32);
//   return 'm_${t.toRadixString(36)}_${r.toRadixString(36)}';
// }

// ====== Модель метки ======
class ClipMark {
  ClipMark({
    String? id, // ← НЕ required
    required this.startMs,
    this.durationMs,
    this.label,
    this.color,
    this.frameChoices,
    this.durationChoicesMs,
    this.selectedFrameChoiceIndex = 0,
    this.selectedDurationChoiceIndex = 0,
    this.lockedSequenceId,
    this.optionalChancePercent,
    this.optionalIncludedInPreview = true,
    this.optionalSoundName,
    this.optionalSoundPath,
    this.optionalSoundOffsetMs = 0,
  }) : id = id ?? genId(); // ← генерим, если не передали

  final String id; // ← НЕ nullable и стабильный
  double startMs;
  double? durationMs;
  String? label;
  int? color; // ARGB
  List<String>? frameChoices;
  List<double>? durationChoicesMs;
  int selectedFrameChoiceIndex;
  int selectedDurationChoiceIndex;
  String? lockedSequenceId;
  double? optionalChancePercent;
  bool optionalIncludedInPreview;
  String? optionalSoundName;
  String? optionalSoundPath;
  double optionalSoundOffsetMs;

  ClipMark copyWith({
    String? id, // обычно не трогаем
    double? startMs,
    double? durationMs,
    String? label,
    int? color,
    List<String>? frameChoices,
    List<double>? durationChoicesMs,
    int? selectedFrameChoiceIndex,
    int? selectedDurationChoiceIndex,
    String? lockedSequenceId,
    bool clearLockedSequenceId = false,
    double? optionalChancePercent,
    bool clearOptionalChancePercent = false,
    bool? optionalIncludedInPreview,
    String? optionalSoundName,
    bool clearOptionalSoundName = false,
    String? optionalSoundPath,
    bool clearOptionalSoundPath = false,
    double? optionalSoundOffsetMs,
  }) {
    return ClipMark(
      id: id ?? this.id, // ← сохраняем старый id по умолчанию
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      label: label ?? this.label,
      color: color ?? this.color,
      frameChoices: frameChoices ?? this.frameChoices,
      durationChoicesMs: durationChoicesMs ?? this.durationChoicesMs,
      selectedFrameChoiceIndex:
          selectedFrameChoiceIndex ?? this.selectedFrameChoiceIndex,
      selectedDurationChoiceIndex:
          selectedDurationChoiceIndex ?? this.selectedDurationChoiceIndex,
      lockedSequenceId: clearLockedSequenceId
          ? null
          : lockedSequenceId ?? this.lockedSequenceId,
      optionalChancePercent: clearOptionalChancePercent
          ? null
          : optionalChancePercent ?? this.optionalChancePercent,
      optionalIncludedInPreview:
          optionalIncludedInPreview ?? this.optionalIncludedInPreview,
      optionalSoundName: clearOptionalSoundName
          ? null
          : optionalSoundName ?? this.optionalSoundName,
      optionalSoundPath: clearOptionalSoundPath
          ? null
          : optionalSoundPath ?? this.optionalSoundPath,
      optionalSoundOffsetMs:
          optionalSoundOffsetMs ?? this.optionalSoundOffsetMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, // ← сохраняем в JSON
    'startMs': startMs,
    'durationMs': durationMs,
    'label': label,
    'color': color,
    'frameChoices': frameChoices,
    'durationChoicesMs': durationChoicesMs,
    'selectedFrameChoiceIndex': selectedFrameChoiceIndex,
    'selectedDurationChoiceIndex': selectedDurationChoiceIndex,
    'lockedSequenceId': lockedSequenceId,
    'optionalChancePercent': optionalChancePercent,
    'optionalIncludedInPreview': optionalIncludedInPreview,
    'optionalSoundName': optionalSoundName,
    'optionalSoundPath': optionalSoundPath,
    'optionalSoundOffsetMs': optionalSoundOffsetMs,
  };

  factory ClipMark.fromJson(Map<String, dynamic> j) => ClipMark(
    id: (j['id'] as String?) ?? genId(), // ← если старый JSON без id
    startMs: (j['startMs'] as num).toDouble(),
    durationMs: (j['durationMs'] as num?)?.toDouble(),
    label: j['label'] as String?,
    color: j['color'] as int?,
    frameChoices: (j['frameChoices'] as List?)?.cast<String>(),
    durationChoicesMs: (j['durationChoicesMs'] as List?)
        ?.map((value) => (value as num).toDouble())
        .toList(),
    selectedFrameChoiceIndex:
        (j['selectedFrameChoiceIndex'] as num?)?.toInt() ?? 0,
    selectedDurationChoiceIndex:
        (j['selectedDurationChoiceIndex'] as num?)?.toInt() ?? 0,
    lockedSequenceId: j['lockedSequenceId'] as String?,
    optionalChancePercent: (j['optionalChancePercent'] as num?)?.toDouble(),
    optionalIncludedInPreview: j['optionalIncludedInPreview'] as bool? ?? true,
    optionalSoundName: j['optionalSoundName'] as String?,
    optionalSoundPath: j['optionalSoundPath'] as String?,
    optionalSoundOffsetMs:
        (j['optionalSoundOffsetMs'] as num?)?.toDouble() ?? 0,
  );

  @override
  bool operator ==(Object other) {
    return other is ClipMark &&
        other.id == id &&
        other.startMs == startMs &&
        other.durationMs == durationMs &&
        other.label == label &&
        other.color == color &&
        _listEquals(other.frameChoices, frameChoices) &&
        _listEquals(other.durationChoicesMs, durationChoicesMs) &&
        other.selectedFrameChoiceIndex == selectedFrameChoiceIndex &&
        other.selectedDurationChoiceIndex == selectedDurationChoiceIndex &&
        other.lockedSequenceId == lockedSequenceId &&
        other.optionalChancePercent == optionalChancePercent &&
        other.optionalIncludedInPreview == optionalIncludedInPreview &&
        other.optionalSoundName == optionalSoundName &&
        other.optionalSoundPath == optionalSoundPath &&
        other.optionalSoundOffsetMs == optionalSoundOffsetMs;
  }

  @override
  int get hashCode => Object.hash(
    id,
    startMs,
    durationMs,
    label,
    color,
    Object.hashAll(frameChoices ?? const []),
    Object.hashAll(durationChoicesMs ?? const []),
    selectedFrameChoiceIndex,
    selectedDurationChoiceIndex,
    lockedSequenceId,
    optionalChancePercent,
    optionalIncludedInPreview,
    optionalSoundName,
    optionalSoundPath,
    optionalSoundOffsetMs,
  );
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Простой генератор id без зависимостей
String genId() => 'm_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';
int _idSeq = 0;
