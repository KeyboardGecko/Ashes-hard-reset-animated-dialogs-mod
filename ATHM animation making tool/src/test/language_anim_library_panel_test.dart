import 'package:animaker/features/language_anim/application/language_anim_workspace.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:animaker/features/language_anim/presentation/language_anim_library_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting a character loads its idle without closing library', (
    tester,
  ) async {
    const idleA = AthmAnimation(name: 'IDLE', track: []);
    const idleB = AthmAnimation(name: 'IDLE', track: []);
    const talkB = AthmAnimation(name: 'B001', track: []);
    const characterA = AthmCharacter(id: 'A', animations: [idleA]);
    const characterB = AthmCharacter(id: 'B', animations: [talkB, idleB]);
    final workspace = LanguageAnimWorkspace(
      languageFilePath: 'LANGUAGE_ANIM.txt',
      rootPath: '.',
      document: const LanguageAnimDocument(
        characters: [characterA, characterB],
      ),
      statuses: const {},
    );
    AthmCharacter? loadedCharacter;
    AthmAnimation? loadedAnimation;
    var closed = false;

    Future<void> noopCharacter(AthmCharacter _) async {}
    Future<void> noopAnimation(AthmCharacter _, AthmAnimation __) async {}

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LanguageAnimLibraryPanel(
            workspace: workspace,
            selectedCharacterId: 'A',
            selectedAnimationName: 'IDLE',
            onSelected: noopAnimation,
            onCharacterSelected: (character, animation) async {
              loadedCharacter = character;
              loadedAnimation = animation;
            },
            onAddCharacter: () async {},
            onAddAnimation: noopCharacter,
            onSetCharacterBackground: noopCharacter,
            onRenameCharacter: noopCharacter,
            onDeleteCharacter: noopCharacter,
            onRenameAnimation: noopAnimation,
            onDeleteAnimation: noopAnimation,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();

    expect(loadedCharacter?.id, 'B');
    expect(loadedAnimation?.name, 'IDLE');
    expect(closed, isFalse);
    expect(find.text('Animation library'), findsOneWidget);
  });
}
