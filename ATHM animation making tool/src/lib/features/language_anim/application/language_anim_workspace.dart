import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/language_anim_codec.dart';
import '../domain/language_anim_models.dart';

class AnimationAssetStatus {
  const AnimationAssetStatus({
    required this.expectsAudio,
    required this.audioPath,
    required this.framesByName,
    required this.missingFrames,
  });

  final bool expectsAudio;
  final String? audioPath;
  final Map<String, String> framesByName;
  final List<String> missingFrames;

  bool get hasAudio => audioPath != null;
  bool get isComplete => (!expectsAudio || hasAudio) && missingFrames.isEmpty;
}

class LanguageAnimWorkspace {
  LanguageAnimWorkspace({
    required this.languageFilePath,
    required this.rootPath,
    required this.document,
    required Map<String, AnimationAssetStatus> statuses,
  }) : _statuses = statuses;

  final String languageFilePath;
  final String rootPath;
  LanguageAnimDocument document;
  final Map<String, AnimationAssetStatus> _statuses;

  AnimationAssetStatus statusFor(String characterId, String animationName) =>
      _statuses['${characterId.toUpperCase()}/${animationName.toUpperCase()}'] ??
      const AnimationAssetStatus(
        expectsAudio: false,
        audioPath: null,
        framesByName: {},
        missingFrames: [],
      );
}

class LanguageAnimWorkspaceService {
  const LanguageAnimWorkspaceService({this.codec = const LanguageAnimCodec()});

  final LanguageAnimCodec codec;

  String assetsRootPath(String workspaceRootPath) =>
      p.join(workspaceRootPath, 'graphics', 'dialog');

  String characterAssetsPath(String workspaceRootPath, String characterId) =>
      p.join(assetsRootPath(workspaceRootPath), characterId);

  String characterImagesPath(String workspaceRootPath, String characterId) =>
      p.join(characterAssetsPath(workspaceRootPath, characterId), 'images');

  String characterSoundsPath(String workspaceRootPath, String characterId) =>
      p.join(characterAssetsPath(workspaceRootPath, characterId), 'sounds');

