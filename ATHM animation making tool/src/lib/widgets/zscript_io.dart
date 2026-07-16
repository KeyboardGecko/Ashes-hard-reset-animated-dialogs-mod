// lib/widgets/zscript_io.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/audio_marks/domain/entities/clip_mark.dart';

class ZScriptIO {
  // ============= ПУБЛИЧНЫЕ API =============

  /// Построить текст .zc из текущего состояния (без сохранения).
  static String buildZcText({
    required String audioPath,
    required int totalDurationMs,
    required List<ClipMark> marks,
    required String? Function(String? label) imageForLabelNullable,
    bool mergeConsecutiveSameFrames = true,
  }) {
    if (audioPath.isEmpty) {
      throw StateError('Audio path is empty');
    }
    if (marks.isEmpty) {
      throw StateError('No marks to export');
    }

    final audioName = _basenameNoExt(audioPath);
    final funcSuffix = _sanitizeIdentifier(audioName);

    // 1) метки отсортированы
    final clips = List<ClipMark>.from(marks)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    // 2) пути картинок
    final defaultImg = imageForLabelNullable(null) ?? imageForLabelNullable('');
    final used = <String>{};
    if (defaultImg != null && defaultImg.isNotEmpty) used.add(defaultImg);
    for (final m in clips) {
      final img = imageForLabelNullable(m.label);
      if (img != null && img.isNotEmpty) used.add(img);
    }
    if (used.isEmpty) {
      throw StateError('No images found (including default).');
    }

    // 3) path -> уникальное имя
    final sortedPaths = used.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final nameByPath = <String, String>{};
    final baseCounts = <String, int>{};
    for (final path in sortedPaths) {
      final base = _fileNameNoExtFromPath(path);
      final n = baseCounts.update(base, (v) => v + 1, ifAbsent: () => 1);
      nameByPath[path] = n == 1 ? base : '${base}_$n';
    }

    // 4) f / d
    final f = <String>[];
    final d = <int>[];
    int safeGapMs(int from, int to) {
      final v = to - from;
      return v > 0 ? v : 200;
    }

    if (defaultImg != null && defaultImg.isNotEmpty) {
      final firstStart = clips.isNotEmpty
          ? clips.first.startMs.round()
          : totalDurationMs;
      final dur = (firstStart > 0 || clips.isEmpty)
          ? safeGapMs(0, firstStart)
          : 200;
      f.add(nameByPath[defaultImg]!);
      d.add(dur);
    }

    for (int i = 0; i < clips.length; i++) {
      final m = clips[i];
      final path = imageForLabelNullable(m.label);
      if (path == null || path.isEmpty) continue;
      final name = nameByPath[path]!;
      final start = m.startMs.round();
      final end = (i + 1 < clips.length)
          ? clips[i + 1].startMs.round()
          : (totalDurationMs > 0 ? totalDurationMs : start + 200);
      f.add(name);
      d.add(safeGapMs(start, end));
    }

    if (mergeConsecutiveSameFrames && f.isNotEmpty) {
      final nf = <String>[], nd = <int>[];
      var curName = f.first, curDur = d.first;
      for (int i = 1; i < f.length; i++) {
        if (f[i] == curName) {
          curDur += d[i];
        } else {
          nf.add(curName);
          nd.add(curDur);
          curName = f[i];
          curDur = d[i];
        }
      }
      nf.add(curName);
      nd.add(curDur);
      f
        ..clear()
        ..addAll(nf);
      d
        ..clear()
        ..addAll(nd);
    }

    if (f.isEmpty || d.isEmpty || f.length != d.length) {
      throw StateError('Nothing to export: f/d empty or different length.');
    }

    return _buildZScript(
      funcSuffix: funcSuffix,
      audioName: audioName,
      nameByPath: nameByPath,
      f: f,
      d: d,
    );
  }

