// lib/features/audio_marks/presentation/hotkeys/keymap_controller.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'intents.dart';
import 'key_bindings.dart'; // ДОЛЖЕН принимать Map<ShortcutActivator, Intent>
import 'package:shared_preferences/shared_preferences.dart';

enum HotAction {
  playPause,
  addMark,
  seekLeft,
  seekRight,
  rateUp,
  rateDown,
  deleteSelected,
}

bool _isModifier(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.shiftLeft ||
    k == LogicalKeyboardKey.shiftRight ||
    k == LogicalKeyboardKey.altLeft ||
    k == LogicalKeyboardKey.altRight ||
    k == LogicalKeyboardKey.metaLeft ||
    k == LogicalKeyboardKey.metaRight ||
    k == LogicalKeyboardKey.controlLeft ||
    k == LogicalKeyboardKey.controlRight;

String _prettyKey(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.space) return 'Spacebar';
  if (k == LogicalKeyboardKey.enter) return 'Enter';
  if (k == LogicalKeyboardKey.backspace) return 'Backspace';
  if (k == LogicalKeyboardKey.delete) return 'Delete';
  if (k == LogicalKeyboardKey.arrowLeft) return 'Left';
  if (k == LogicalKeyboardKey.arrowRight) return 'Right';
  if (k == LogicalKeyboardKey.arrowUp) return 'Up';
  if (k == LogicalKeyboardKey.arrowDown) return 'Down';
  if (k == LogicalKeyboardKey.equal) return '=';
  if (k == LogicalKeyboardKey.minus) return '-';

  final lbl = k.keyLabel.trim();
  if (lbl.isNotEmpty) return lbl.toUpperCase();
  return k.debugName ?? 'Key(${k.keyId})';
}

String describeChord(Set<LogicalKeyboardKey> keys) {
  final parts = <String>[];
  final s = keys;

  if (s.contains(LogicalKeyboardKey.controlLeft) ||
      s.contains(LogicalKeyboardKey.controlRight)) {
    parts.add('Ctrl');
  }
  if (s.contains(LogicalKeyboardKey.altLeft) ||
      s.contains(LogicalKeyboardKey.altRight)) {
    parts.add('Alt');
  }
  if (s.contains(LogicalKeyboardKey.shiftLeft) ||
      s.contains(LogicalKeyboardKey.shiftRight)) {
    parts.add('Shift');
  }

  final mains = s.where((k) => !_isModifier(k));
  parts.addAll(mains.map(_prettyKey));
  return parts.join(' + ');
}

/// Преобразует набор логических клавиш в ShortcutActivator (SingleActivator).
ShortcutActivator _toActivator(Set<LogicalKeyboardKey> chord) {
  bool has(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
      chord.contains(a) || chord.contains(b);

  final control = has(
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  );
  final shift = has(
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  );
  final alt = has(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight);
  final meta = has(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight);

  final main = chord.firstWhere(
    (k) => !_isModifier(k),
    orElse: () => LogicalKeyboardKey.space,
  );

  return SingleActivator(
    main,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

class KeymapController extends ChangeNotifier {
  /// действие -> набор клавиш (с модификаторами)
  final ValueNotifier<Map<HotAction, Set<LogicalKeyboardKey>>> map =
      ValueNotifier(<HotAction, Set<LogicalKeyboardKey>>{});

  KeymapController() {
    map.value = _defaults();
  }

  Map<HotAction, Set<LogicalKeyboardKey>> _defaults() => {
    HotAction.playPause: {LogicalKeyboardKey.space},
    HotAction.addMark: {LogicalKeyboardKey.keyB},
    HotAction.seekRight: {LogicalKeyboardKey.arrowRight},
    HotAction.seekLeft: {LogicalKeyboardKey.arrowLeft},
    HotAction.rateUp: {LogicalKeyboardKey.equal},
    HotAction.rateDown: {LogicalKeyboardKey.minus},
    HotAction.deleteSelected: {LogicalKeyboardKey.delete},
  };

  void setBinding(HotAction a, Set<LogicalKeyboardKey> chord) {
    final next = Map<HotAction, Set<LogicalKeyboardKey>>.from(map.value);
    next[a] = chord;
    map.value = next;
    notifyListeners();
  }

  void resetDefaults() {
    map.value = _defaults();
    notifyListeners();
  }

  // -------- persistence --------
  static const _prefsKey = 'keymap.v1';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final restored = <HotAction, Set<LogicalKeyboardKey>>{};
      for (final entry in json.entries) {
        final a = HotAction.values.firstWhere(
          (e) => e.name == entry.key,
          orElse: () => HotAction.playPause,
        );
        final ids = (entry.value as List).cast<int>();
        restored[a] = ids
            .map(
              (id) =>
                  LogicalKeyboardKey.findKeyByKeyId(id) ??
                  LogicalKeyboardKey(id),
            )
            .toSet();
      }
      map.value = restored;
      notifyListeners();
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    final json = <String, List<int>>{};
    map.value.forEach(
      (a, chord) => json[a.name] = chord.map((k) => k.keyId).toList(),
    );
    await sp.setString(_prefsKey, jsonEncode(json));
  }

  // ---- адаптация под GlobalHotkeys (НОВЫЙ API) ----
  KeyBindings toKeyBindings({int seekStepMs = 15, double rateStep = 0.15}) {
    final m = map.value;

    final shortcuts = <ShortcutActivator, Intent>{
      _toActivator(m[HotAction.playPause] ?? {}): const PlayPauseIntent(),
      _toActivator(m[HotAction.addMark] ?? {}): const AddMarkIntent(),
      _toActivator(m[HotAction.seekRight] ?? {}): SeekIntent(4),
      _toActivator(m[HotAction.seekLeft] ?? {}): SeekIntent(-4),
      _toActivator(m[HotAction.rateUp] ?? {}): RateIntent(rateStep),
      _toActivator(m[HotAction.rateDown] ?? {}): RateIntent(-rateStep),
      _toActivator(m[HotAction.deleteSelected] ?? {}):
          const DeleteSelectedIntent(),
      // Дубликат Backspace на удаление (по умолчанию удобно)
      const SingleActivator(LogicalKeyboardKey.backspace):
          const DeleteSelectedIntent(),
      // Undo/Redo по умолчанию (можно тоже сделать настраиваемыми при желании)
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
          const UndoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true):
          const RedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          const CopyFramesIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true):
          const CutFramesIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true):
          const PasteFramesIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          const SaveAnimationIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): const RedoIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
          SeekIntent(-seekStepMs),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
          SeekIntent(seekStepMs),
    };

    return KeyBindings(
      shortcuts: shortcuts,
      ctrlKeys: {
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      },
    );
  }
}
