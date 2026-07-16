// imports:
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Добавь этот пункт в itemBuilder твоего PopupMenuButton:
///
///   ...,
///   const PopupMenuItem(
///     value: 'export_language_anim',
///     child: Text('Export LANGUAGE_ANIM.txt…'),
///   ),
///   ...
///
/// А в onSelected:
///
///   else if (v == 'export_language_anim') {
///     await exportLanguageAnimFromJsonBatch(context);
///     _refocus(); // твой helper, чтобы вернуть фокус экрану
///   }
///
Future<void> exportLanguageAnimFromJsonBatch(BuildContext context) async {
  if (kIsWeb) {
    _showSnack(context, 'Экспорт на Web не реализован (нужен доступ к ФС).');
    return;
  }

  final picked = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (picked == null || picked.files.isEmpty) return;

  final files = picked.files.map((f) => f.path).whereType<String>().toList();
  if (files.isEmpty) return;

  final entries = <_AnimEntry>[];

  for (final path in files) {
    try {
      final map =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

      final name = p.basenameWithoutExtension(path); // напр. "JM001"
      final group = _inferGroup(name); // "JM"
      final anim = name.toUpperCase(); // "JM001"
      final char = group; // персонаж = префикс файла

      final clips =
          ((map['clips'] as List?) ?? const <dynamic>[])
              .cast<Map<String, dynamic>>()
              .map(
                (e) => _Clip(
                  image: (e['image'] as String?) ?? '',
                  startMs: (e['startMs'] as num).toDouble(),
                  label: (e['label'] as String?) ?? '',
                ),
              )
              .toList()
            ..sort((a, b) => a.startMs.compareTo(b.startMs));
      final defImage = (map['defaultImage'] as String?)?.trim();
      if (defImage != null && defImage.isNotEmpty) {
        final defBase = p.basenameWithoutExtension(defImage).toUpperCase();
        final needInsert =
            clips.isEmpty ||
            clips.first.startMs > 0 ||
            p.basenameWithoutExtension(clips.first.image).toUpperCase() !=
                defBase;

        if (needInsert) {
          // кадр без метки на t=0
          clips.insert(0, _Clip(image: defImage, startMs: 0.0, label: ''));
        }
      } else {
        // (опционально) если defaultImage отсутствует — попробуем взять
        // картинку из первого кадра с пустым label и перенести на t=0
        const eps = 0.001; // ~1 мс
        final hasZeroFrame = clips.any((c) => c.startMs.abs() <= eps);

        if (!hasZeroFrame) {
          final defImage = (map['defaultImage'] as String?)?.trim();
          if (defImage != null && defImage.isNotEmpty) {
            clips.insert(0, _Clip(image: defImage, startMs: 0.0, label: ''));
          } else {
            final i = clips.indexWhere(
              (c) => c.label.trim().isEmpty && c.image.isNotEmpty,
            );
            if (i >= 0) {
              clips.insert(
                0,
                _Clip(image: clips[i].image, startMs: 0.0, label: ''),
              );
            }
          }
        }
      }

      // FRAMES: только имя файла без расширения (без префикса и без слэша)
      final frames = <String>[];
      for (final c in clips) {
        final base = p.basenameWithoutExtension(c.image).toUpperCase();
        frames.add(base);
      }

      // DURS: разницы стартов; последний = 60 мс
      // final durs = <int>[];
      // for (var i = 0; i < clips.length; i++) {
      //   if (i + 1 < clips.length) {
      //     durs.add(
      //       (clips[i + 1].startMs - clips[i].startMs).round().clamp(1, 100000),
      //     );
      //   } else {
      //     durs.add(60);
      //   }
      // }
      final starts = clips.map((c) => c.startMs.round()).toList()..sort();
      final durs = <int>[];
      for (var i = 0; i + 1 < starts.length; i++) {
        durs.add((starts[i + 1] - starts[i]).clamp(1, 100000));
      }
      durs.add(60);
      entries.add(
        _AnimEntry(
          fileName: name,
          group: group,
          char: char,
          anim: anim,
          frames: frames,
          durs: durs,
        ),
      );
    } catch (e) {
      _showSnack(context, 'Пропущен ${p.basename(path)}: $e');
    }
  }

  if (entries.isEmpty) {
    _showSnack(context, 'Нет валидных JSON.');
    return;
  }

  // Группы для MAP
  final groupsSorted = entries.map((e) => e.group).toSet().toList()..sort();

  // По персонажам (теперь это те же коды групп)
  final char2anims = <String, List<_AnimEntry>>{};
  for (final e in entries) {
    (char2anims[e.char] ??= <_AnimEntry>[]).add(e);
  }
  for (final list in char2anims.values) {
    list.sort((a, b) => a.anim.compareTo(b.anim));
  }
  final charsSorted = char2anims.keys.toList()..sort();

  final buf = StringBuffer();
  buf.writeln('[default]\n');

  // MAP
  buf.writeln('ANIMS_MAP_LIST = "${groupsSorted.join(',')}";\n');
  for (final g in groupsSorted) {
    buf.writeln('ANIMS_MAP_$g = "$g";');
  }
  buf.writeln('');

  // Персонажи/анимации
  for (final char in charsSorted) {
    final list = char2anims[char] ?? const <_AnimEntry>[];
    buf.writeln('// --- $char ---');
    buf.writeln('ANIMS_${char}_PRELOAD = "IDLE";'); // без префикса
    final animNames = ['IDLE', ...list.map((e) => e.anim)];
    buf.writeln('ANIMS_${char}_LIST    = "${animNames.join(',')}";\n');

    buf.writeln('ANIMS_${char}_IDLE_FRAMES = "IDLE";'); // без префикса
    buf.writeln('ANIMS_${char}_IDLE_DURS   = "60";');
    buf.writeln('ANIMS_${char}_IDLE_LOOP   = "true";');
    // buf.writeln('ANIMS_${char}_IDLE_STOP   = "false";\n');

    for (final e in list) {
      buf.writeln('ANIMS_${char}_${e.anim}_FRAMES = "${e.frames.join(',')}";');
      buf.writeln('ANIMS_${char}_${e.anim}_DURS   = "${e.durs.join(',')}";');
      buf.writeln('ANIMS_${char}_${e.anim}_LOOP   = "false";');
      // buf.writeln('ANIMS_${char}_${e.anim}_STOP   = "true";\n');
    }
  }

  final text = buf.toString();

  final loc = await getSaveLocation(
    suggestedName: 'LANGUAGE_ANIM.txt',
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Text', extensions: ['txt']),
    ],
  );
  if (loc == null) return;

  final path = p.extension(loc.path).toLowerCase() == '.txt'
      ? loc.path
      : '${loc.path}.txt';

  await File(path).writeAsString(text);
  _showSnack(context, 'Сохранено: ${p.basename(path)}');
}

// ---------- helpers & модели ----------

class _Clip {
  final String image;
  final double startMs;
  final String label;
  _Clip({required this.image, required this.startMs, required this.label});
}

class _AnimEntry {
  final String fileName; // "JM001"
  final String group; // "JM"
  final String char; // "JIM"
  final String anim; // "JM001"
  final List<String> frames;
  final List<int> durs;
  _AnimEntry({
    required this.fileName,
    required this.group,
    required this.char,
    required this.anim,
    required this.frames,
    required this.durs,
  });
}

// из имени файла: "JM001" -> "JM", "POR02" -> "POR", "AND14" -> "AND"
String _inferGroup(String nameNoExt) {
  final m = RegExp(r'^[A-Za-z]+').firstMatch(nameNoExt);
  return (m?.group(0) ?? 'UNK').toUpperCase();
}

void _showSnack(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
}