  /// Экспорт с диалогом сохранения (UI-обвязка).
  static Future<void> exportInteractive(
    BuildContext context, {
    required String? currentAudioPath,
    required int Function() getTotalDurationMs,
    required List<ClipMark> marks,
    required String? Function(String? label) imageForLabelNullable,
    bool mergeConsecutiveSameFrames = true,
  }) async {
    if (currentAudioPath == null || currentAudioPath.isEmpty) {
      _toast(context, 'Load audio file first.');
      return;
    }
    if (marks.isEmpty) {
      _toast(context, 'Marks are empty.');
      return;
    }

    String zc;
    try {
      zc = buildZcText(
        audioPath: currentAudioPath,
        totalDurationMs: getTotalDurationMs(),
        marks: marks,
        imageForLabelNullable: imageForLabelNullable,
        mergeConsecutiveSameFrames: mergeConsecutiveSameFrames,
      );
    } catch (e) {
      _toast(context, 'Ошибка экспорта: $e');
      return;
    }

    final audioName = _basenameNoExt(currentAudioPath);
    final suggestedName = '${audioName.isEmpty ? "animation" : audioName}.zc';

    if (kIsWeb) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(suggestedName),
          content: SingleChildScrollView(child: Text(zc)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZScript', extensions: ['zc']),
      ],
    );
    if (loc == null) return;

