// lib/features/audio_marks/presentation/hotkeys/keybindings_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'keymap_controller.dart';

class KeybindingsDialog extends StatefulWidget {
  final KeymapController controller;
  const KeybindingsDialog({super.key, required this.controller});

  @override
  State<KeybindingsDialog> createState() => _KeybindingsDialogState();
}

class _KeybindingsDialogState extends State<KeybindingsDialog> {
  final FocusNode _captureFocus = FocusNode();
  HotAction? capturing; // какое действие сейчас ждёт нажатие

  bool _isModifier(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight ||
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight ||
      k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight;

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Key bindings'),
      content: KeyboardListener(
        focusNode: _captureFocus,
        autofocus: true,
        onKeyEvent: (KeyEvent e) {
          if (capturing == null || e is! KeyDownEvent) return;

          // Текущий набор зажатых клавиш (новый API)
          final pressed = HardwareKeyboard.instance.logicalKeysPressed;

          // Игнор, если только модификаторы
          if (pressed.isEmpty || pressed.every(_isModifier)) return;

          widget.controller.setBinding(capturing!, pressed);
          setState(() => capturing = null);
        },
        child: SizedBox(
          width: 420,
          child: ValueListenableBuilder(
            valueListenable: widget.controller.map,
            builder: (_, __, ___) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final a in HotAction.values) _row(a)],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => widget.controller.resetDefaults(),
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            await widget.controller.save();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _row(HotAction a) {
    final chord = widget.controller.map.value[a] ?? {};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(_title(a))),
          Text(describeChord(chord)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () {
              setState(() => capturing = a);
              _captureFocus.requestFocus(); // фокусим слушатель для захвата
            },
            child: Text(capturing == a ? 'Press keys…' : 'Change'),
          ),
        ],
      ),
    );
  }

  String _title(HotAction a) => switch (a) {
    HotAction.playPause => 'Play / Pause',
    HotAction.addMark => 'Add mark',
    HotAction.seekLeft => 'Seek left',
    HotAction.seekRight => 'Seek right',
    HotAction.rateUp => 'Rate +',
    HotAction.rateDown => 'Rate −',
    HotAction.deleteSelected => 'Delete selected',
  };
}
