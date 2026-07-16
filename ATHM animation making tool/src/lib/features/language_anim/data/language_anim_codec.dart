import '../domain/language_anim_models.dart';

class LanguageAnimCodec {
  const LanguageAnimCodec();

  LanguageAnimDocument decode(String source) {
    final values = _parseAssignments(source);
    final version = int.tryParse(values['ATHM_FORMAT'] ?? '');
    if (version == 3) return _decodeV3(values);
    if (version != null) {
      throw LanguageAnimFormatException(
        'Unsupported ATHM_FORMAT $version; expected 3.',
      );
    }
    return _decodeLegacy(values);
  }

  String encode(LanguageAnimDocument document) {
    _validateDocument(document);
    final out = StringBuffer()
      ..writeln('[default]')
      ..writeln()
      ..writeln('ATHM_FORMAT = "3";')
      ..writeln(
        'ATHM_CHARACTERS = "${document.characters.map((c) => c.id).join(',')}";',
      )
      ..writeln();

    for (final character in document.characters) {
      final prefix = 'ATHM_${character.id}';
      out.writeln(
        '${prefix}_ANIMATIONS = "${character.animations.map((a) => a.name).join(',')}";',
      );
      if (character.voiceMatches.isNotEmpty) {
        out.writeln(
          '${prefix}_VOICE_MATCH = "${character.voiceMatches.map(_escape).join(',')}";',
        );
      }
      if (_hasText(character.background)) {
        out.writeln(
          '${prefix}_BACKGROUND = "${_escape(character.background!)}";',
        );
      }
      if (_hasText(character.variantOf)) {
        out.writeln(
          '${prefix}_VARIANT_OF = "${_escape(character.variantOf!)}";',
        );
      }
      out.writeln();

      for (final animation in character.animations) {
        final key = '${prefix}_${animation.name}';
        out.writeln(
          '${key}_TRACK = "${_escape(encodeTrack(animation.track))}";',
        );
        out.writeln('${key}_LOOP = "${animation.loop}";');
        if (animation.durationMs != null) {
          out.writeln(
            '${key}_DURATION_MS = "${_formatNumber(animation.durationMs!)}";',
          );
        }
        if (_hasText(animation.sound)) {
          out.writeln('${key}_SOUND = "${_escape(animation.sound!)}";');
          if (animation.soundOffsetMs > 0) {
            out.writeln(
              '${key}_SOUND_OFFSET_MS = "${_formatNumber(animation.soundOffsetMs)}";',
            );
          }
        }
        out.writeln();
      }
    }
    return out.toString();
  }

