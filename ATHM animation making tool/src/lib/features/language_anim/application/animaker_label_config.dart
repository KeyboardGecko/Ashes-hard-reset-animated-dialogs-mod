import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AnimakerLabelConfig {
  AnimakerLabelConfig({String? filePath})
    : filePath =
          filePath ?? p.join(Directory.current.path, 'animaker_labels.json');

  static const int formatVersion = 1;

  final String filePath;

  Future<Map<String, String>> loadForCharacter(String characterId) async {
    final document = await _read();
    final characters = document['characters'];
    if (characters is! Map) return const {};
    final rawAliases = characters[characterId.trim().toUpperCase()];
    if (rawAliases is! Map) return const {};

    final aliases = <String, String>{};
    for (final entry in rawAliases.entries) {
      final frameName = entry.key.toString().trim().toUpperCase();
      final label = entry.value?.toString().trim() ?? '';
      if (frameName.isNotEmpty && label.isNotEmpty) {
        aliases[frameName] = label;
      }
    }
    return aliases;
  }

  Future<void> updateCharacter(
    String characterId,
    Map<String, String> frameLabels,
  ) async {
    final document = await _read();
    final characters = _stringMap(document['characters']);
    final id = characterId.trim().toUpperCase();
    final aliases = _stringMap(characters[id]);

    for (final entry in frameLabels.entries) {
      final frameName = entry.key.trim().toUpperCase();
      final label = entry.value.trim();
      if (frameName.isEmpty) continue;
      if (label.isEmpty || label.toUpperCase() == frameName) {
        aliases.remove(frameName);
      } else {
        aliases[frameName] = label;
      }
    }

    if (aliases.isEmpty) {
      characters.remove(id);
    } else {
      characters[id] = aliases;
    }
    await _write({'version': formatVersion, 'characters': characters});
  }

  Future<void> renameCharacter(String oldId, String newId) async {
    final document = await _read();
    final characters = _stringMap(document['characters']);
    final oldKey = oldId.trim().toUpperCase();
    final newKey = newId.trim().toUpperCase();
    if (oldKey == newKey || !characters.containsKey(oldKey)) return;
    final aliases = characters.remove(oldKey);
    if (aliases != null) characters[newKey] = aliases;
    await _write({'version': formatVersion, 'characters': characters});
  }

  Future<Map<String, dynamic>> _read() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return <String, dynamic>{
        'version': formatVersion,
        'characters': <String, dynamic>{},
      };
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, dynamic>{};
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _stringMap(Object? source) {
    if (source is! Map) return <String, dynamic>{};
    return source.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _write(Map<String, dynamic> document) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    );
  }
}
