// lib/widgets/batch_json_projects_to_zscript_button.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Кнопка: выбрать несколько JSON-проектов и конвертировать каждый в .zc (ZScript)
class BatchJsonProjectsToZScriptButton extends StatefulWidget {
  const BatchJsonProjectsToZScriptButton({
    super.key,
    this.label = 'Массово: JSON → .zc',
    this.mergeConsecutiveSameFrames = true,
    this.minGapMs = 200,
    this.tailMsIfUnknownDuration = 200,
  });

  final String label;
  final bool mergeConsecutiveSameFrames;
  final int minGapMs;
  final int tailMsIfUnknownDuration;

  @override
  State<BatchJsonProjectsToZScriptButton> createState() =>
      _BatchJsonProjectsToZScriptButtonState();
}

class _BatchJsonProjectsToZScriptButtonState
    extends State<BatchJsonProjectsToZScriptButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_fix_high_outlined),
      label: Text(widget.label),
    );
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pick = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (pick == null || pick.files.isEmpty) return;

      int ok = 0, fail = 0;

      for (final f in pick.files) {
        final path = f.path;
        if (path == null) {
          fail++;
          continue;
        }
        try {
          final text = await File(path).readAsString();
          final map = jsonDecode(text) as Map<String, dynamic>;

          final baseName = p.basenameWithoutExtension(path);
          final res = _zcFromProjectMap(
            map,
            preferredBaseName: baseName,
            mergeConsecutive: widget.mergeConsecutiveSameFrames,
            minGapMs: widget.minGapMs,
            tailMsIfUnknown: widget.tailMsIfUnknownDuration,
          );

          final dir = p.dirname(path);
          final outBase = res.suggestedBaseName.isEmpty
              ? baseName
              : res.suggestedBaseName;
          final outPath = await _uniquePath(p.join(dir, '$outBase.zc'));
          await File(outPath).writeAsString(res.text);

          ok++;
        } catch (_) {
          fail++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Готово: $ok файлов, ошибок: $fail')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    int i = 1;
    while (true) {
      final candidate = p.join(dir, '$name ($i)$ext');
      if (!await File(candidate).exists()) return candidate;
      i++;
    }
  }
}

/// Результат генерации .zc
class _ZcResult {
  final String text;
  final String suggestedBaseName;
  const _ZcResult(this.text, this.suggestedBaseName);
}

