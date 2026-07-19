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
    this.backgroundCandidatesByName = const {},
    this.backgroundPath,
    this.missingBackground,
    this.soundsByName = const {},
    this.missingOptionalSounds = const [],
  });

  final bool expectsAudio;
  final String? audioPath;
  final Map<String, String> framesByName;
  final List<String> missingFrames;
  final Map<String, String> backgroundCandidatesByName;
  final String? backgroundPath;
  final String? missingBackground;
  final Map<String, String> soundsByName;
  final List<String> missingOptionalSounds;

  bool get hasAudio => audioPath != null;
  bool get isComplete =>
      (!expectsAudio || hasAudio) &&
      missingFrames.isEmpty &&
      missingBackground == null &&
      missingOptionalSounds.isEmpty;
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
        backgroundCandidatesByName: {},
        soundsByName: {},
        missingOptionalSounds: [],
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
      characterAssetsPath(workspaceRootPath, characterId);

  String soundsRootPath(String workspaceRootPath) =>
      p.join(workspaceRootPath, 'sounds', 'voices');

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
    await _ensureOptionalSoundAliases(workspace);
  }

  Future<void> _ensureOptionalSoundAliases(
    LanguageAnimWorkspace workspace,
  ) async {
    final sounds =
        workspace.document.characters
            .expand((character) => character.animations)
            .expand((animation) => animation.track)
            .whereType<AthmOptionalLockedSequence>()
            .map((entry) => entry.sound?.trim())
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .map(
              (name) => p.basenameWithoutExtension(name.replaceAll('\\', '/')),
            )
            .toSet()
            .toList()
          ..sort();
    if (sounds.isEmpty) return;

    final file = File(p.join(workspace.rootPath, 'SNDINFO'));
    final existing = await file.exists() ? await file.readAsString() : '';
    final additions = <String>[];
    for (final sound in sounds) {
      final escaped = RegExp.escape(sound);
      if (RegExp(
        '^\\s*$escaped\\s+',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(existing)) {
        continue;
      }
      additions.add('$sound sounds/voices/$sound');
    }
    if (additions.isEmpty) return;
    final prefix = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    await file.writeAsString(
      '$existing$prefix// ATHM optional block sounds\n'
      '${additions.join('\n')}\n',
    );
  }

  Future<LanguageAnimWorkspace> saveAs(
    LanguageAnimWorkspace workspace,
    String languageFilePath,
  ) async {
    final file = File(languageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(codec.encode(workspace.document));
    final reopened = await open(languageFilePath);
    await _ensureOptionalSoundAliases(reopened);
    return reopened;
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

  Future<String> importBackground(
    LanguageAnimWorkspace workspace,
    String characterId,
    String sourcePath,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Background image does not exist.', sourcePath);
    }
    final extension = p.extension(source.path).toLowerCase();
    if (!const {'.png', '.jpg', '.jpeg', '.webp'}.contains(extension)) {
      throw FileSystemException(
        'Background must be PNG, JPG, JPEG, or WEBP.',
        sourcePath,
      );
    }

    final targetDirectory = Directory(
      characterAssetsPath(workspace.rootPath, characterId),
    );
    await targetDirectory.create(recursive: true);
    final baseName = p.basenameWithoutExtension(source.path);
    var destination = File(p.join(targetDirectory.path, '$baseName$extension'));
    var suffix = 2;
    while (await destination.exists() &&
        p.normalize(destination.path).toLowerCase() !=
            p.normalize(source.path).toLowerCase()) {
      destination = File(
        p.join(targetDirectory.path, '${baseName}_$suffix$extension'),
      );
      suffix++;
    }
    if (p.normalize(destination.path).toLowerCase() !=
        p.normalize(source.path).toLowerCase()) {
      await source.copy(destination.path);
    }
    return destination.path;
  }

  Future<LanguageAnimWorkspace> open(String languageFilePath) async {
    final source = await File(languageFilePath).readAsString();
    final document = codec.decode(source);
    final root = p.dirname(languageFilePath);
    final charactersRoot = Directory(assetsRootPath(root));
    await charactersRoot.create(recursive: true);
    await Directory(soundsRootPath(root)).create(recursive: true);

    for (final character in document.characters) {
      await Directory(
        characterImagesPath(root, character.id),
      ).create(recursive: true);
    }

    final globalImages = await _indexFiles(
      [Directory(p.join(root, 'graphics', 'dialog'))],
      const {'.png', '.jpg', '.jpeg', '.webp'},
      recursive: false,
    );
    final globalSounds = await _indexFiles(
      [Directory(soundsRootPath(root))],
      const {'.ogg', '.wav', '.mp3', '.flac', '.m4a', '.aac'},
    );

    final statuses = <String, AnimationAssetStatus>{};
    for (final character in document.characters) {
      final characterRoot = p.join(charactersRoot.path, character.id);
      final localImages = await _indexFiles(
        [Directory(characterRoot)],
        const {'.png', '.jpg', '.jpeg', '.webp'},
      );

      final images = <String, String>{...globalImages, ...localImages};
      final backgroundCandidates = Map<String, String>.from(images);
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
        final requestedBackgroundName = animation.disablesBackground
            ? null
            : animation.background?.trim() ?? character.background?.trim();
        final requestedBackgroundPath =
            requestedBackgroundName == null || requestedBackgroundName.isEmpty
            ? null
            : backgroundCandidates[requestedBackgroundName.toUpperCase()];
        final missingBackground =
            requestedBackgroundName != null &&
                requestedBackgroundName.isNotEmpty &&
                requestedBackgroundPath == null
            ? requestedBackgroundName
            : null;
        final inheritedBackgroundName = character.background?.trim();
        final backgroundPath =
            requestedBackgroundPath ??
            (animation.hasCustomBackground &&
                    inheritedBackgroundName != null &&
                    inheritedBackgroundName.isNotEmpty
                ? backgroundCandidates[inheritedBackgroundName.toUpperCase()]
                : null);
        final soundName = expectsAudio
            ? p.basenameWithoutExtension(animation.sound!.replaceAll('\\', '/'))
            : null;
        final missingOptionalSounds = <String>[];
        for (final entry
            in animation.track.whereType<AthmOptionalLockedSequence>()) {
          final blockSound = entry.sound?.trim();
          if (blockSound == null || blockSound.isEmpty) continue;
          final baseName = p.basenameWithoutExtension(
            blockSound.replaceAll('\\', '/'),
          );
          if (!globalSounds.containsKey(baseName.toUpperCase())) {
            missingOptionalSounds.add(blockSound);
          }
        }
        statuses['${character.id.toUpperCase()}/${animation.name.toUpperCase()}'] =
            AnimationAssetStatus(
              expectsAudio: expectsAudio,
              audioPath: soundName == null
                  ? null
                  : globalSounds[soundName.toUpperCase()],
              framesByName: framesByName,
              missingFrames: missing..sort(),
              backgroundCandidatesByName: {
                for (final entry in backgroundCandidates.entries)
                  p.basenameWithoutExtension(entry.value): entry.value,
              },
              backgroundPath: backgroundPath,
              missingBackground: missingBackground,
              soundsByName: Map<String, String>.from(globalSounds),
              missingOptionalSounds: missingOptionalSounds..sort(),
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
