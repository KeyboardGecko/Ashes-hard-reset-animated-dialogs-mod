import 'dart:io';

import 'package:animaker/features/language_anim/application/language_anim_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('creates a new v3 project with an editable IDLE animation', () async {
    final root = await Directory.systemTemp.createTemp('athm_create_test_');
    addTearDown(() => root.delete(recursive: true));
    final languagePath = p.join(root.path, 'LANGUAGE_ANIM.txt');

    final workspace = await const LanguageAnimWorkspaceService().create(
      languagePath,
      'jm',
    );

    expect(await File(languagePath).exists(), isTrue);
    final character = workspace.document.characters.single;
    expect(character.id, 'JM');
    expect(character.animations.single.name, 'IDLE');
    expect(character.animations.single.loop, isTrue);
    expect(character.animations.single.segments.single.frameChoices, ['JMDEF']);
    expect(
      await Directory(
        p.join(root.path, 'graphics', 'dialog', 'JM', 'images'),
      ).exists(),
      isTrue,
    );
    expect(
      await Directory(
        p.join(root.path, 'graphics', 'dialog', 'JM', 'sounds'),
      ).exists(),
      isTrue,
    );
  });

  test('saveAs writes only the v3 project and creates asset roots', () async {
    final root = await Directory.systemTemp.createTemp('athm_save_as_test_');
    addTearDown(() => root.delete(recursive: true));
    const service = LanguageAnimWorkspaceService();
    final source = await service.create(
      p.join(root.path, 'source', 'LANGUAGE_ANIM.txt'),
      'JM',
    );
    final destination = p.join(root.path, 'copy', 'LANGUAGE_ANIM.txt');

    final copy = await service.saveAs(source, destination);

    expect(copy.languageFilePath, destination);
    expect(
      await File(destination).readAsString(),
      contains('ATHM_FORMAT = "3"'),
    );
    expect(
      await Directory(
        p.join(root.path, 'copy', 'graphics', 'dialog', 'JM', 'images'),
      ).exists(),
      isTrue,
    );
  });

  test('renames a character asset folder without losing media', () async {
    final root = await Directory.systemTemp.createTemp('athm_rename_test_');
    addTearDown(() => root.delete(recursive: true));
    const service = LanguageAnimWorkspaceService();
    final workspace = await service.create(
      p.join(root.path, 'LANGUAGE_ANIM.txt'),
      'JM',
    );
    final image = File(
      p.join(root.path, 'graphics', 'dialog', 'JM', 'images', 'JMDEF.png'),
    );
    await image.writeAsBytes([1, 2, 3]);

    await service.renameCharacterAssets(workspace, 'JM', 'JANE');

    expect(await image.exists(), isFalse);
    expect(
      await File(
        p.join(root.path, 'graphics', 'dialog', 'JANE', 'images', 'JMDEF.png'),
      ).exists(),
      isTrue,
    );
  });

  test('creates character asset folders and resolves local assets', () async {
    final root = await Directory.systemTemp.createTemp('athm_workspace_test_');
    addTearDown(() => root.delete(recursive: true));
    final language = File(p.join(root.path, 'LANGUAGE_ANIM.txt'));
    await language.writeAsString('''
[default]
ATHM_FORMAT = "3";
ATHM_CHARACTERS = "JM";
ATHM_JM_ANIMATIONS = "IDLE,JM001";
ATHM_JM_IDLE_TRACK = "JMDEF@1000";
ATHM_JM_IDLE_LOOP = "true";
ATHM_JM_JM001_TRACK = "JMDEF@100;[JMA@80;JMB@90]";
ATHM_JM_JM001_LOOP = "false";
ATHM_JM_JM001_SOUND = "JM001";
''');

    final images = Directory(
      p.join(root.path, 'graphics', 'dialog', 'JM', 'images'),
    );
    final sounds = Directory(
      p.join(root.path, 'graphics', 'dialog', 'JM', 'sounds'),
    );
    await images.create(recursive: true);
    await sounds.create(recursive: true);
    await File(p.join(images.path, 'JMDEF.png')).writeAsBytes([0]);
    await File(p.join(images.path, 'JMA.webp')).writeAsBytes([0]);
    await File(p.join(images.path, 'JMNEW.png')).writeAsBytes([0]);
    await File(p.join(sounds.path, 'JM001.ogg')).writeAsBytes([0]);

    final workspace = await const LanguageAnimWorkspaceService().open(
      language.path,
    );
    final status = workspace.statusFor('jm', 'jm001');
    final idleStatus = workspace.statusFor('jm', 'idle');

    expect(await images.exists(), isTrue);
    expect(await sounds.exists(), isTrue);
    expect(status.audioPath, endsWith('JM001.ogg'));
    expect(status.expectsAudio, isTrue);
    expect(idleStatus.expectsAudio, isFalse);
    expect(idleStatus.isComplete, isTrue);
    expect(status.framesByName.keys, containsAll(['JMDEF', 'JMA']));
    expect(status.framesByName.keys, contains('JMNEW'));
    expect(status.missingFrames, ['JMB']);
  });
}
