import 'package:animaker/features/language_anim/application/language_anim_session_store.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = LanguageAnimSessionStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns no session before a project has been opened', () async {
    expect(await store.load(), isNull);
  });

  test('persists and restores the last project selection', () async {
    await store.save(
      languageFilePath: r'D:\mods\LANGUAGE_ANIM.txt',
      characterId: 'JM',
      animationName: 'JM015',
    );

    final session = await store.load();

    expect(session, isNotNull);
    expect(session!.languageFilePath, r'D:\mods\LANGUAGE_ANIM.txt');
    expect(session.characterId, 'JM');
    expect(session.animationName, 'JM015');
  });

  test('clears every stored session value', () async {
    await store.save(
      languageFilePath: r'D:\mods\LANGUAGE_ANIM.txt',
      characterId: 'JM',
      animationName: 'IDLE',
    );

    await store.clear();

    expect(await store.load(), isNull);
  });

  test('falls back to IDLE when the remembered animation is gone', () {
    final document = LanguageAnimDocument(
      characters: [
        AthmCharacter(
          id: 'JM',
          animations: [
            AthmAnimation(
              name: 'IDLE',
              loop: true,
              track: [
                AthmSegmentEntry(
                  AthmSegment(
                    frameChoices: ['JMDEF'],
                    durationChoicesMs: [1000],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    const session = LanguageAnimSession(
      languageFilePath: 'LANGUAGE_ANIM.txt',
      characterId: 'JM',
      animationName: 'DELETED',
    );

    final selection = resolveLanguageAnimSessionSelection(document, session);

    expect(selection.character.id, 'JM');
    expect(selection.animation.name, 'IDLE');
  });

  test('falls back to the first character when the remembered one is gone', () {
    final document = LanguageAnimDocument(
      characters: [
        AthmCharacter(
          id: 'AND',
          animations: [
            AthmAnimation(
              name: 'IDLE',
              loop: true,
              track: [
                AthmSegmentEntry(
                  AthmSegment(
                    frameChoices: ['ANDDEF'],
                    durationChoicesMs: [1000],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    const session = LanguageAnimSession(
      languageFilePath: 'LANGUAGE_ANIM.txt',
      characterId: 'DELETED',
      animationName: 'DELETED',
    );

    final selection = resolveLanguageAnimSessionSelection(document, session);

    expect(selection.character.id, 'AND');
    expect(selection.animation.name, 'IDLE');
  });
}
