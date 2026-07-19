// lib/features/audio_marks/presentation/hotkeys/key_bindings.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'intents.dart';

class KeyBindings {
  final Map<ShortcutActivator, Intent> shortcuts;
  final Set<LogicalKeyboardKey> ctrlKeys;

  KeyBindings({required this.shortcuts, required this.ctrlKeys});

  factory KeyBindings.defaultDesktop({
    int seekStepMs = 15,
    double rateStep = 0.15,
  }) {
    final s = seekStepMs;
    final r = rateStep;

    return KeyBindings(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.space): const PlayPauseIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyB): const AddMarkIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): SeekIntent(s),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): SeekIntent(-s),
        LogicalKeySet(LogicalKeyboardKey.equal): RateIntent(r),
        LogicalKeySet(LogicalKeyboardKey.minus): RateIntent(-r),
        LogicalKeySet(LogicalKeyboardKey.delete): const DeleteSelectedIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyX):
            const CutFramesIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyX):
            const CutFramesIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyS):
            const SaveAnimationIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyS):
            const SaveAnimationIntent(),
        // LogicalKeySet(LogicalKeyboardKey.backspace):
        //     const DeleteSelectedIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ):
            const UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyZ): const UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyZ):
            const UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY):
            const RedoIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.arrowLeft,
        ): SeekIntent(
          -4,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.arrowRight,
        ): SeekIntent(
          4,
        ),
        LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyY):
            const RedoIntent(),
        // (опционально) Ctrl+Shift+Z как redo:
        LogicalKeySet(
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyZ,
        ): const RedoIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.shiftRight,
          LogicalKeyboardKey.keyZ,
        ): const RedoIntent(),
      },
      ctrlKeys: {
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      },
    );
  }
}
