// zscript_io_button.dart
import 'dart:convert';

import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

class ZScriptIOButtons extends StatelessWidget {
  const ZScriptIOButtons({
    super.key,
    required this.currentAudioPath,
    required this.getTotalDurationMs,
    required this.marksListenable,
    required this.imageForLabelNullable,
    required this.onImportMarks, // <- применить импортированные метки
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
              onPressed: canExport ? () => _export(context, marks) : null,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(exportLabel),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(importLabel),
            ),
          ],
        );
      },
    );
  }

  int msToTicks(int ms) => ((ms * 35) + 999) ~/ 1000;
  int ticksToMs(int ticks) => (ticks * 1000) ~/ 35;

  // --------------------- EXPORT ---------------------

  Future<void> _export(BuildContext context, List<ClipMark> marks) async {
    if (currentAudioPath == null || currentAudioPath!.isEmpty) {
      _toast(context, 'Сначала загрузите аудиофайл.');
      return;
    }

    final audioName = _basenameNoExt(currentAudioPath!);
    final funcSuffix = _sanitizeIdentifier(audioName);

    // 1) метки по времени
    final clips = List<ClipMark>.from(marks)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    // 2) собрать пути картинок: дефолт + клипы
    final defaultImg = imageForLabelNullable(null) ?? imageForLabelNullable('');
    final usedPathsSet = <String>{};
    if (defaultImg != null && defaultImg.isNotEmpty) {
      usedPathsSet.add(defaultImg);
    }
    for (final m in clips) {
      final img = imageForLabelNullable(m.label);
      if (img != null && img.isNotEmpty) usedPathsSet.add(img);
    }
    if (usedPathsSet.isEmpty) {
      _toast(context, 'Не найдены изображения (включая дефолтное).');
      return;
    }

    // 3) уникальные пути, отсортированные по алфавиту
    final uniqueSortedPaths = usedPathsSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // 4) уникальные имена без расширения (на случай коллизий добавляем _2, _3, …)
    final nameByPath = <String, String>{};
    final baseCounts = <String, int>{};
    for (final path in uniqueSortedPaths) {
      final base = _fileNameNoExtFromPath(path);
      final count = baseCounts.update(base, (v) => v + 1, ifAbsent: () => 1);
      final uniqueName = count == 1 ? base : '${base}_$count';
      nameByPath[path] = uniqueName;
    }

    // 5) построить f (имена) и d (мс)
    final f = <String>[];
    final d = <int>[];
    final totalMs = getTotalDurationMs();

    int safeGapMs(int from, int to) {
      final v = to - from;
      return v > 0 ? v : 200;
    }

    // дефолт кадр первым
    if (defaultImg != null && defaultImg.isNotEmpty) {
      final firstStart = clips.isNotEmpty
          ? clips.first.startMs.round()
          : totalMs;
      final dur = (firstStart > 0 || clips.isEmpty)
          ? safeGapMs(0, firstStart)
          : 200;
      f.add(nameByPath[defaultImg]!);
      d.add(dur);
    }

    // далее по клипам
    for (int i = 0; i < clips.length; i++) {
      final m = clips[i];
      final path = imageForLabelNullable(m.label);
      if (path == null || path.isEmpty) continue;
      final name = nameByPath[path]!;
      final start = m.startMs.round();
      final end = (i + 1 < clips.length)
          ? clips[i + 1].startMs.round()
          : (totalMs > 0 ? totalMs : start + 200);
      f.add(name);
      d.add(safeGapMs(start, end));
    }

    // склейка одинаковых подряд
    if (mergeConsecutiveSameFrames && f.isNotEmpty) {
      final nf = <String>[];
      final nd = <int>[];
      var curName = f.first;
      var curDur = d.first;
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
      _toast(context, 'Нечего экспортировать в .zc');
      return;
    }

    final zc = _buildZScript(
      funcSuffix: funcSuffix,
      audioName: audioName,
      nameByPath: nameByPath,
      f: f,
      d: d,
    );

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

  String _buildZScript({
    required String funcSuffix,
    required String audioName,
    required Map<String, String>
    nameByPath, // path -> unique name (без расширения)
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

  // --------------------- IMPORT ---------------------

  Future<void> _import(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZScript', extensions: ['zc']),
      ],
    );
    if (file == null) return;

    String src;
    try {
      src = await file.readAsString();
    } catch (e) {
      _toast(context, 'Не удалось прочитать файл: $e');
      return;
    }

    // сначала пробуем распарсить пары "f.Push(...); d.Push(...);"
    final pairs = _parseFDpairs(src);
    List<String> fnames;
    List<int> durs;

    if (pairs.isNotEmpty) {
      fnames = pairs.map((e) => e.$1).toList();
      durs = pairs.map((e) => e.$2).toList();
    } else {
      // fallback: отдельно f и d
      fnames = _parseF(src);
      durs = _parseD(src);
      if (fnames.isEmpty || durs.isEmpty) {
        _toast(context, 'В файле не найдены f.Push(...) / d.Push(...).');
        return;
      }
      final minLen = fnames.length < durs.length ? fnames.length : durs.length;
      fnames = fnames.sublist(0, minLen);
      durs = durs.sublist(0, minLen);
    }

    // реконструируем метки: startMs = накопленная сумма предыдущих d
    final marks = <ClipMark>[];
    int t = 0;
    for (int i = 0; i < fnames.length; i++) {
      final label = fnames[i];
      marks.add(
        ClipMark(
          id: genId(),
          startMs: (t * 1.27).toDouble(),
          label: label.isEmpty ? null : label,
          color: null,
        ),
      );
      final dur = durs[i];
      t += dur > 0 ? dur : 0; // не даём отрицательно «ехать назад»
    }

    // применяем в приложение
    onImportMarks(marks..sort((a, b) => a.startMs.compareTo(b.startMs)));

    _toast(context, 'Импортировано меток: ${marks.length}');
  }

  // Совмещённый парсер: f.Push("name"); d.Push(150);
  List<(String, int)> _parseFDpairs(String src) {
    final re = RegExp(
      r'f\.Push\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*;\s*d\.Push\(\s*(\d+)\s*\)\s*;',
      multiLine: true,
    );
    return [
      for (final m in re.allMatches(src))
        (_unescapeZS(m.group(1)!), int.parse(m.group(2)!)),
    ];
  }

  // Отдельно f.Push("..."); (если пары не найдены)
  List<String> _parseF(String src) {
    final re = RegExp(
      r'f\.Push\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*;',
      multiLine: true,
    );
    return [for (final m in re.allMatches(src)) _unescapeZS(m.group(1)!)];
  }

  // Отдельно d.Push(123);
  List<int> _parseD(String src) {
    final re = RegExp(r'd\.Push\(\s*(\d+)\s*\)\s*;', multiLine: true);
    return [for (final m in re.allMatches(src)) int.parse(m.group(1)!)];
  }

  String _unescapeZS(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');

  // --------------------- helpers ---------------------

  String _basenameNoExt(String fullPath) {
    final norm = fullPath.replaceAll('\\', '/');
    final base = norm.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  String _fileNameNoExtFromPath(String path) {
    final norm = path.replaceAll('\\', '/');
    final base = norm.split('/').last;
    final dot = base.lastIndexOf('.');
    final name = dot > 0 ? base.substring(0, dot) : base;
    return name.isEmpty ? 'frame' : name;
  }

  String _sanitizeIdentifier(String s) {
    final base = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    if (base.isEmpty) return 'Anim';
    return RegExp(r'^[0-9]').hasMatch(base) ? '_$base' : base;
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