  List<AthmTrackEntry> decodeTrack(String source) {
    final entries = <AthmTrackEntry>[];
    for (final raw in _splitTopLevel(source, ';')) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      if (token.startsWith('[')) {
        if (!token.endsWith(']')) {
          throw const LanguageAnimFormatException('Unclosed locked sequence.');
        }
        final inner = token.substring(1, token.length - 1);
        final items = _splitTopLevel(inner, ';')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .map(_decodeSegment)
            .toList();
        if (items.isEmpty) {
          throw const LanguageAnimFormatException('Locked sequence is empty.');
        }
        entries.add(AthmLockedSequence(items));
      } else {
        entries.add(AthmSegmentEntry(_decodeSegment(token)));
      }
    }
    if (entries.isEmpty) {
      throw const LanguageAnimFormatException('Animation track is empty.');
    }
    return entries;
  }

  String encodeTrack(List<AthmTrackEntry> track) {
    return track
        .map((entry) {
          return switch (entry) {
            AthmSegmentEntry(:final segment) => _encodeSegment(segment),
            AthmLockedSequence(:final items) =>
              '[${items.map(_encodeSegment).join(';')}]',
          };
        })
        .join(';');
  }

  LanguageAnimDocument _decodeV3(Map<String, String> values) {
    final characterIds = _splitCsv(values['ATHM_CHARACTERS'] ?? '');
    if (characterIds.isEmpty) {
      throw const LanguageAnimFormatException('ATHM_CHARACTERS is empty.');
    }

    final characters = <AthmCharacter>[];
    for (final id in characterIds) {
      final prefix = 'ATHM_$id';
      final animationNames = _splitCsv(values['${prefix}_ANIMATIONS'] ?? '');
      final animations = <AthmAnimation>[];
      for (final name in animationNames) {
        final key = '${prefix}_$name';
        final trackText = values['${key}_TRACK'];
        if (!_hasText(trackText)) {
          throw LanguageAnimFormatException('$key has no TRACK.');
        }
        animations.add(
          AthmAnimation(
            name: name,
            track: decodeTrack(trackText!),
            loop: _parseBool(values['${key}_LOOP']),
            sound: _nullIfEmpty(values['${key}_SOUND']),
            durationMs: _parseOptionalPositiveDouble(
              values['${key}_DURATION_MS'],
              '${key}_DURATION_MS',
            ),
            soundOffsetMs:
                _parseOptionalNonNegativeDouble(
                  values['${key}_SOUND_OFFSET_MS'],
                  '${key}_SOUND_OFFSET_MS',
                ) ??
                0,
          ),
        );
      }
      characters.add(
        AthmCharacter(
          id: id,
          animations: animations,
          voiceMatches: _splitCsv(values['${prefix}_VOICE_MATCH'] ?? ''),
          background: _nullIfEmpty(values['${prefix}_BACKGROUND']),
          variantOf: _nullIfEmpty(values['${prefix}_VARIANT_OF']),
        ),
      );
    }
    final document = LanguageAnimDocument(characters: characters);
    _validateDocument(document);
    return document;
  }

  double? _parseOptionalPositiveDouble(String? source, String key) {
    if (!_hasText(source)) return null;
    final value = double.tryParse(source!.trim());
    if (value == null || !value.isFinite || value <= 0) {
      throw LanguageAnimFormatException('$key must be a positive number.');
    }
    return value;
  }

  double? _parseOptionalNonNegativeDouble(String? source, String key) {
    if (!_hasText(source)) return null;
    final value = double.tryParse(source!.trim());
    if (value == null || !value.isFinite || value < 0) {
      throw LanguageAnimFormatException('$key must be a non-negative number.');
    }
    return value;
  }

  LanguageAnimDocument _decodeLegacy(Map<String, String> values) {
    final characterIds = <String>[];
    for (final key in values.keys) {
      final match = RegExp(r'^ANIMS_(.+)_LIST$').firstMatch(key);
      if (match == null) continue;
      final id = match.group(1)!;
      if (id == 'MAP' || id == 'RANGE_MAP' || id == 'NAME_MAP') continue;
      characterIds.add(id);
    }
    characterIds.sort();
    if (characterIds.isEmpty) {
      throw const LanguageAnimFormatException(
        'Neither ATHM v3 nor legacy animation lists were found.',
      );
    }

    final characters = <AthmCharacter>[];
    for (final id in characterIds) {
      final names = _splitCsv(values['ANIMS_${id}_LIST'] ?? '');
      final animations = <AthmAnimation>[];
      for (final name in names) {
        final key = 'ANIMS_${id}_$name';
        final frames = _decodeLegacyChoices(values['${key}_FRAMES'] ?? '');
        final durations = _decodeLegacyDurations(values['${key}_DURS'] ?? '');
        final count = frames.length < durations.length
            ? frames.length
            : durations.length;
        if (count == 0) continue;
        final track = <AthmTrackEntry>[
          for (var i = 0; i < count; i++)
            AthmSegmentEntry(
              AthmSegment(
                frameChoices: frames[i],
                durationChoicesMs: durations[i],
              ),
            ),
        ];
        animations.add(
          AthmAnimation(
            name: name,
            track: track,
            loop: _parseBool(values['${key}_LOOP']),
            sound: name == 'IDLE' ? null : name,
          ),
        );
      }
      characters.add(
        AthmCharacter(
          id: id,
          animations: animations,
          voiceMatches: _legacyVoiceMatches(id, values, characterIds),
          background: _nullIfEmpty(values['ANIMS_${id}_BGDEF']),
          variantOf: _legacyVariantOf(id, characterIds),
        ),
      );
    }
    return LanguageAnimDocument(
      characters: characters,
      wasMigratedFromLegacy: true,
    );
  }

  List<String> _legacyVoiceMatches(
    String characterId,
    Map<String, String> values,
    List<String> characterIds,
  ) {
    if (_legacyVariantOf(characterId, characterIds) != null) return const [];
    final result = <String>{};

    for (final prefix in _splitCsv(values['ANIMS_MAP_LIST'] ?? '')) {
      final owner = values['ANIMS_MAP_$prefix']?.trim();
      if (owner?.toUpperCase() == characterId.toUpperCase()) {
        result.add('${prefix.toUpperCase()}*');
      }
    }

    for (final series in _splitCsv(values['ANIMS_RANGE_MAP_LIST'] ?? '')) {
      var width = 1;
      final pattern = RegExp(
        '^${RegExp.escape(series)}(\\d+)\$',
        caseSensitive: false,
      );
      for (final id in characterIds) {
        for (final name in _splitCsv(values['ANIMS_${id}_LIST'] ?? '')) {
          final match = pattern.firstMatch(name);
          final digits = match?.group(1);
          if (digits != null && digits.length > width) width = digits.length;
        }
      }
      for (final item in _splitCsv(values['ANIMS_RANGE_MAP_$series'] ?? '')) {
        final colon = item.indexOf(':');
        final dash = item.indexOf('-');
        if (colon < 0 || dash < 0 || dash > colon) continue;
        final owner = item.substring(colon + 1).trim();
        if (owner.toUpperCase() != characterId.toUpperCase()) continue;
        final first = int.tryParse(item.substring(0, dash).trim());
        final last = int.tryParse(item.substring(dash + 1, colon).trim());
        if (first == null || last == null) continue;
        final prefix = series.toUpperCase();
        result.add(
          '$prefix${first.toString().padLeft(width, '0')}-'
          '$prefix${last.toString().padLeft(width, '0')}',
        );
      }
    }

    for (final voice in _splitCsv(values['ANIMS_NAME_MAP_LIST'] ?? '')) {
      final owner = values['ANIMS_NAME_MAP_$voice']?.trim();
      if (owner?.toUpperCase() == characterId.toUpperCase()) {
        result.add(voice.toUpperCase());
      }
    }
    return result.toList();
  }

  String? _legacyVariantOf(String id, List<String> characterIds) {
    if (!id.toUpperCase().endsWith('_ALT')) return null;
    final base = id.substring(0, id.length - 4);
    return characterIds.any(
          (candidate) => candidate.toUpperCase() == base.toUpperCase(),
        )
        ? base
        : null;
  }

  AthmSegment _decodeSegment(String source) {
    final at = _findTopLevel(source, '@');
    if (at < 1 || at == source.length - 1) {
      throw LanguageAnimFormatException('Invalid segment "$source".');
    }
    final frames = _decodePipeChoices(source.substring(0, at), 'frame');
    final durations = _decodePipeChoices(source.substring(at + 1), 'duration')
        .map((value) {
          final parsed = double.tryParse(value);
          if (parsed == null || parsed <= 0 || parsed > 60000) {
            throw LanguageAnimFormatException('Invalid duration "$value".');
          }
          return parsed;
        })
        .toList();
    return AthmSegment(frameChoices: frames, durationChoicesMs: durations);
  }

  String _encodeSegment(AthmSegment segment) {
    if (segment.frameChoices.isEmpty || segment.durationChoicesMs.isEmpty) {
      throw const LanguageAnimFormatException(
        'Segment choices cannot be empty.',
      );
    }
    return '${_encodeChoices(segment.frameChoices)}@'
        '${_encodeChoices(segment.durationChoicesMs.map(_formatNumber).toList())}';
  }

  void _validateDocument(LanguageAnimDocument document) {
    if (document.formatVersion != 3) {
      throw LanguageAnimFormatException(
        'Unsupported ATHM_FORMAT ${document.formatVersion}; expected 3.',
      );
    }
    if (document.characters.isEmpty) {
      throw const LanguageAnimFormatException('ATHM_CHARACTERS is empty.');
    }

    final characterIds = <String>{};
    final soundOwners = <String, String>{};
    final patternOwners = <String, String>{};
    for (final character in document.characters) {
      final id = character.id.trim().toUpperCase();
      if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(id)) {
        throw LanguageAnimFormatException(
          'Invalid character id "${character.id}".',
        );
      }
      if (!characterIds.add(id)) {
        throw LanguageAnimFormatException('Duplicate character "$id".');
      }
    }

    for (final character in document.characters) {
      final id = character.id.toUpperCase();
      final variantOf = character.variantOf?.trim().toUpperCase();
      if (variantOf != null && !characterIds.contains(variantOf)) {
        throw LanguageAnimFormatException(
          'Character $id references missing variant base "$variantOf".',
        );
      }
      if (character.animations.isEmpty) {
        throw LanguageAnimFormatException('Character $id has no animations.');
      }

      final animationNames = <String>{};
      for (final animation in character.animations) {
        final name = animation.name.trim().toUpperCase();
        if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(name)) {
          throw LanguageAnimFormatException(
            'Invalid animation name "${animation.name}" for $id.',
          );
        }
        if (!animationNames.add(name)) {
          throw LanguageAnimFormatException('Duplicate animation $id/$name.');
        }
        if (animation.track.isEmpty) {
          throw LanguageAnimFormatException(
            'Animation $id/$name has an empty track.',
          );
        }
        for (final segment in animation.segments) {
          if (segment.frameChoices.isEmpty ||
              segment.durationChoicesMs.isEmpty) {
            throw LanguageAnimFormatException(
              'Animation $id/$name has an empty segment.',
            );
          }
          if (segment.durationChoicesMs.any(
            (duration) =>
                !duration.isFinite || duration <= 0 || duration > 60000,
          )) {
            throw LanguageAnimFormatException(
              'Animation $id/$name has a duration outside 0..60000 ms.',
            );
          }
        }
        if (animation.soundOffsetMs < 0 || !animation.soundOffsetMs.isFinite) {
          throw LanguageAnimFormatException(
            'Animation $id/$name has an invalid SOUND_OFFSET_MS.',
          );
        }

        if (variantOf == null && name != 'IDLE' && _hasText(animation.sound)) {
          final sound = _normalizeSound(animation.sound!);
          final owner = '$id/$name';
          final previous = soundOwners[sound];
          if (previous != null && previous != owner) {
            throw LanguageAnimFormatException(
              'Sound "$sound" is owned by both $previous and $owner.',
            );
          }
          soundOwners[sound] = owner;
        }
      }
      if (!animationNames.contains('IDLE')) {
        throw LanguageAnimFormatException(
          'Character $id has no IDLE animation.',
        );
      }

      if (variantOf != null && character.voiceMatches.isNotEmpty) {
        throw LanguageAnimFormatException(
          'Variant $id must inherit voice matching from $variantOf.',
        );
      }
      for (final rawPattern in character.voiceMatches) {
        final pattern = rawPattern.trim().toUpperCase();
        final valid =
            RegExp(r'^[A-Z0-9_]+\*$').hasMatch(pattern) ||
            RegExp(r'^[A-Z]+\d+-[A-Z]+\d+$').hasMatch(pattern) ||
            RegExp(r'^[A-Z0-9_]+$').hasMatch(pattern);
        if (!valid) {
          throw LanguageAnimFormatException(
            'Invalid VOICE_MATCH "$rawPattern" for $id.',
          );
        }
        final previous = patternOwners[pattern];
        if (previous != null && previous != id) {
          throw LanguageAnimFormatException(
            'VOICE_MATCH "$pattern" is owned by both $previous and $id.',
          );
        }
        patternOwners[pattern] = id;
      }
    }
  }

  static String _normalizeSound(String value) {
    final normalized = value.replaceAll('\\', '/').split('/').last;
    final dot = normalized.lastIndexOf('.');
    return (dot > 0 ? normalized.substring(0, dot) : normalized).toUpperCase();
  }

  List<List<String>> _decodeLegacyChoices(String source) {
    return _splitTopLevel(source, ',')
        .map((token) => _decodeGroupedChoices(token, ','))
        .where((choices) => choices.isNotEmpty)
        .toList();
  }

  List<List<double>> _decodeLegacyDurations(String source) {
    return _splitTopLevel(source, ',')
        .map((token) => _decodeGroupedChoices(token, ','))
        .where((choices) => choices.isNotEmpty)
        .map(
          (choices) => choices.map((value) {
            final parsed = double.tryParse(value);
            if (parsed == null || parsed <= 0) {
              throw LanguageAnimFormatException(
                'Invalid legacy duration "$value".',
              );
            }
            return parsed;
          }).toList(),
        )
        .toList();
  }

  List<String> _decodeGroupedChoices(String source, String separator) {
    var token = source.trim();
    if (token.startsWith('(') && token.endsWith(')')) {
      token = token.substring(1, token.length - 1);
      return token
          .split(separator)
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return token.isEmpty ? const [] : [token];
  }

  List<String> _decodePipeChoices(String source, String label) {
    var token = source.trim();
    if (token.startsWith('(') && token.endsWith(')')) {
      token = token.substring(1, token.length - 1);
    }
    final choices = token
        .split('|')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (choices.isEmpty) {
      throw LanguageAnimFormatException('Empty $label choice.');
    }
    return choices;
  }

  String _encodeChoices(List<String> choices) =>
      choices.length == 1 ? choices.first : '(${choices.join('|')})';

  Map<String, String> _parseAssignments(String source) {
    final result = <String, String>{};
    final expression = RegExp(
      r'^\s*([A-Za-z0-9_]+)\s*=\s*"((?:\\.|[^"\\])*)"\s*;?\s*(?://.*)?$',
      multiLine: true,
    );
    for (final match in expression.allMatches(source)) {
      result[match.group(1)!] = _unescape(match.group(2)!);
    }
    return result;
  }

  List<String> _splitCsv(String source) => source
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  List<String> _splitTopLevel(String source, String separator) {
    final result = <String>[];
    var round = 0;
    var square = 0;
    var start = 0;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char == '(') round++;
      if (char == ')') round--;
      if (char == '[') square++;
      if (char == ']') square--;
      if (round < 0 || square < 0) {
        throw const LanguageAnimFormatException('Unexpected closing bracket.');
      }
      if (char == separator && round == 0 && square == 0) {
        result.add(source.substring(start, i));
        start = i + 1;
      }
    }
    if (round != 0 || square != 0) {
      throw const LanguageAnimFormatException('Unclosed bracket.');
    }
    result.add(source.substring(start));
    return result;
  }

  int _findTopLevel(String source, String wanted) {
    var round = 0;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char == '(') round++;
      if (char == ')') round--;
      if (char == wanted && round == 0) return i;
    }
    return -1;
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  static bool _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
  static String? _nullIfEmpty(String? value) =>
      _hasText(value) ? value!.trim() : null;
  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  static String _unescape(String value) =>
      value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
}
