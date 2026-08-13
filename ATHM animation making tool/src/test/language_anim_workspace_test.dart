import 'dart:io';

import 'package:animaker/features/language_anim/application/language_anim_workspace.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('creates a new v4 project with an editable IDLE animation', () async {
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
      await Directory(p.join(root.path, 'graphics', 'dialog', 'JM')).exists(),
      isTrue,
    );
    expect(
      await Directory(p.join(root.path, 'sounds', 'voices')).exists(),
      isTrue,
    );
  });

  test('saveAs writes only the v4 project and creates asset roots', () async {
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
      contains('ATHM_FORMAT = "4"'),
    );
    expect(
      await Directory(
        p.join(root.path, 'copy', 'graphics', 'dialog', 'JM'),
      ).exists(),
      isTrue,
    );
    expect(
      await Directory(p.join(root.path, 'copy', 'sounds', 'voices')).exists(),
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
      p.join(root.path, 'graphics', 'dialog', 'JM', 'JMDEF.png'),
    );
    await image.writeAsBytes([1, 2, 3]);

    await service.renameCharacterAssets(workspace, 'JM', 'JANE');

    expect(await image.exists(), isFalse);
    expect(
      await File(
        p.join(root.path, 'graphics', 'dialog', 'JANE', 'JMDEF.png'),
      ).exists(),
      isTrue,
    );
  });

  test('imports backgrounds directly into the character folder', () async {
    final root = await Directory.systemTemp.createTemp('athm_bg_import_test_');
    addTearDown(() => root.delete(recursive: true));
    const service = LanguageAnimWorkspaceService();
    final workspace = await service.create(
      p.join(root.path, 'LANGUAGE_ANIM.txt'),
      'JM',
    );
    final source = File(p.join(root.path, 'scene.png'));
    await source.writeAsBytes([1, 2, 3]);

    final imported = await service.importBackground(
      workspace,
      'JM',
      source.path,
    );

    expect(
      imported,
      p.join(root.path, 'graphics', 'dialog', 'JM', 'scene.png'),
    );
    expect(await File(imported).exists(), isTrue);
    expect(
      await Directory(
        p.join(root.path, 'graphics', 'dialog', 'JM', 'backgrounds'),
      ).exists(),
      isFalse,
    );
  });

  test('creates character asset folders and resolves local assets', () async {
    final root = await Directory.systemTemp.createTemp('athm_workspace_test_');
    addTearDown(() => root.delete(recursive: true));
    final language = File(p.join(root.path, 'LANGUAGE_ANIM.txt'));
    await language.writeAsString('''
[default]
ATHM_FORMAT = "4";
ATHM_CHARACTERS = "JM";
ATHM_JM_ANIMATIONS = "IDLE,JM001";
ATHM_JM_IDLE_TRACK = "JMDEF@1000";
ATHM_JM_IDLE_LOOP = "true";
ATHM_JM_IDLE_BACKGROUND = "JMDEF";
ATHM_JM_JM001_TRACK = "JMDEF@100;[JMA@80;JMB@90]";
ATHM_JM_JM001_LOOP = "false";
ATHM_JM_JM001_BACKGROUND = "JM_SCENE";
ATHM_JM_JM001_SOUND = "JM001";
''');

    final images = Directory(p.join(root.path, 'graphics', 'dialog', 'JM'));
    final sounds = Directory(p.join(root.path, 'sounds', 'voices'));
    await images.create(recursive: true);
    await sounds.create(recursive: true);
    await File(p.join(images.path, 'JMDEF.png')).writeAsBytes([0]);
    await File(p.join(images.path, 'JMA.webp')).writeAsBytes([0]);
    await File(p.join(images.path, 'JMNEW.png')).writeAsBytes([0]);
    await File(p.join(images.path, 'JM_SCENE.png')).writeAsBytes([0]);
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
    expect(status.framesByName.keys, contains('JM_SCENE'));
    expect(
      status.backgroundCandidatesByName.keys,
      containsAll(['JMDEF', 'JM_SCENE']),
    );
    expect(status.backgroundPath, endsWith('JM_SCENE.png'));
    expect(status.missingBackground, isNull);
    expect(idleStatus.backgroundPath, endsWith('JMDEF.png'));
    expect(status.missingFrames, ['JMB']);
  });

  test(
    'reports a missing animation background without hiding frames',
    () async {
      final root = await Directory.systemTemp.createTemp('athm_bg_test_');
      addTearDown(() => root.delete(recursive: true));
      final language = File(p.join(root.path, 'LANGUAGE_ANIM.txt'));
      await language.writeAsString('''
ATHM_FORMAT = "4";
ATHM_CHARACTERS = "JM";
ATHM_JM_ANIMATIONS = "IDLE";
ATHM_JM_IDLE_TRACK = "JMDEF@1000";
ATHM_JM_IDLE_BACKGROUND = "MISSING_BG";
''');
      final images = Directory(p.join(root.path, 'graphics', 'dialog', 'JM'));
      await images.create(recursive: true);
      await File(p.join(images.path, 'JMDEF.png')).writeAsBytes([0]);

      final workspace = await const LanguageAnimWorkspaceService().open(
        language.path,
      );
      final status = workspace.statusFor('JM', 'IDLE');

      expect(status.framesByName.keys, contains('JMDEF'));
      expect(status.missingFrames, isEmpty);
      expect(status.backgroundPath, isNull);
      expect(status.missingBackground, 'MISSING_BG');
      expect(status.isComplete, isFalse);
    },
  );

  test('missing override falls back to the character background', () async {
    final root = await Directory.systemTemp.createTemp('athm_bg_fallback_test_');
    addTearDown(() => root.delete(recursive: true));
    final language = File(p.join(root.path, 'LANGUAGE_ANIM.txt'));
    await language.writeAsString('''
ATHM_FORMAT = "4";
ATHM_CHARACTERS = "JM";
ATHM_JM_ANIMATIONS = "IDLE";
ATHM_JM_BACKGROUND = "JM_DEFAULT_BG";
ATHM_JM_IDLE_TRACK = "JMDEF@1000";
ATHM_JM_IDLE_BACKGROUND = "MISSING_OVERRIDE";
''');
    final images = Directory(p.join(root.path, 'graphics', 'dialog', 'JM'));
    await images.create(recursive: true);
    await File(p.join(images.path, 'JMDEF.png')).writeAsBytes([0]);
    await File(p.join(images.path, 'JM_DEFAULT_BG.png')).writeAsBytes([0]);

    final workspace = await const LanguageAnimWorkspaceService().open(
      language.path,
    );
    final status = workspace.statusFor('JM', 'IDLE');

    expect(status.backgroundPath, endsWith('JM_DEFAULT_BG.png'));
    expect(status.missingBackground, 'MISSING_OVERRIDE');
  });

  test('save writes SNDINFO aliases for optional block sounds', () async {
    final root = await Directory.systemTemp.createTemp('athm_sndinfo_test_');
    addTearDown(() => root.delete(recursive: true));
    const service = LanguageAnimWorkspaceService();
    final workspace = await service.create(
      p.join(root.path, 'LANGUAGE_ANIM.txt'),
      'JM',
    );
    final character = workspace.document.characters.single;
    final idle = character.animations.single;
    workspace.document = workspace.document.copyWith(
      characters: [
        character.copyWith(
          animations: [
            idle.copyWith(
              track: const [
                AthmSegmentEntry(
                  AthmSegment(
                    frameChoices: ['JMDEF'],
                    durationChoicesMs: [500],
                  ),
                ),
                AthmOptionalLockedSequence(
                  sound: 'JM_BLINK',
                  items: [
                    AthmSegment(
                      frameChoices: ['JMBLK'],
                      durationChoicesMs: [125],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await service.save(workspace, backup: false);

    expect(
      await File(p.join(root.path, 'SNDINFO')).readAsString(),
      contains('JM_BLINK sounds/voices/JM_BLINK'),
    );
  });
}
