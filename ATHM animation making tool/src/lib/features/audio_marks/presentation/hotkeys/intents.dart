// lib/features/audio_marks/presentation/hotkeys/intents.dart
import 'package:flutter/widgets.dart';

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class AddMarkIntent extends Intent {
  const AddMarkIntent();
}

class SeekIntent extends Intent {
  const SeekIntent(this.deltaMs);
  final int deltaMs;
}

class RateIntent extends Intent {
  const RateIntent(this.delta);
  final double delta;
}

class DeleteSelectedIntent extends Intent {
  const DeleteSelectedIntent();
}

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class CopyFramesIntent extends Intent {
  const CopyFramesIntent();
}

class PasteFramesIntent extends Intent {
  const PasteFramesIntent();
}

class CtrlIntent extends Intent {
  const CtrlIntent(this.down);
  final bool down;
} // для единообразия (не обязателен)