  Future<LanguageAnimWorkspace> create(
    String languageFilePath,
    String firstCharacterId,
  ) async {
    final id = firstCharacterId.trim().toUpperCase();
    final document = LanguageAnimDocument(
      characters: [
        AthmCharacter(id: id, animations: [defaultIdleAnimation(id)]),
      ],
    );
    final file = File(languageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(codec.encode(document));
    return open(languageFilePath);
  }

  AthmAnimation defaultIdleAnimation(String characterId) => AthmAnimation(
    name: 'IDLE',
    loop: true,
    track: [
      AthmSegmentEntry(
        AthmSegment(
          frameChoices: ['${characterId.trim().toUpperCase()}DEF'],
          durationChoicesMs: const [1000],
        ),
      ),
    ],
  );

  AthmAnimation defaultAnimation(String characterId, String name) =>
      AthmAnimation(
        name: name.trim().toUpperCase(),
        track: [
          AthmSegmentEntry(
            AthmSegment(
              frameChoices: ['${characterId.trim().toUpperCase()}DEF'],
              durationChoicesMs: const [1000],
            ),
          ),
        ],
      );

  Future<void> save(
    LanguageAnimWorkspace workspace, {
    bool backup = true,
  }) async {
    final file = File(workspace.languageFilePath);
    if (backup && await file.exists()) {
      await file.copy('${file.path}.bak');
    }
    await file.writeAsString(codec.encode(workspace.document));
  }

  Future<LanguageAnimWorkspace> saveAs(
    LanguageAnimWorkspace workspace,
    String languageFilePath,
  ) async {
    final file = File(languageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(codec.encode(workspace.document));
    return open(languageFilePath);
  }

  Future<void> renameCharacterAssets(
    LanguageAnimWorkspace workspace,
    String oldId,
    String newId,
  ) async {
    final charactersRoot = assetsRootPath(workspace.rootPath);
    final source = Directory(p.join(charactersRoot, oldId));
    if (!await source.exists()) return;
    final destination = Directory(p.join(charactersRoot, newId));
    if (p.normalize(source.path).toLowerCase() ==
        p.normalize(destination.path).toLowerCase()) {
      if (source.path == destination.path) return;
      final temporary = Directory(
        p.join(
          charactersRoot,
          '.athm_rename_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await source.rename(temporary.path);
      await temporary.rename(destination.path);
      return;
    }
    if (await destination.exists()) {
      throw FileSystemException(
        'The destination character folder already exists.',
        destination.path,
      );
    }
    await source.rename(destination.path);
  }

  Future<LanguageAnimWorkspace> open(String languageFilePath) async {
    final source = await File(languageFilePath).readAsString();
    final document = codec.decode(source);
    final root = p.dirname(languageFilePath);
    final charactersRoot = Directory(assetsRootPath(root));
    await charactersRoot.create(recursive: true);

    for (final character in document.characters) {
      await Directory(
        p.join(charactersRoot.path, character.id, 'images'),
      ).create(recursive: true);
      await Directory(
        p.join(charactersRoot.path, character.id, 'sounds'),
      ).create(recursive: true);
    }

    final globalImages = await _indexFiles(
      [Directory(p.join(root, 'graphics', 'dialog'))],
      const {'.png', '.jpg', '.jpeg', '.webp'},
      recursive: false,
    );
    final globalSounds = await _indexFiles(
      [Directory(p.join(root, 'sounds', 'voices'))],
      const {'.ogg', '.wav', '.mp3', '.flac', '.m4a', '.aac'},
    );

    final statuses = <String, AnimationAssetStatus>{};
    for (final character in document.characters) {
      final characterRoot = p.join(charactersRoot.path, character.id);
      final localImages = await _indexFiles(
        [Directory(p.join(characterRoot, 'images'))],
        const {'.png', '.jpg', '.jpeg', '.webp'},
      );
      final localSounds = await _indexFiles(
        [Directory(p.join(characterRoot, 'sounds'))],
        const {'.ogg', '.wav', '.mp3', '.flac', '.m4a', '.aac'},
      );

      final images = <String, String>{...globalImages, ...localImages};
      final sounds = <String, String>{...globalSounds, ...localSounds};
      for (final animation in character.animations) {
        final framesByName = <String, String>{
          for (final path in images.values)
            p.basenameWithoutExtension(path): path,
        };
        final missing = <String>[];
        final frameNames = animation.segments
            .expand((segment) => segment.frameChoices)
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
        for (final frameName in frameNames) {
          final path = images[frameName.toUpperCase()];
          if (path == null) {
            missing.add(frameName);
          } else {
            framesByName[frameName] = path;
          }
        }

        final expectsAudio = animation.sound?.trim().isNotEmpty ?? false;
        final soundName = expectsAudio
            ? p.basenameWithoutExtension(animation.sound!.replaceAll('\\', '/'))
            : null;
        statuses['${character.id.toUpperCase()}/${animation.name.toUpperCase()}'] =
            AnimationAssetStatus(
              expectsAudio: expectsAudio,
              audioPath: soundName == null
                  ? null
                  : sounds[soundName.toUpperCase()],
              framesByName: framesByName,
              missingFrames: missing..sort(),
            );
      }
    }

    return LanguageAnimWorkspace(
      languageFilePath: languageFilePath,
      rootPath: root,
      document: document,
      statuses: statuses,
    );
  }

  Future<Map<String, String>> _indexFiles(
    List<Directory> roots,
    Set<String> extensions, {
    bool recursive = true,
  }) async {
    final result = <String, String>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final extension = p.extension(entity.path).toLowerCase();
        if (!extensions.contains(extension)) continue;
        result[p.basenameWithoutExtension(entity.path).toUpperCase()] =
            entity.path;
      }
    }
    return result;
  }
}
