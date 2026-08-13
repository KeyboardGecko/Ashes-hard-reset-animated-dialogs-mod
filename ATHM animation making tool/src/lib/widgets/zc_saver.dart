import 'dart:io';
import 'package:path/path.dart' as p;

abstract class ZcSaver {
  static Future<String> readText(String path) async {
    return File(path).readAsString();
  }

  static Future<void> save({
    required String fileName,
    required String content,
    String? originalPath,
  }) async {
    final dir = (originalPath != null)
        ? p.dirname(originalPath)
        : Directory.current.path;
    final outBase = p.join(dir, fileName);
    final outPath = await _uniquePath(outBase);
    await File(outPath).writeAsString(content);
  }

  static Future<String> _uniquePath(String basePath) async {
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
