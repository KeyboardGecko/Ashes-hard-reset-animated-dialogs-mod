import 'dart:convert';
import 'dart:io';

import 'package:animaker/features/language_anim/application/animaker_label_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'stores aliases per character and merges later animation saves',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'animaker_labels_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final filePath = p.join(root.path, 'animaker_labels.json');
      final config = AnimakerLabelConfig(filePath: filePath);

      await config.updateCharacter('jm', {'JMF': 'f', 'JMS': 's'});
      await config.updateCharacter('and', {'ANDF': 'f'});
      await config.updateCharacter('JM', {'JMM': 'm'});

      expect(await config.loadForCharacter('JM'), {
        'JMF': 'f',
        'JMS': 's',
        'JMM': 'm',
      });
      expect(await config.loadForCharacter('AND'), {'ANDF': 'f'});

      final decoded =
          jsonDecode(await File(filePath).readAsString())
              as Map<String, dynamic>;
      expect(decoded['version'], 1);
    },
  );

  test('full frame name removes a stale short alias', () async {
    final root = await Directory.systemTemp.createTemp('animaker_labels_test_');
    addTearDown(() => root.delete(recursive: true));
    final config = AnimakerLabelConfig(
      filePath: p.join(root.path, 'animaker_labels.json'),
    );

    await config.updateCharacter('JM', {'JMF': 'f'});
    await config.updateCharacter('JM', {'JMF': 'JMF'});

    expect(await config.loadForCharacter('JM'), isEmpty);
  });

  test('missing or malformed config falls back to no aliases', () async {
    final root = await Directory.systemTemp.createTemp('animaker_labels_test_');
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'animaker_labels.json'));
    final config = AnimakerLabelConfig(filePath: file.path);

    expect(await config.loadForCharacter('JM'), isEmpty);
    await file.writeAsString('{broken');
    expect(await config.loadForCharacter('JM'), isEmpty);
  });
}
