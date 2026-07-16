// ====== Модель метки ======
class ClipMark {
  ClipMark({
    String? id, // ← НЕ required
    required this.startMs,
    this.durationMs,
    this.label,
    this.color,
  }) : id = id ?? genId(); // ← генерим, если не передали

  final String id; // ← НЕ nullable и стабильный
  double startMs;
  double? durationMs;
  String? label;
  int? color; // ARGB

  ClipMark copyWith({
    String? id, // обычно не трогаем
    double? startMs,
    double? durationMs,
    String? label,
    int? color,
  }) {
    return ClipMark(
      id: id ?? this.id, // ← сохраняем старый id по умолчанию
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      label: label ?? this.label,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, // ← сохраняем в JSON
    'startMs': startMs,
    'durationMs': durationMs,
    'label': label,
    'color': color,
  };

  factory ClipMark.fromJson(Map<String, dynamic> j) => ClipMark(
    id: (j['id'] as String?) ?? genId(), // ← если старый JSON без id
    startMs: (j['startMs'] as num).toDouble(),
    durationMs: (j['durationMs'] as num?)?.toDouble(),
    label: j['label'] as String?,
    color: j['color'] as int?,
  );

  @override
  bool operator ==(Object other) {
    return other is ClipMark &&
        other.id == id &&
        other.startMs == startMs &&
        other.durationMs == durationMs &&
        other.label == label &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(id, startMs, durationMs, label, color);
}

// Простой генератор id без зависимостей
String genId() => 'm_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';
int _idSeq = 0;