    final bytes = Uint8List.fromList(utf8.encode(zc));
    final file = XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: 'text/plain',
    );
    try {
      await file.saveTo(loc.path);
      _toast(context, 'Сохранено: ${loc.path}');
    } catch (e) {
      _toast(context, 'Ошибка сохранения .zc: $e');
    }
  }

  /// Импорт с диалогом выбора файла (UI-обвязка).
  /// Возвращает список меток или null, если пользователь отменил.
  static Future<List<ClipMark>?> importInteractive(
    BuildContext context, {
    required String Function() idFactory, // напр. () => genId()
  }) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZScript', extensions: ['zc']),
      ],
    );
    if (file == null) return null;

    String src;
    try {
      src = await file.readAsString();
    } catch (e) {
      _toast(context, 'Не удалось прочитать файл: $e');
      return null;
    }

    try {
      final marks = importFromZcText(src, idFactory: idFactory);
      return marks;
    } catch (e) {
      _toast(context, 'Ошибка импорта: $e');
      return null;
    }
  }

  /// Импорт из текста .zc (без UI). Удобно для вставки через буфер/сетку.
  static List<ClipMark> importFromZcText(
    String src, {
    required String Function() idFactory,
  }) {
    final pairs = _parseFDpairs(src);
    late List<String> fnames;
    late List<int> durs;

    if (pairs.isNotEmpty) {
      fnames = [for (final p in pairs) p.$1];
      durs = [for (final p in pairs) p.$2];
    } else {
      fnames = _parseF(src);
      durs = _parseD(src);
      if (fnames.isEmpty || durs.isEmpty) {
        throw StateError('В файле не найдены f.Push(...) / d.Push(...).');
      }
      final minLen = fnames.length < durs.length ? fnames.length : durs.length;
      fnames = fnames.sublist(0, minLen);
      durs = durs.sublist(0, minLen);
    }

    final marks = <ClipMark>[];
    int t = 0;
    for (int i = 0; i < fnames.length; i++) {
      final label = fnames[i];
      marks.add(
        ClipMark(
          id: idFactory(),
          startMs: (t * 1.27).toDouble(),
          label: label.isEmpty ? null : label,
          color: null,
        ),
      );
      final dur = durs[i];
      t += dur > 0 ? dur : 0;
    }
    marks.sort((a, b) => a.startMs.compareTo(b.startMs));
    return marks;
  }

  // ============= ВНУТРЕННИЕ ХЕЛПЕРЫ =============

  static String _buildZScript({
    required String funcSuffix,
    required String audioName,
    required Map<String, String> nameByPath,
    required List<String> f,
    required List<int> d,
  }) {
    final entries = nameByPath.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    final sb = StringBuffer()
      ..writeln('extend class CustomAnimData')
      ..writeln('{')
      ..writeln('    ui static void RegisterAnims_$funcSuffix(PanelPlayer p)')
      ..writeln('    {')
      ..writeln('        Array<String> f;')
      ..writeln('        Array<int> d;')
      ..writeln('        // Frame names → paths (sorted by name):');

    for (final e in entries) {
      final safePath = e.key.replaceAll('\\', '\\\\');
      final safeName = e.value.replaceAll('"', r'\"');
      sb.writeln('        // "$safeName" => $safePath');
    }

    for (int i = 0; i < f.length; i++) {
      final name = f[i].replaceAll('"', r'\"');
      sb.writeln('        f.Push("$name"); d.Push(${d[i]});');
    }

    final safeAnim = audioName.replaceAll('"', r'\"');
    sb.writeln(
      '        p.DefineAnimationByNames("$safeAnim", f, d, false, true);',
    );
    sb.writeln('    }');
    sb.writeln('}');
    return sb.toString();
  }

  static List<(String, int)> _parseFDpairs(String src) {
    final re = RegExp(
      r'f\.Push\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*;\s*d\.Push\(\s*(\d+)\s*\)\s*;',
      multiLine: true,
    );
    return [
      for (final m in re.allMatches(src))
        (_unescapeZS(m.group(1)!), int.parse(m.group(2)!)),
    ];
  }

  static List<String> _parseF(String src) {
    final re = RegExp(
      r'f\.Push\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*;',
      multiLine: true,
    );
    return [for (final m in re.allMatches(src)) _unescapeZS(m.group(1)!)];
  }

  static List<int> _parseD(String src) {
    final re = RegExp(r'd\.Push\(\s*(\d+)\s*\)\s*;', multiLine: true);
    return [for (final m in re.allMatches(src)) int.parse(m.group(1)!)];
  }

  static String _unescapeZS(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');

  static String _basenameNoExt(String fullPath) {
    final norm = fullPath.replaceAll('\\', '/');
    final base = norm.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static String _fileNameNoExtFromPath(String path) {
    final norm = path.replaceAll('\\', '/');
    final base = norm.split('/').last;
    final dot = base.lastIndexOf('.');
    final name = dot > 0 ? base.substring(0, dot) : base;
    return name.isEmpty ? 'frame' : name;
  }

  static String _sanitizeIdentifier(String s) {
    final base = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    if (base.isEmpty) return 'Anim';
    return RegExp(r'^[0-9]').hasMatch(base) ? '_$base' : base;
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // (на всякий) конвертеры тиков/мс
  static int msToTicks(int ms) => ((ms * 35) + 999) ~/ 1000;
  static int ticksToMs(int ticks) => (ticks * 1000) ~/ 35;
}

/// Тонкая кнопочная обёртка — оставил для совместимости.
class ZScriptIOButtons extends StatelessWidget {
  const ZScriptIOButtons({
    super.key,
    required this.currentAudioPath,
    required this.getTotalDurationMs,
    required this.marksListenable,
    required this.imageForLabelNullable,
    required this.onImportMarks,
    this.mergeConsecutiveSameFrames = true,
    this.exportLabel = 'Экспорт .zc',
    this.importLabel = 'Импорт .zc',
  });

  final String? currentAudioPath;
  final int Function() getTotalDurationMs;
  final ValueListenable<List<ClipMark>> marksListenable;
  final String? Function(String? label) imageForLabelNullable;
  final void Function(List<ClipMark> marks) onImportMarks;

  final bool mergeConsecutiveSameFrames;
  final String exportLabel;
  final String importLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ClipMark>>(
      valueListenable: marksListenable,
      builder: (context, marks, _) {
        final canExport =
            (currentAudioPath != null && currentAudioPath!.isNotEmpty) &&
            marks.isNotEmpty;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canExport
                  ? () => ZScriptIO.exportInteractive(
                      context,
                      currentAudioPath: currentAudioPath,
                      getTotalDurationMs: getTotalDurationMs,
                      marks: marks,
                      imageForLabelNullable: imageForLabelNullable,
                      mergeConsecutiveSameFrames: mergeConsecutiveSameFrames,
                    )
                  : null,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(exportLabel),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final imported = await ZScriptIO.importInteractive(
                  context,
                  idFactory: () => genId(),
                );
                if (imported != null) onImportMarks(imported);
              },
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(importLabel),
            ),
          ],
        );
      },
    );
  }
}