/// Преобразование JSON-проекта → .zc (повторяет логику твоего _export)
_ZcResult _zcFromProjectMap(
  Map<String, dynamic> map, {
  required String preferredBaseName,
  required bool mergeConsecutive,
  required int minGapMs,
  required int tailMsIfUnknown,
}) {
  final audioStored = (map['audio'] as String?)?.trim();
  final totalMs =
      (map['durationMs'] as num?)?.round() ?? -1; // может отсутствовать
  final clipsRaw = (map['clips'] as List?) ?? const [];
  final defaultImg = (map['defaultImage'] as String?)?.trim();

  // собираем клипы (берём только startMs и image)
  final clips = <({double startMs, String? image})>[];
  for (final e in clipsRaw) {
    if (e is Map<String, dynamic>) {
      final start = (e['startMs'] as num?)?.toDouble();
      if (start == null) continue;
      final img = (e['image'] as String?)?.trim();
      clips.add((
        startMs: start,
        image: (img == null || img.isEmpty) ? null : img,
      ));
    }
  }
  clips.sort((a, b) => a.startMs.compareTo(b.startMs));

  // набор путей изображений: default + из клипов
  final usedPaths = <String>{};
  if (defaultImg != null && defaultImg.isNotEmpty) usedPaths.add(defaultImg);
  for (final c in clips) {
    if (c.image != null && c.image!.isNotEmpty) usedPaths.add(c.image!);
  }
  if (usedPaths.isEmpty) {
    throw Exception(
      'No images in the project (defaultImage and clips[].image are empty).',
    );
  }

  // уникальные «имена кадров» из путей
  final paths = usedPaths.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final nameByPath = <String, String>{};
  final counts = <String, int>{};
  for (final path in paths) {
    final base = _baseNameForPath(path);
    final n = counts.update(base, (v) => v + 1, ifAbsent: () => 1);
    nameByPath[path] = n == 1 ? base : '${base}_$n';
  }

  // f/d
  final f = <String>[];
  final d = <int>[];

  int safeGapMs(int from, int to) {
    final v = to - from;
    return v > 0 ? v : minGapMs;
    // (как в твоём экспорте — не даём нулей/отрицательных)
  }

  // дефолтный кадр первым
  if (defaultImg != null && defaultImg.isNotEmpty) {
    final firstStart = clips.isNotEmpty ? clips.first.startMs.round() : totalMs;
    final dur = (firstStart > 0 || clips.isEmpty)
        ? safeGapMs(0, firstStart)
        : minGapMs;
    f.add(nameByPath[defaultImg]!);
    d.add(dur);
  }

  // далее клипы
  for (int i = 0; i < clips.length; i++) {
    final c = clips[i];
    if (c.image == null || c.image!.isEmpty) continue;
    final name = nameByPath[c.image]!;
    final start = c.startMs.round();
    final end = (i + 1 < clips.length)
        ? clips[i + 1].startMs.round()
        : (totalMs > 0 ? totalMs : start + tailMsIfUnknown);
    f.add(name);
    d.add(safeGapMs(start, end));
  }

  // склейка одинаковых подряд
  if (mergeConsecutive && f.isNotEmpty) {
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
    throw Exception('Нечего экспортировать: f/d пусты или разной длины.');
  }

  // имя анимации/функции
  final audioBase = (audioStored != null && audioStored.isNotEmpty)
      ? _fileNameNoExtFromPath(audioStored)
      : preferredBaseName;
  final funcSuffix = _sanitizeIdentifier(audioBase);
  final animName = audioBase.isEmpty ? 'animation' : audioBase;

  // сам текст ZScript (как в твоём _buildZScript)
  final entries = nameByPath.entries.toList()
    ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

  final sb = StringBuffer()
    ..writeln('extend class CustomAnimData')
    ..writeln('{')
    ..writeln('    ui static void RegisterAnims_$funcSuffix(PanelPlayer p)')
    ..writeln('    {')
    ..writeln('        Array<String> f;')
    ..writeln('        Array<int> d;')
    ..writeln('        // Frame names → source paths:');

  for (final e in entries) {
    final safePath = e.key.replaceAll('\\', '\\\\');
    final safeName = e.value.replaceAll('"', r'\"');
    sb.writeln('        // "$safeName" <= $safePath');
  }

  for (int i = 0; i < f.length; i++) {
    final name = f[i].replaceAll('"', r'\"');
    sb.writeln('        f.Push("$name"); d.Push(${d[i]});');
  }

  final safeAnim = animName.replaceAll('"', r'\"');
  sb.writeln(
    '        p.DefineAnimationByNames("$safeAnim", f, d, false, true);',
  );
  sb.writeln('    }');
  sb.writeln('}');

  return _ZcResult(sb.toString(), animName);
}

// --- маленькие хелперы (имена/идентификаторы) ---

String _fileNameNoExtFromPath(String path) {
  final norm = path.replaceAll('\\', '/');
  final base = norm.split('/').last;
  final dot = base.lastIndexOf('.');
  final name = dot > 0 ? base.substring(0, dot) : base;
  return name.isEmpty ? 'frame' : name;
}

String _baseNameForPath(String path) {
  if (path.startsWith('data:image/')) return 'img';
  return _fileNameNoExtFromPath(path);
}

String _sanitizeIdentifier(String s) {
  final base = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (base.isEmpty) return 'Anim';
  return RegExp(r'^[0-9]').hasMatch(base) ? '_$base' : base;
}
