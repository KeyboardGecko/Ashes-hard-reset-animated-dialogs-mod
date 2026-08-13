import 'package:shared_preferences/shared_preferences.dart';

import '../domain/language_anim_models.dart';

class LanguageAnimSession {
  const LanguageAnimSession({
    required this.languageFilePath,
    this.characterId,
    this.animationName,
  });

  final String languageFilePath;
  final String? characterId;
  final String? animationName;
}

class LanguageAnimSessionStore {
  const LanguageAnimSessionStore();

  static const _pathKey = 'language_anim.last_path';
  static const _characterKey = 'language_anim.last_character';
  static const _animationKey = 'language_anim.last_animation';

  Future<LanguageAnimSession?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final path = preferences.getString(_pathKey)?.trim();
    if (path == null || path.isEmpty) return null;
    return LanguageAnimSession(
      languageFilePath: path,
      characterId: _nonEmpty(preferences.getString(_characterKey)),
      animationName: _nonEmpty(preferences.getString(_animationKey)),
    );
  }

  Future<void> save({
    required String languageFilePath,
    required String characterId,
    required String animationName,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pathKey, languageFilePath);
    await preferences.setString(_characterKey, characterId);
    await preferences.setString(_animationKey, animationName);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pathKey);
    await preferences.remove(_characterKey);
    await preferences.remove(_animationKey);
  }

  String? _nonEmpty(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }
}

class LanguageAnimSessionSelection {
  const LanguageAnimSessionSelection({
    required this.character,
    required this.animation,
  });

  final AthmCharacter character;
  final AthmAnimation animation;
}

LanguageAnimSessionSelection resolveLanguageAnimSessionSelection(
  LanguageAnimDocument document,
  LanguageAnimSession session,
) {
  final character =
      document.characterById(session.characterId ?? '') ??
      document.characters.first;
  final rememberedName = session.animationName?.toUpperCase();
  if (rememberedName != null) {
    for (final animation in character.animations) {
      if (animation.name.toUpperCase() == rememberedName) {
        return LanguageAnimSessionSelection(
          character: character,
          animation: animation,
        );
      }
    }
  }
  final fallback = character.animations.firstWhere(
    (animation) => animation.name.toUpperCase() == 'IDLE',
    orElse: () => character.animations.first,
  );
  return LanguageAnimSessionSelection(
    character: character,
    animation: fallback,
  );
}
