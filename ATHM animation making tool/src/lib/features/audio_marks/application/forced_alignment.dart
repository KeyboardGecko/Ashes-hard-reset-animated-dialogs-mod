import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/entities/clip_mark.dart';
import 'audio_transcode.dart';
import 'mfa_runtime.dart';

enum MfaLanguage { english, russian }

extension MfaLanguageInfo on MfaLanguage {
  String get label => switch (this) {
    MfaLanguage.english => 'English',
    MfaLanguage.russian => 'Russian',
  };

  String get modelName => switch (this) {
    MfaLanguage.english => 'english_mfa',
    MfaLanguage.russian => 'russian_mfa',
  };
}

class AlignedPhone {
  const AlignedPhone({
    required this.startMs,
    required this.endMs,
    required this.phone,
  });

  final double startMs;
  final double endMs;
  final String phone;
}

class GeneratedLipSyncTrack {
  const GeneratedLipSyncTrack({
    required this.marks,
    required this.durationMs,
    this.unmappedPhones = const [],
  });

  final List<ClipMark> marks;
  final double durationMs;
  final List<String> unmappedPhones;
}

class MfaAlignmentException implements Exception {
  const MfaAlignmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TextGridPhoneParser {
  const TextGridPhoneParser();

  List<AlignedPhone> parse(String source) {
    final tierName = RegExp(
      r'name\s*=\s*"phones?"',
      caseSensitive: false,
    ).firstMatch(source);
    if (tierName == null) {
      throw const FormatException('TextGrid has no phones tier.');
    }

    final tierRemainder = source.substring(tierName.end);
    final nextTier = RegExp(
      r'\n\s*item\s*\[\d+\]\s*:',
      caseSensitive: false,
    ).firstMatch(tierRemainder);
    final tier = tierRemainder.substring(0, nextTier?.start);
    final intervalPattern = RegExp(
      r'intervals\s*\[\d+\]\s*:\s*'
      r'xmin\s*=\s*([\d.eE+-]+)\s*'
      r'xmax\s*=\s*([\d.eE+-]+)\s*'
      r'text\s*=\s*"([^"]*)"',
      caseSensitive: false,
      dotAll: true,
    );
    final result = <AlignedPhone>[];
    for (final match in intervalPattern.allMatches(tier)) {
      final startSeconds = double.tryParse(match.group(1)!);
      final endSeconds = double.tryParse(match.group(2)!);
      if (startSeconds == null || endSeconds == null) continue;
      result.add(
        AlignedPhone(
          startMs: startSeconds * 1000,
          endMs: endSeconds * 1000,
          phone: match.group(3)!.trim(),
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException('The phones tier contains no intervals.');
    }
    return result;
  }
}

class AthmVisemeTrackBuilder {
  const AthmVisemeTrackBuilder({
    this.minimumPoseDurationMs = 50,
    this.closedMouthLeadMs = 40,
  });

  final double minimumPoseDurationMs;
  final double closedMouthLeadMs;

  GeneratedLipSyncTrack build({
    required List<AlignedPhone> phones,
    required String prefix,
  }) {
    final normalizedPrefix = prefix.trim().toUpperCase();
    if (normalizedPrefix.isEmpty) {
      throw const FormatException('Character prefix is empty.');
    }
    if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(normalizedPrefix)) {
      throw const FormatException(
        'Character prefix may contain only A-Z, 0-9 and underscore.',
      );
    }
    if (phones.isEmpty) {
      throw const FormatException('Alignment contains no phones.');
    }

    final unmapped = <String>{};
    final spans = <_PoseSpan>[];
    for (final phone in phones) {
      if (phone.endMs <= phone.startMs) continue;
      final mapping = _poseForPhone(phone.phone);
      if (!mapping.known && phone.phone.trim().isNotEmpty) {
        unmapped.add(phone.phone.trim());
      }
      if (spans.isNotEmpty && spans.last.pose == mapping.pose) {
        spans.last.endMs = phone.endMs;
      } else {
        spans.add(
          _PoseSpan(
            startMs: phone.startMs,
            endMs: phone.endMs,
            pose: mapping.pose,
          ),
        );
      }
    }
    if (spans.isEmpty) {
      throw const FormatException('Alignment contains no usable intervals.');
    }

    _applyClosedMouthLead(spans);
    _removeShortPoses(spans);
    _mergeAdjacentPoses(spans);

    final marks = <ClipMark>[];
    for (final span in spans) {
      final frame = '$normalizedPrefix${span.pose}';
      if (frame.length > 6) {
        throw FormatException(
          'Generated frame name "$frame" exceeds ATHM\'s 6-character frame limit.',
        );
      }
      marks.add(
        ClipMark(
          startMs: span.startMs,
          durationMs: span.endMs - span.startMs,
          label: frame,
        ),
      );
    }
    return GeneratedLipSyncTrack(
      marks: marks,
      durationMs: spans.last.endMs,
      unmappedPhones: unmapped.toList()..sort(),
    );
  }

  void _applyClosedMouthLead(List<_PoseSpan> spans) {
    if (closedMouthLeadMs <= 0) return;
    for (var index = 1; index < spans.length; index++) {
      final current = spans[index];
      if (current.pose != 'M') continue;
      final previous = spans[index - 1];
      final newStart = (current.startMs - closedMouthLeadMs).clamp(
        previous.startMs,
        current.startMs,
      );
      previous.endMs = newStart;
      current.startMs = newStart;
    }
  }

  void _removeShortPoses(List<_PoseSpan> spans) {
    if (minimumPoseDurationMs <= 0 || spans.length < 2) return;
    var index = 0;
    while (index < spans.length && spans.length > 1) {
      final span = spans[index];
      if (span.pose == 'M' ||
          span.endMs - span.startMs >= minimumPoseDurationMs) {
        index++;
        continue;
      }
      if (index > 0 &&
          index + 1 < spans.length &&
          spans[index - 1].pose == spans[index + 1].pose) {
        spans[index - 1].endMs = spans[index + 1].endMs;
        spans.removeAt(index + 1);
        spans.removeAt(index);
        index = (index - 1).clamp(0, spans.length);
      } else if (index == 0) {
        spans[1].startMs = span.startMs;
        spans.removeAt(0);
      } else {
        spans[index - 1].endMs = span.endMs;
        spans.removeAt(index);
        index--;
      }
    }
  }

  void _mergeAdjacentPoses(List<_PoseSpan> spans) {
    var index = 1;
    while (index < spans.length) {
      if (spans[index - 1].pose == spans[index].pose) {
        spans[index - 1].endMs = spans[index].endMs;
        spans.removeAt(index);
      } else {
        index++;
      }
    }
  }

  _PoseMapping _poseForPhone(String source) {
    var phone = source.trim().toLowerCase();
    if (phone.isEmpty || phone == 'sil' || phone == 'sp') {
      return const _PoseMapping('DEF', true);
    }
    if (phone == 'spn') return const _PoseMapping('DEF', false);
    phone = phone
        .replaceAll(RegExp(r'\d'), '')
        .replaceAll('ˈ', '')
        .replaceAll('ˌ', '')
        .replaceAll('ː', '')
        .replaceAll('ʲ', '')
        .replaceAll('̪', '')
        .replaceAll('͡', '')
        .replaceAll('͜', '');

    const groups = <String, Set<String>>{
      'M': {'p', 'b', 'm'},
      'F': {'f', 'v'},
      'O': {'o', 'oʊ', 'ɔ', 'ɒ', 'aʊ', 'ɔɪ', 'ɵ'},
      'U': {'u', 'ʊ', 'ʉ', 'w'},
      'S': {
        's',
        'z',
        'ʃ',
        'ʒ',
        'ʂ',
        'ʐ',
        'ɕ',
        't',
        'd',
        'ts',
        'tɕ',
        'tʂ',
        'tʃ',
        'dʒ',
        'θ',
        'ð',
        'h',
        'x',
        'ç',
        'ɣ',
        'c',
        'dz',
      },
      'N': {'n', 'ŋ', 'ɲ', 'l', 'ɫ', 'ʎ', 'r', 'ɹ', 'j', 'k', 'g', 'ɡ', 'ɟ'},
      'EI': {'i', 'ɪ', 'e', 'eɪ', 'ɛ'},
      'A': {'a', 'æ', 'ɑ', 'ɐ', 'ə', 'ʌ', 'ɨ'},
    };
    for (final entry in groups.entries) {
      if (entry.value.contains(phone)) return _PoseMapping(entry.key, true);
    }
    return const _PoseMapping('N', false);
  }
}

class MfaForcedAlignmentService {
  const MfaForcedAlignmentService({
    this.parser = const TextGridPhoneParser(),
    this.runtimeManager,
  });

  final TextGridPhoneParser parser;
  final MfaRuntimeManager? runtimeManager;

  Future<GeneratedLipSyncTrack> align({
    required String audioPath,
    required String transcript,
    required String prefix,
    required MfaLanguage language,
    double minimumPoseDurationMs = 50,
    double closedMouthLeadMs = 40,
    MfaProgressCallback? onProgress,
  }) async {
    if (transcript.trim().isEmpty) {
      throw const MfaAlignmentException('Enter the spoken transcript first.');
    }
    final audio = File(audioPath);
    if (!await audio.exists()) {
      throw MfaAlignmentException('Audio file was not found: $audioPath');
    }

    final runtime = runtimeManager ?? MfaRuntimeManager();
    await runtime.ensureReady(
      language.modelName,
      languageLabel: language.label,
      onProgress: onProgress,
    );

    final temp = await Directory.systemTemp.createTemp('athm_mfa_');
    try {
      final corpus = Directory(p.join(temp.path, 'corpus'));
      final output = Directory(p.join(temp.path, 'aligned'));
      await corpus.create();
      await output.create();
      final wavPath = p.join(corpus.path, 'line.wav');
      await _prepareMonoWav(audioPath, wavPath);
      await File(
        p.join(corpus.path, 'line.txt'),
      ).writeAsString(transcript.trim(), encoding: utf8);

      onProgress?.call('Aligning speech and building the lipsync track...');
      final model = language.modelName;
      final arguments = [
        'align',
        '--clean',
        '--single_speaker',
        '--output_format',
        'long_textgrid',
        corpus.path,
        model,
        model,
        output.path,
      ];
      ProcessResult process;
      try {
        process = await runtime.runMfa(arguments);
      } on ProcessException catch (error) {
        throw MfaAlignmentException(
          'Could not start the portable MFA runtime.\n$error',
        );
      }
      if (process.exitCode != 0) {
        final details = '${process.stderr}'.trim();
        throw MfaAlignmentException(
          'MFA alignment failed (${process.exitCode}).'
          '${details.isEmpty ? '' : '\n$details'}',
        );
      }

      File? textGrid;
      await for (final entity in output.list(recursive: true)) {
        if (entity is File &&
            p.extension(entity.path).toLowerCase() == '.textgrid') {
          textGrid = entity;
          break;
        }
      }
      if (textGrid == null) {
        throw const MfaAlignmentException(
          'MFA completed but produced no TextGrid file.',
        );
      }
      final phones = parser.parse(await textGrid.readAsString());
      return AthmVisemeTrackBuilder(
        minimumPoseDurationMs: minimumPoseDurationMs,
        closedMouthLeadMs: closedMouthLeadMs,
      ).build(phones: phones, prefix: prefix);
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // A failed cleanup must not hide the alignment result or real error.
      }
    }
  }

  Future<void> _prepareMonoWav(String input, String output) async {
    final ffmpeg = resolveFfmpegExecutable();
    ProcessResult process;
    try {
      process = await Process.run(ffmpeg, [
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        input,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        output,
      ]);
    } on ProcessException catch (error) {
      throw MfaAlignmentException('Could not start FFmpeg.\n$error');
    }
    if (process.exitCode != 0) {
      throw MfaAlignmentException(
        'FFmpeg could not prepare audio for MFA.\n${process.stderr}',
      );
    }
  }
}

class _PoseSpan {
  _PoseSpan({required this.startMs, required this.endMs, required this.pose});

  double startMs;
  double endMs;
  final String pose;
}

class _PoseMapping {
  const _PoseMapping(this.pose, this.known);

  final String pose;
  final bool known;
}
