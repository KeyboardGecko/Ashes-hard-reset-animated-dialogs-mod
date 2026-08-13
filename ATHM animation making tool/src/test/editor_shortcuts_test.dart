import 'package:animaker/features/audio_marks/presentation/hotkeys/intents.dart';
import 'package:animaker/features/audio_marks/presentation/hotkeys/keymap_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop editor binds save and cut shortcuts', () {
    final shortcuts = KeymapController().toKeyBindings().shortcuts;

    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyS, control: true)],
      isA<SaveAnimationIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyX, control: true)],
      isA<CutFramesIntent>(),
    );
  });
}
