sealed class AthmTrackEntry {
  const AthmTrackEntry();

  Iterable<AthmSegment> get segments;
}

class AthmSegmentEntry extends AthmTrackEntry {
  const AthmSegmentEntry(this.segment);

  final AthmSegment segment;

  @override
  Iterable<AthmSegment> get segments => [segment];
}

class AthmLockedSequence extends AthmTrackEntry {
  const AthmLockedSequence(this.items);

  final List<AthmSegment> items;

  @override
  Iterable<AthmSegment> get segments => items;
}

class AthmOptionalLockedSequence extends AthmTrackEntry {
  const AthmOptionalLockedSequence({
    required this.items,
    this.chancePercent = 50,
    this.sound,
    this.soundOffsetMs = 0,
  });

  final List<AthmSegment> items;
  final double chancePercent;
  final String? sound;
  final double soundOffsetMs;

  @override
  Iterable<AthmSegment> get segments => items;
}

class AthmSegment {
  const AthmSegment({
    required this.frameChoices,
    required this.durationChoicesMs,
  });

  final List<String> frameChoices;
  final List<double> durationChoicesMs;

  String get previewFrame => frameChoices.first;
  double get previewDurationMs => durationChoicesMs.first;
}

class AthmAnimation {
  static const noBackground = '@none';

  const AthmAnimation({
    required this.name,
    required this.track,
    this.loop = false,
    this.sound,
    this.durationMs,
    this.soundOffsetMs = 0,
    this.background,
  });

  final String name;
  final List<AthmTrackEntry> track;
  final bool loop;
  final String? sound;
  final double? durationMs;
  final double soundOffsetMs;
  final String? background;

  bool get inheritsBackground => background == null;
  bool get disablesBackground =>
      background?.trim().toLowerCase() == noBackground;
  bool get hasCustomBackground => background != null && !disablesBackground;

  Iterable<AthmSegment> get segments => track.expand((entry) => entry.segments);
  double get previewDurationMs =>
      segments.fold(0, (total, segment) => total + segment.previewDurationMs);
  double get maximumPreviewDurationMs => segments.fold(
    0,
    (total, segment) =>
        total + segment.durationChoicesMs.reduce((a, b) => a > b ? a : b),
  );
  double get effectiveDurationMs {
    final preview = previewDurationMs;
    final minimum = durationMs;
    return minimum == null || minimum < preview ? preview : minimum;
  }

  AthmAnimation copyWith({
    String? name,
    List<AthmTrackEntry>? track,
    bool? loop,
    String? sound,
    double? durationMs,
    double? soundOffsetMs,
    String? background,
    bool clearSound = false,
    bool clearDuration = false,
    bool clearBackground = false,
  }) => AthmAnimation(
    name: name ?? this.name,
    track: track ?? this.track,
    loop: loop ?? this.loop,
    sound: clearSound ? null : (sound ?? this.sound),
    durationMs: clearDuration ? null : (durationMs ?? this.durationMs),
    soundOffsetMs: soundOffsetMs ?? this.soundOffsetMs,
    background: clearBackground ? null : (background ?? this.background),
  );
}

class AthmCharacter {
  const AthmCharacter({
    required this.id,
    required this.animations,
    this.voiceMatches = const [],
    this.background,
    this.variantOf,
  });

  final String id;
  final List<AthmAnimation> animations;
  final List<String> voiceMatches;
  final String? background;
  final String? variantOf;

  AthmCharacter copyWith({
    String? id,
    List<AthmAnimation>? animations,
    List<String>? voiceMatches,
    String? background,
    String? variantOf,
    bool clearBackground = false,
  }) => AthmCharacter(
    id: id ?? this.id,
    animations: animations ?? this.animations,
    voiceMatches: voiceMatches ?? this.voiceMatches,
    background: clearBackground ? null : (background ?? this.background),
    variantOf: variantOf ?? this.variantOf,
  );
}

class LanguageAnimDocument {
  const LanguageAnimDocument({
    required this.characters,
    this.formatVersion = 4,
    this.wasMigratedFromLegacy = false,
  });

  final int formatVersion;
  final List<AthmCharacter> characters;
  final bool wasMigratedFromLegacy;

  AthmCharacter? characterById(String id) {
    final wanted = id.toUpperCase();
    for (final character in characters) {
      if (character.id.toUpperCase() == wanted) return character;
    }
    return null;
  }

  LanguageAnimDocument copyWith({List<AthmCharacter>? characters}) =>
      LanguageAnimDocument(
        formatVersion: formatVersion,
        characters: characters ?? this.characters,
        wasMigratedFromLegacy: wasMigratedFromLegacy,
      );
}

class LanguageAnimFormatException implements Exception {
  const LanguageAnimFormatException(this.message);

  final String message;

  @override
  String toString() => 'LANGUAGE_ANIM format error: $message';
}
