// lib/features/audio_marks/application/label_images_io.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../domain/services/label_image_service.dart';

/// Экспортирует соответствия лейбл→картинка в .labels.json.
/// Пути делаютcя относительными к файлу настроек (как в проекте).
Future<void> exportLabelImagesSettings(
  BuildContext context, {
  required LabelImageService imgSvc,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Web export is not supported.')),
    );
    return;
  }

  final loc = await getSaveLocation(
    suggestedName: 'label_images.labels.json',
    acceptedTypeGroups: [
      const XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (loc == null) return;

  final dir = p.dirname(loc.path);
  final payload = <String, dynamic>{'version': 1, 'images': <String, String>{}};

  imgSvc.map.forEach((key, path) {
    final stored = imgSvc.storePath(path, dir);
    if (stored != null) {
      (payload['images'] as Map<String, String>)[key] = stored;
    }
  });

  await File(
    loc.path,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Saved: ${p.basename(loc.path)}')));
}

/// Импортирует .labels.json и применяет ко всем лейблам (через imgSvc.setAll).
Future<void> importLabelImagesSettings(
  BuildContext context, {
  required LabelImageService imgSvc,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Web import is not supported.')),
    );
    return;
  }

  final picked = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (picked == null) return;

  final path = picked.path;
  try {
    final text = await File(path).readAsString();
    final map = jsonDecode(text) as Map<String, dynamic>;
    final imgs =
        (map['images'] as Map?)?.cast<String, String>() ??
        const <String, String>{};
    final dir = p.dirname(path);

    // резолвим в абсолютные/валидные пути (или data: URL)
    final resolved = <String, String>{};
    imgs.forEach((k, v) {
      resolved[k] = imgSvc.resolvePath(v, dir);
    });

    imgSvc.setAll(resolved); // 🔔 всё UI, слушающее imgSvc, обновится
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Loaded: ${p.basename(path)}')));
  } catch (e) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}
