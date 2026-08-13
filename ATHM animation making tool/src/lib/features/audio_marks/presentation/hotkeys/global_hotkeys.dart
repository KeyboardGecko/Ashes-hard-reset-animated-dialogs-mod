// lib/features/audio_marks/presentation/hotkeys/global_hotkeys.dart
// global_hotkeys.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'intents.dart';
import 'key_bindings.dart';

class GuardedShortcutManager extends ShortcutManager {
  GuardedShortcutManager({required this.isBlocked, required super.shortcuts});

  final bool Function() isBlocked;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (isBlocked()) return KeyEventResult.ignored; // пропускаем в EditableText
    return super.handleKeypress(context, event);
  }
}

class GlobalHotkeys extends StatefulWidget {
  const GlobalHotkeys({
    super.key,
    required this.child,
    required this.bindings,
    required this.onPlayPause,
    required this.onAddMark,
    required this.onSeek,
    required this.onRate,
    required this.onDeleteSelected,
    required this.onUndo,
    required this.onRedo,
    required this.onCopyFrames,
    required this.onCutFrames,
    required this.onPasteFrames,
    required this.onSaveAnimation,
    this.onCtrlChange,
    this.focusNode,
  });

  final Widget child;
  final KeyBindings bindings;
  final VoidCallback onPlayPause;
  final VoidCallback onAddMark;
  final ValueChanged<int> onSeek;
  final ValueChanged<double> onRate;
  final VoidCallback onDeleteSelected;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCopyFrames;
  final VoidCallback onCutFrames;
  final VoidCallback onPasteFrames;
  final VoidCallback onSaveAnimation;
  final void Function(bool down)? onCtrlChange;
  final FocusNode? focusNode;

  @override
  State<GlobalHotkeys> createState() => _GlobalHotkeysState();
}

class _GlobalHotkeysState extends State<GlobalHotkeys> {
  late GuardedShortcutManager _manager;

  bool _isEditingOrDropdown() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    final inEdit =
        ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
    final inDropdown =
        ctx.findAncestorWidgetOfExactType<DropdownButton<dynamic>>() != null ||
        ctx.findAncestorWidgetOfExactType<DropdownMenuItem<dynamic>>() != null;
    final inDialog =
        ctx.findAncestorWidgetOfExactType<AlertDialog>() != null ||
        ctx.findAncestorWidgetOfExactType<Dialog>() != null;
    return inEdit || inDropdown || inDialog;
  }

  @override
  void initState() {
    super.initState();
    _manager = GuardedShortcutManager(
      isBlocked: _isEditingOrDropdown,
      shortcuts: widget.bindings.shortcuts, // Map<ShortcutActivator, Intent>
    );
  }

  @override
  void didUpdateWidget(covariant GlobalHotkeys oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bindings.shortcuts, oldWidget.bindings.shortcuts)) {
      // В ShortcutManager shortcuts — settable, обновим без пересоздания менеджера
      _manager.shortcuts = widget.bindings.shortcuts;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts.manager(
      manager: _manager,
      child: Actions(
        actions: {
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onPlayPause();
              return null;
            },
          ),
          AddMarkIntent: CallbackAction<AddMarkIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onAddMark();
              return null;
            },
          ),
          SeekIntent: CallbackAction<SeekIntent>(
            onInvoke: (i) {
              if (!_isEditingOrDropdown()) widget.onSeek(i.deltaMs);
              return null;
            },
          ),
          RateIntent: CallbackAction<RateIntent>(
            onInvoke: (i) {
              if (!_isEditingOrDropdown()) widget.onRate(i.delta);
              return null;
            },
          ),
          DeleteSelectedIntent: CallbackAction<DeleteSelectedIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onDeleteSelected();
              return null;
            },
          ),
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onUndo();
              return null;
            },
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onRedo();
              return null;
            },
          ),
          CopyFramesIntent: CallbackAction<CopyFramesIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onCopyFrames();
              return null;
            },
          ),
          CutFramesIntent: CallbackAction<CutFramesIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onCutFrames();
              return null;
            },
          ),
          PasteFramesIntent: CallbackAction<PasteFramesIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onPasteFrames();
              return null;
            },
          ),
          SaveAnimationIntent: CallbackAction<SaveAnimationIntent>(
            onInvoke: (_) {
              if (!_isEditingOrDropdown()) widget.onSaveAnimation();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: true,
          onKeyEvent: (node, e) {
            // ctrl up/down для таймлайна
            if (widget.onCtrlChange != null &&
                (e.logicalKey == LogicalKeyboardKey.controlLeft ||
                    e.logicalKey == LogicalKeyboardKey.controlRight)) {
              if (_isEditingOrDropdown()) return KeyEventResult.ignored;
              if (e is KeyDownEvent) {
                widget.onCtrlChange!(true);
                return KeyEventResult.handled;
              }
              if (e is KeyUpEvent) {
                widget.onCtrlChange!(false);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// global_hotkeys.dart
