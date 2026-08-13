// lib/features/audio_marks/domain/services/label_image_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class LabelImageService extends ChangeNotifier {
  final String kNoLabelKey = '__NO_LABEL__';
  final Map<String, String> _labelImagePath = {};

  String _key(String? label) =>
      (label == null || label.trim().isEmpty) ? kNoLabelKey : label.trim();

  String? imageForLabelNullable(String? label) => _labelImagePath[_key(label)];

  Map<String, String> get map => Map<String, String>.from(_labelImagePath);

  String? get defaultImage => _labelImagePath[kNoLabelKey];
  set defaultImage(String? v) {
    final k = kNoLabelKey;
    final old = _labelImagePath[k];
    if (v == null) {
      if (old != null) {
        _labelImagePath.remove(k);
        notifyListeners();
      }
    } else {
      if (old != v) {
        _labelImagePath[k] = v;
        notifyListeners();
      }
    }
  }

  void setImageForLabel(String? label, String pathOrDataUrl) {
    final k = _key(label);
    if (_labelImagePath[k] != pathOrDataUrl) {
      _labelImagePath[k] = pathOrDataUrl;
      notifyListeners();
    }
  }

  void clearImageForLabel(String? label) {
    final k = _key(label);
    if (_labelImagePath.containsKey(k)) {
      _labelImagePath.remove(k);
      notifyListeners();
    }
  }

  void setAll(Map<String, String> src) {
    _labelImagePath
      ..clear()
      ..addAll(src);
    notifyListeners();
  }

  Future<String?> pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: kIsWeb,
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

  String? storePath(String? absOrDataUrl, String projectDir) {
    if (absOrDataUrl == null || absOrDataUrl.isEmpty) return null;
    if (kIsWeb) return absOrDataUrl;
    if (absOrDataUrl.startsWith('data:image/')) return absOrDataUrl;
    final normalized = p.normalize(absOrDataUrl);
    if (p.isWithin(projectDir, normalized)) {
      return p.relative(normalized, from: projectDir);
    }
    return normalized;
  }

  String resolvePath(String stored, String projectDir) {
    if (stored.startsWith('data:image/')) return stored;
    if (p.isAbsolute(stored)) return p.normalize(stored);
    return p.normalize(p.join(projectDir, stored));
  }
}
