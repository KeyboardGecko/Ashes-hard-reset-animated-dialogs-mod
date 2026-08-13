// lib/features/audio_marks/application/label_image_service.dart
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Сервис картинок для лейблов с уведомлениями UI.
/// Хранит соответствия label -> image (путь / data:URL / URL),
/// умеет выбирать файл и делать относительные пути для проекта.
class LabelImageService extends ChangeNotifier {
  final String kNoLabelKey = '__NO_LABEL__';

  final Map<String, String> _labelImagePath = {};

  // --- ключ и доступ ---
  String _key(String? label) {
    if (label == null || label.trim().isEmpty) return kNoLabelKey;
    return label.trim();
  }

  String? imageForLabelNullable(String? label) => _labelImagePath[_key(label)];

  Map<String, String> get map => Map.unmodifiable(_labelImagePath);

  // --- мутации с нотификацией ---
  void setImageForLabel(String? label, String pathOrDataUrl) {
    _labelImagePath[_key(label)] = pathOrDataUrl;
    notifyListeners();
  }

  void clearImageForLabel(String? label) {
    _labelImagePath.remove(_key(label));
    notifyListeners();
  }

  String? get defaultImage => _labelImagePath[kNoLabelKey];

  set defaultImage(String? v) {
    if (v == null) {
      _labelImagePath.remove(kNoLabelKey);
    } else {
      _labelImagePath[kNoLabelKey] = v;
    }
    notifyListeners();
  }

  /// Полная замена мапы (например, при загрузке проекта).
  void setAll(Map<String, String> src) {
    _labelImagePath
      ..clear()
      ..addAll(src);
    notifyListeners();
  }

  // --- файловый выбор ---
  Future<String?> pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: kIsWeb, // на web вернём data:URL
    );
    if (res == null) return null;

    if (kIsWeb) {
      final bytes = res.files.single.bytes;
      if (bytes == null) return null;
      final ext = res.files.single.extension ?? 'png';
      return 'data:image/$ext;base64,${base64Encode(bytes)}';
    } else {
      return res.files.single.path;
    }
  }

  // --- сериализация путей для project.json ---
  String? storePath(String? absOrDataUrl, String projectDir) {
    if (absOrDataUrl == null || absOrDataUrl.isEmpty) return null;
    if (kIsWeb) return absOrDataUrl; // оставляем как есть
    if (absOrDataUrl.startsWith('data:image/')) {
      // data:URL
      return absOrDataUrl;
    }
    final normalized = p.normalize(absOrDataUrl);
    if (p.isWithin(projectDir, normalized)) {
      return p.relative(normalized, from: projectDir);
    }
    return normalized; // абсолютный путь
  }

  String resolvePath(String stored, String projectDir) {
    if (stored.startsWith('data:image/')) return stored;
    if (p.isAbsolute(stored)) return p.normalize(stored);
    return p.normalize(p.join(projectDir, stored));
  }
}
