import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;
import 'package:animaker/features/audio_marks/application/history_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:path/path.dart' as p;
import 'package:animaker/features/language_anim/application/animaker_label_config.dart';
import 'package:animaker/features/language_anim/application/language_anim_session_store.dart';
import 'package:animaker/features/language_anim/application/language_anim_workspace.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:animaker/features/language_anim/presentation/animation_background_dialog.dart';
import 'package:animaker/features/language_anim/presentation/language_anim_library_panel.dart';

// существующие виджеты из вашего проекта
import 'package:animaker/widgets/zoomable_timeline.dart';
import 'package:animaker/widgets/inline_label_editor.dart';
import 'package:animaker/widgets/label_image_slot.dart';
import 'package:animaker/widgets/playback_player_preview.dart';

// новые части
import '../../../application/audio_transcode.dart';
import '../../../application/frame_clipboard.dart';
import '../../../application/marks_to_athm_track.dart';
import '../../../application/optional_audio_timeline.dart';
import '../../../application/timeline_duration.dart';
import '../../../domain/entities/clip_mark.dart';
import '../../../domain/services/playback_controller.dart';
import '../../../domain/services/animation_clock.dart';
import '../../../domain/services/marks_controller.dart';
import '../../../domain/services/label_image_service.dart';
import '../../hotkeys/global_hotkeys.dart';
import '../../hotkeys/keybindings_dialog.dart';
import '../../hotkeys/keymap_controller.dart';
import '../../images/label_images_panel.dart';
import '../../widgets/project_menu.dart';
import '../../widgets/playback_toolbar.dart';
import '../step_variants_dialog.dart';

final _itemScrollCtrl = ItemScrollController();
final _itemPositions = ItemPositionsListener.create();

enum _UnsavedAnimationChoice { save, discard, cancel }

class _OptionalAudioCue {
  const _OptionalAudioCue({
    required this.groupId,
    required this.path,
    required this.startMs,
  });

  final String groupId;
  final String path;
  final double startMs;
}

class _EditorStateSnapshot {
  const _EditorStateSnapshot({
    required this.audioPath,
    required this.soundName,
    required this.audioOffsetMs,
    required this.explicitDurationMs,
    required this.loop,
    required this.background,
  });

  final String? audioPath;
  final String? soundName;
  final double audioOffsetMs;
  final double? explicitDurationMs;
  final bool loop;
  final String? background;

  bool sameAs(_EditorStateSnapshot other) =>
      audioPath == other.audioPath &&
      soundName == other.soundName &&
      (audioOffsetMs - other.audioOffsetMs).abs() < 0.001 &&
      explicitDurationMs == other.explicitDurationMs &&
      loop == other.loop &&
      background == other.background;
}

class AudioMarksScreen extends StatefulWidget {
  const AudioMarksScreen({super.key});

  @override
  State<AudioMarksScreen> createState() => _AudioMarksScreenState();
}

class _AudioMarksScreenState extends State<AudioMarksScreen>
    with TickerProviderStateMixin {
  // controllers/services
  late final PlaybackController playback;
  late final PlaybackController optionalBlockPlayback;
  late final AnimationClock animationClock;
  late final MarksController marksCtrl;
  final LabelImageService imgSvc = LabelImageService();
  final LanguageAnimWorkspaceService _languageWorkspaceService =
      const LanguageAnimWorkspaceService();
  final LanguageAnimSessionStore _languageSessionStore =
      const LanguageAnimSessionStore();
  final AnimakerLabelConfig _labelConfig = AnimakerLabelConfig();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  LanguageAnimWorkspace? _languageWorkspace;
  String? _selectedCharacterId;
  String? _selectedAnimationName;
  String? _selectedSoundName;
  String? _animationBackground;
  Map<String, String> _backgroundCandidatesByName = {};

  // history (for undo-redo)
  late final HistoryController history;

  String? _playbackPath; // чем реально играет плеер (WAV либо исходник)
  Directory?
  _playTmpDir; // временная папка с конвертом (удаляем при смене файла)

  // ui state
  final FocusNode _screenFocus = FocusNode(
    debugLabel: 'screenHotkeys',
    skipTraversal: true,
  );
  final _timelineKey = GlobalKey<ZoomableTimelineState>();

  String? currentAudioPath;
  double _playbackRate = 1.0;
  bool _loopEnabled = false;
  double _animationDurationMs = 1000;
  double? _explicitDurationMs = 1000;
  double _audioOffsetMs = 0;
  double _audioDurationMs = 0;
  double _lastClockPositionMs = 0;
  bool _audioSyncBusy = false;
  bool _optionalAudioSyncBusy = false;
  String? _activeOptionalAudioGroupId;
  String? _activeOptionalAudioPath;
  StreamSubscription<Duration>? _clockPositionSubscription;
  StreamSubscription<bool>? _clockPlayingSubscription;
  List<double>? _peaks;
  final Map<String, double> _optionalAudioDurationByPath = {};
  final Map<String, List<double>> _optionalAudioPeaksByPath = {};
  final Map<String, Future<void>> _optionalAudioPeakLoads = {};
  FrameClipboardData _frameClipboard = const FrameClipboardData([]);
  String? _pendingScrollId;
  late final AppLifecycleListener _appLifecycleListener;
  _EditorStateSnapshot? _timelineGestureBefore;
  List<ClipMark>? _timelineGestureMarksBefore;
  Set<String>? _timelineGestureSelectionBefore;
  List<ClipMark>? _blockAudioGestureBefore;
  Set<String>? _blockAudioGestureSelection;

  bool get hasPlaybackTimeline => _animationDurationMs > 0;

  AthmCharacter? get _selectedCharacter =>
      _languageWorkspace?.document.characterById(_selectedCharacterId ?? '');

  AthmAnimation? get _selectedAnimation {
    final wanted = _selectedAnimationName?.toUpperCase();
    if (wanted == null) return null;
    for (final animation in _selectedCharacter?.animations ?? const []) {
      if (animation.name.toUpperCase() == wanted) return animation;
    }
    return null;
  }

  List<ClipMark> get _selectedMarks => marksCtrl.marks.value
      .where((mark) => marksCtrl.selection.value.contains(mark.id))
      .toList();

  bool get _allSelectedMarksLocked =>
      _selectedMarks.isNotEmpty &&
      _selectedMarks.every((mark) => mark.lockedSequenceId != null);

  bool get _allSelectedMarksOptional =>
      _allSelectedMarksLocked &&
      _selectedMarks.every((mark) => mark.optionalChancePercent != null);

  double? get _selectedOptionalChance {
    if (!_allSelectedMarksOptional) return null;
    final chance = _selectedMarks.first.optionalChancePercent!;
    return _selectedMarks.every((mark) => mark.optionalChancePercent == chance)
        ? chance
        : null;
  }

  bool get _selectedOptionalIncludedInPreview =>
      _allSelectedMarksOptional &&
      _selectedMarks.every((mark) => mark.optionalIncludedInPreview);

  String? get _selectedOptionalGroupId {
    final groups = _selectedOptionalGroupIds();
    return groups.length == 1 ? groups.single : null;
  }

  ClipMark? get _selectedOptionalGroupFirstMark {
    final groupId = _selectedOptionalGroupId;
    if (groupId == null) return null;
    final group =
        marksCtrl.marks.value
            .where((mark) => mark.lockedSequenceId == groupId)
            .toList()
          ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return group.isEmpty ? null : group.first;
  }

  String _optionalAudioCacheKey(String path) => p.normalize(path).toLowerCase();

  List<TimelineBlockAudioClip> get _timelineBlockAudioClips {
    final marks = marksCtrl.marks.value;
    final result = <TimelineBlockAudioClip>[];
    var index = 0;
    while (index < marks.length) {
      final first = marks[index];
      final groupId = first.lockedSequenceId;
      if (groupId == null || first.optionalSoundPath == null) {
        index++;
        continue;
      }
      var endIndex = index;
      while (endIndex + 1 < marks.length &&
          marks[endIndex + 1].lockedSequenceId == groupId) {
        endIndex++;
      }
      final path = first.optionalSoundPath!;
      final audioDurationMs =
          _optionalAudioDurationByPath[_optionalAudioCacheKey(path)] ?? 0;
      if (audioDurationMs > 0) {
        final blockEndMs = endIndex + 1 < marks.length
            ? marks[endIndex + 1].startMs
            : marks[endIndex].startMs + (marks[endIndex].durationMs ?? 100.0);
        result.add(
          TimelineBlockAudioClip(
            groupId: groupId,
            label: first.optionalSoundName ?? p.basename(path),
            blockStartMs: first.startMs,
            blockEndMs: blockEndMs,
            audioDurationMs: audioDurationMs,
            offsetMs: first.optionalSoundOffsetMs,
            includedInPreview: first.optionalIncludedInPreview,
            peaks: _optionalAudioPeaksByPath[_optionalAudioCacheKey(path)],
          ),
        );
      }
      index = endIndex + 1;
    }
    return result;
  }

  AthmAnimation? get _editorAnimation {
    final selected = _selectedAnimation;
    if (selected == null) return null;
    return selected.copyWith(
      track: _trackFromMarks(),
      loop: _loopEnabled,
      durationMs: _explicitDurationMs,
      clearDuration: _explicitDurationMs == null,
      soundOffsetMs: _audioOffsetMs,
      sound: _selectedSoundName,
      clearSound: _selectedSoundName == null,
      background: _animationBackground,
      clearBackground: _animationBackground == null,
    );
  }

  String? get _effectiveBackgroundName {
    if (_animationBackground?.toLowerCase() == AthmAnimation.noBackground) {
      return null;
    }
    return _animationBackground ?? _selectedCharacter?.background;
  }

  String? get _effectiveBackgroundPath {
    final name = _effectiveBackgroundName?.trim();
    if (name == null || name.isEmpty) return null;
    final requested = _backgroundCandidatesByName[name.toUpperCase()];
    if (requested != null) return requested;
    if (_animationBackground != null) {
      final inherited = _selectedCharacter?.background?.trim();
      if (inherited != null && inherited.isNotEmpty) {
        return _backgroundCandidatesByName[inherited.toUpperCase()];
      }
    }
    return null;
  }

  bool get _isRequestedBackgroundMissing {
    final name = _effectiveBackgroundName?.trim();
    return name != null &&
        name.isNotEmpty &&
        !_backgroundCandidatesByName.containsKey(name.toUpperCase());
  }

  String get _backgroundControlLabel {
    if (_animationBackground == null) return 'BACKGROUND: INHERIT';
    if (_animationBackground?.toLowerCase() == AthmAnimation.noBackground) {
      return 'BACKGROUND: NONE';
    }
    return 'BACKGROUND: $_animationBackground';
  }

  bool get _hasUnsavedAnimation {
    final original = _selectedAnimation;
    final edited = _editorAnimation;
    if (original == null || edited == null) return false;
    final codec = _languageWorkspaceService.codec;
    return codec.encodeTrack(original.track) !=
            codec.encodeTrack(edited.track) ||
        original.loop != edited.loop ||
        original.sound != edited.sound ||
        original.background != edited.background ||
        original.durationMs != edited.durationMs ||
        (original.soundOffsetMs - edited.soundOffsetMs).abs() > 0.001;
  }

  late final KeymapController keymapCtrl;
  final _hotkeysFocus = FocusNode(debugLabel: 'hotkeys', skipTraversal: true);

  void _refocusHotkeys() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hotkeysFocus.hasFocus && !isEditableTextFocused()) {
        FocusScope.of(context).requestFocus(_hotkeysFocus);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    playback = PlaybackController();
    optionalBlockPlayback = PlaybackController();
    animationClock = AnimationClock(
      vsync: this,
      durationMs: _animationDurationMs,
    );
    _clockPositionSubscription = animationClock.positionStream.listen(
      _onClockPosition,
    );
    _clockPlayingSubscription = animationClock.playingStream.listen((_) {
      _syncAudioToClock(forceSeek: true);
      _syncOptionalBlockAudio(forceSeek: true);
    });
    history = HistoryController(
      apply: (m, s) {
        marksCtrl.marks.value = List<ClipMark>.from(m);
        marksCtrl.selection.value = Set<String>.from(s);
        _refreshTimelineDurationFromMarks();
      },
    );

    marksCtrl = MarksController(
      history: history,
      getDurationMs: () => _animationDurationMs,
    );
    marksCtrl.selection.addListener(_selectionChanged);
    keymapCtrl = KeymapController()..load(); // <- загрузим сохранённые биндинги
    marksCtrl.marks.addListener(_marksChanged);
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreLastLanguageAnimSession());
    });

    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) _screenFocus.requestFocus();
    // });
  }

  @override
  void dispose() {
    marksCtrl.selection.removeListener(_selectionChanged);
    marksCtrl.marks.removeListener(_marksChanged);
    _labelEditorKeyById.clear();

    playback.dispose();
    optionalBlockPlayback.dispose();
    _clockPositionSubscription?.cancel();
    _clockPlayingSubscription?.cancel();
    animationClock.dispose();
    _screenFocus.dispose();
    _appLifecycleListener.dispose();
    super.dispose();
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _marksChanged() {
    _disposeMissingLabelFoci();
    if (mounted) setState(() {});
  }

  Future<AppExitResponse> _onExitRequested() async {
    return await _confirmSaveCurrentAnimation()
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  void _refreshTimelineDurationFromMarks() {
    _animationDurationMs = effectiveTimelineDurationMs(
      selectedTrackEndMs: selectedTrackEndMs(marksCtrl.marks.value),
      explicitMinimumMs: _explicitDurationMs,
      audioEndMs: currentAudioPath == null
          ? 0
          : _audioOffsetMs + _audioDurationMs,
    );
    animationClock.setDurationMs(_animationDurationMs);
  }

  _EditorStateSnapshot _captureEditorState() => _EditorStateSnapshot(
    audioPath: currentAudioPath,
    soundName: _selectedSoundName,
    audioOffsetMs: _audioOffsetMs,
    explicitDurationMs: _explicitDurationMs,
    loop: _loopEnabled,
    background: _animationBackground,
  );

  void _recordEditorState(
    _EditorStateSnapshot before, {
    required String label,
  }) {
    final after = _captureEditorState();
    if (before.sameAs(after)) return;
    history.recordAction(
      marks: marksCtrl.marks.value,
      selection: marksCtrl.selection.value,
      undo: () => _applyEditorState(before),
      redo: () => _applyEditorState(after),
      label: label,
    );
  }

  void _beginTimelineEditorChange() {
    _timelineGestureBefore ??= _captureEditorState();
    _timelineGestureMarksBefore ??= List<ClipMark>.from(marksCtrl.marks.value);
    _timelineGestureSelectionBefore ??= Set<String>.from(
      marksCtrl.selection.value,
    );
  }

  void _endTimelineEditorChange(String label) {
    final before = _timelineGestureBefore;
    final beforeMarks = _timelineGestureMarksBefore;
    final beforeSelection = _timelineGestureSelectionBefore;
    _timelineGestureBefore = null;
    _timelineGestureMarksBefore = null;
    _timelineGestureSelectionBefore = null;
    if (before == null || beforeMarks == null || beforeSelection == null) {
      return;
    }
    final after = _captureEditorState();
    final afterMarks = List<ClipMark>.from(marksCtrl.marks.value);
    final afterSelection = Set<String>.from(marksCtrl.selection.value);
    if (before.sameAs(after) && listEquals(beforeMarks, afterMarks)) return;
    history.record(
      beforeMarks: beforeMarks,
      beforeSel: beforeSelection,
      afterMarks: afterMarks,
      afterSel: afterSelection,
      undoAction: before.sameAs(after) ? null : () => _applyEditorState(before),
      redoAction: before.sameAs(after) ? null : () => _applyEditorState(after),
      label: label,
    );
  }

  Future<void> _applyEditorState(_EditorStateSnapshot state) async {
    final audioChanged = currentAudioPath != state.audioPath;

    if (audioChanged) {
      animationClock.pause();
      await playback.raw.stop();
      await _cleanupPlayTmp();
      currentAudioPath = state.audioPath;
      _playbackPath = null;
      _peaks = null;
      _audioDurationMs = 0;

      final source = state.audioPath;
      if (source != null && await File(source).exists()) {
        if (p.extension(source).toLowerCase() == '.wav') {
          _playbackPath = source;
        } else {
          _playTmpDir = await Directory.systemTemp.createTemp('am2_wav_');
          _playbackPath = await ensureWavForPlayback(
            source,
            outDir: _playTmpDir,
          );
        }
        await playback.openPath(_playbackPath!);
        await playback.setLooping(false);
        _audioDurationMs = await _resolveLoadedAudioDurationMs();
        try {
          _peaks = await computePeaksFromWavFile(_playbackPath!, buckets: 1200);
        } catch (_) {
          _peaks = null;
        }
      }
    }

    _selectedSoundName = state.soundName;
    _audioOffsetMs = state.audioOffsetMs;
    _explicitDurationMs = state.explicitDurationMs;
    _loopEnabled = state.loop;
    _animationBackground = state.background;
    _animationDurationMs = effectiveTimelineDurationMs(
      selectedTrackEndMs: selectedTrackEndMs(marksCtrl.marks.value),
      explicitMinimumMs: _explicitDurationMs,
      audioEndMs: currentAudioPath == null
          ? 0
          : _audioOffsetMs + _audioDurationMs,
    );
    animationClock.setDurationMs(_animationDurationMs);
    animationClock.setLooping(_loopEnabled);
    if (animationClock.position.inMilliseconds > _animationDurationMs) {
      animationClock.seekMs(_animationDurationMs);
    }
    if (mounted) setState(() {});
  }

  void _copySelectedFrames() {
    final copied = copySelectedFrames(
      marksCtrl.marks.value,
      marksCtrl.selection.value,
    );
    if (copied.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select frames to copy.')));
      return;
    }
    _frameClipboard = copied;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${copied.frames.length} frame(s).')),
    );
  }

  void _cutSelectedFrames() {
    final copied = copySelectedFrames(
      marksCtrl.marks.value,
      marksCtrl.selection.value,
    );
    if (copied.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select frames to cut.')));
      return;
    }
    _frameClipboard = copied;
    marksCtrl.removeSelected();
    _refreshTimelineDurationFromMarks();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cut ${copied.frames.length} frame(s).')),
    );
  }

  Future<void> _pasteCopiedFrames() async {
    if (_frameClipboard.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The frame clipboard is empty.')),
      );
      return;
    }
    animationClock.pause();
    final beforeMarks = List<ClipMark>.from(marksCtrl.marks.value);
    final beforeSelection = Set<String>.from(marksCtrl.selection.value);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var lockSequence = 0;
    final result = pasteFramesAtPlayhead(
      source: beforeMarks,
      clipboard: _frameClipboard,
      playheadMs: animationClock.position.inMilliseconds.toDouble(),
      idFactory: genId,
      lockIdFactory: () => 'paste_${stamp}_${lockSequence++}',
    );
    history.record(
      beforeMarks: beforeMarks,
      beforeSel: beforeSelection,
      afterMarks: result.marks,
      afterSel: result.selectedIds,
      label: 'paste frames',
    );
    marksCtrl.marks.value = result.marks;
    marksCtrl.selection.value = result.selectedIds;
    _refreshTimelineDurationFromMarks();
    await _seekAnimation(result.insertionMs);
    if (result.selectedIds.isNotEmpty) {
      final firstId = result.selectedIds.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToMarkId(firstId);
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pasted ${result.selectedIds.length} frame(s) at '
          '${result.insertionMs.toStringAsFixed(0)} ms.',
        ),
      ),
    );
  }

  Future<void> _cleanupPlayTmp() async {
    final dir = _playTmpDir;
    _playTmpDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _setAnimationDuration(double value) {
    final audioEnd = currentAudioPath == null
        ? 0.0
        : _audioOffsetMs + _audioDurationMs;
    final source = _timelineGestureMarksBefore ?? marksCtrl.marks.value;
    final resized = resizeTimelineEnd(
      source: source,
      requestedDurationMs: value,
      audioEndMs: audioEnd,
    );
    if (!listEquals(marksCtrl.marks.value, resized.marks)) {
      marksCtrl.marks.value = resized.marks;
    }
    _explicitDurationMs = resized.durationMs;
    _animationDurationMs = resized.durationMs;
    animationClock.setDurationMs(_animationDurationMs);
    if (mounted) setState(() {});
  }

  void _setAudioOffset(double value) {
    final maximum = math.max(0, _animationDurationMs - _audioDurationMs);
    _audioOffsetMs = value.clamp(0, maximum).toDouble();
    _syncAudioToClock(forceSeek: true);
    if (mounted) setState(() {});
  }

  void _beginBlockAudioOffsetChange(String groupId) {
    _blockAudioGestureBefore ??= List<ClipMark>.from(marksCtrl.marks.value);
    _blockAudioGestureSelection ??= Set<String>.from(marksCtrl.selection.value);
  }

  void _setBlockAudioOffset(String groupId, double value) {
    marksCtrl.marks.value = marksCtrl.marks.value
        .map(
          (mark) => mark.lockedSequenceId == groupId
              ? mark.copyWith(optionalSoundOffsetMs: value)
              : mark,
        )
        .toList();
    _syncOptionalBlockAudio(forceSeek: true);
  }

  void _endBlockAudioOffsetChange(String groupId) {
    final before = _blockAudioGestureBefore;
    final beforeSelection = _blockAudioGestureSelection;
    _blockAudioGestureBefore = null;
    _blockAudioGestureSelection = null;
    if (before == null || beforeSelection == null) return;
    final after = List<ClipMark>.from(marksCtrl.marks.value);
    if (listEquals(before, after)) return;
    history.record(
      beforeMarks: before,
      beforeSel: beforeSelection,
      afterMarks: after,
      afterSel: Set<String>.from(marksCtrl.selection.value),
      label: 'move block audio',
    );
  }

  void _onClockPosition(Duration position) {
    final positionMs = position.inMilliseconds.toDouble();
    final wrapped = positionMs + 1 < _lastClockPositionMs;
    _lastClockPositionMs = positionMs;
    _syncAudioToClock(forceSeek: wrapped);
    _syncOptionalBlockAudio(forceSeek: wrapped);
  }

  List<_OptionalAudioCue> _optionalAudioCues() {
    final marks = List<ClipMark>.from(marksCtrl.marks.value)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final result = <_OptionalAudioCue>[];
    var skippedMs = 0.0;
    var index = 0;
    while (index < marks.length) {
      final first = marks[index];
      if (first.optionalChancePercent == null ||
          first.lockedSequenceId == null) {
        index++;
        continue;
      }
      final groupId = first.lockedSequenceId!;
      final groupStart = first.startMs;
      var groupEnd = first.startMs + (first.durationMs ?? 100);
      var next = index + 1;
      while (next < marks.length && marks[next].lockedSequenceId == groupId) {
        groupEnd = math.max(
          groupEnd,
          marks[next].startMs + (marks[next].durationMs ?? 100),
        );
        next++;
      }
      if (!first.optionalIncludedInPreview) {
        skippedMs += groupEnd - groupStart;
      } else if (first.optionalSoundPath case final path?) {
        result.add(
          _OptionalAudioCue(
            groupId: groupId,
            path: path,
            startMs: groupStart - skippedMs + first.optionalSoundOffsetMs,
          ),
        );
      }
      index = next;
    }
    return result;
  }

  Future<double> _loadOptionalAudioDurationMs(String path) async {
    final key = _optionalAudioCacheKey(path);
    final peaksLoad = _ensureOptionalAudioPeaks(path);
    final cached = _optionalAudioDurationByPath[key];
    if (cached != null) {
      await peaksLoad;
      return cached;
    }
    if (!await File(path).exists()) {
      await peaksLoad;
      return 0;
    }

    final probe = PlaybackController();
    try {
      await probe.openPath(path);
      final duration = await probe.waitForDuration();
      final durationMs = duration.inMilliseconds.toDouble();
      if (durationMs > 0) _optionalAudioDurationByPath[key] = durationMs;
      await peaksLoad;
      return durationMs;
    } finally {
      await probe.dispose();
    }
  }

  Future<void> _ensureOptionalAudioPeaks(String path) {
    final key = _optionalAudioCacheKey(path);
    final cached = _optionalAudioPeaksByPath[key];
    if (cached != null && cached.isNotEmpty) {
      return Future<void>.value();
    }
    final active = _optionalAudioPeakLoads[key];
    if (active != null) return active;

    final load = _loadOptionalAudioPeaks(path, key);
    _optionalAudioPeakLoads[key] = load;
    return load.whenComplete(() {
      if (identical(_optionalAudioPeakLoads[key], load)) {
        _optionalAudioPeakLoads.remove(key);
      }
    });
  }

  Future<void> _loadOptionalAudioPeaks(String path, String key) async {
    Directory? temporaryDirectory;
    try {
      if (!await File(path).exists()) {
        _optionalAudioPeaksByPath.remove(key);
        return;
      }

      var wavPath = path;
      if (p.extension(path).toLowerCase() != '.wav') {
        temporaryDirectory = await Directory.systemTemp.createTemp(
          'am2_block_wav_',
        );
        wavPath = await ensureWavForPlayback(path, outDir: temporaryDirectory);
      }
      _optionalAudioPeaksByPath[key] =
          await computePeaksFromWavFile(wavPath, buckets: 800) ?? const [];
    } catch (_) {
      _optionalAudioPeaksByPath.remove(key);
    } finally {
      if (temporaryDirectory != null) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }
  }

  Future<List<ClipMark>> _fitLoadedOptionalAudio(List<ClipMark> source) async {
    var result = List<ClipMark>.from(source);
    final groups = <String, String>{};
    for (final mark in result) {
      final groupId = mark.lockedSequenceId;
      final path = mark.optionalSoundPath;
      if (groupId != null && path != null) groups[groupId] = path;
    }
    for (final entry in groups.entries) {
      final durationMs = await _loadOptionalAudioDurationMs(entry.value);
      if (durationMs <= 0) continue;
      result = fitOptionalAudioGroup(
        marks: result,
        groupId: entry.key,
        audioDurationMs: durationMs,
      ).marks;
    }
    return result;
  }

  List<ClipMark> _fitKnownOptionalAudio(List<ClipMark> source) {
    var result = List<ClipMark>.from(source);
    final groups = <String, String>{};
    for (final mark in result) {
      final groupId = mark.lockedSequenceId;
      final path = mark.optionalSoundPath;
      if (groupId != null && path != null) groups[groupId] = path;
    }
    for (final entry in groups.entries) {
      final durationMs =
          _optionalAudioDurationByPath[_optionalAudioCacheKey(entry.value)] ??
          0;
      if (durationMs <= 0) continue;
      result = fitOptionalAudioGroup(
        marks: result,
        groupId: entry.key,
        audioDurationMs: durationMs,
      ).marks;
    }
    return result;
  }

  void _ensureKnownOptionalAudioFits() {
    final before = marksCtrl.marks.value;
    final fitted = _fitKnownOptionalAudio(before);
    if (!listEquals(before, fitted)) {
      marksCtrl.marks.value = fitted;
      _refreshTimelineDurationFromMarks();
    }
  }

  Future<void> _syncOptionalBlockAudio({bool forceSeek = false}) async {
    if (_optionalAudioSyncBusy) return;
    _optionalAudioSyncBusy = true;
    try {
      final clockMs = animationClock.position.inMilliseconds.toDouble();
      _OptionalAudioCue? cue;
      for (final candidate in _optionalAudioCues()) {
        if (candidate.startMs <= clockMs) cue = candidate;
      }
      if (!animationClock.playing || cue == null) {
        if (optionalBlockPlayback.playing) await optionalBlockPlayback.pause();
        return;
      }

      final changed =
          _activeOptionalAudioGroupId != cue.groupId ||
          _activeOptionalAudioPath != cue.path;
      if (changed) {
        if (!await File(cue.path).exists()) {
          _activeOptionalAudioGroupId = cue.groupId;
          _activeOptionalAudioPath = null;
          return;
        }
        await optionalBlockPlayback.openPath(cue.path);
        await optionalBlockPlayback.setRate(_playbackRate);
        _activeOptionalAudioGroupId = cue.groupId;
        _activeOptionalAudioPath = cue.path;
        forceSeek = true;
      }
      final localMs = clockMs - cue.startMs;
      final durationMs = (await optionalBlockPlayback.waitForDuration())
          .inMilliseconds
          .toDouble();
      if (localMs < 0 || (durationMs > 0 && localMs >= durationMs)) {
        if (optionalBlockPlayback.playing) await optionalBlockPlayback.pause();
        return;
      }
      final drift = optionalBlockPlayback.position.inMilliseconds - localMs;
      if (forceSeek || !optionalBlockPlayback.playing || drift.abs() > 80) {
        await optionalBlockPlayback.seekMs(localMs);
      }
      if (!optionalBlockPlayback.playing) await optionalBlockPlayback.play();
    } finally {
      _optionalAudioSyncBusy = false;
    }
  }

  Future<void> _syncAudioToClock({bool forceSeek = false}) async {
    if (_audioSyncBusy || currentAudioPath == null || _playbackPath == null) {
      return;
    }
    _audioSyncBusy = true;
    try {
      final localMs =
          animationClock.position.inMilliseconds.toDouble() - _audioOffsetMs;
      final insideAudio = localMs >= 0 && localMs < _audioDurationMs;
      if (!animationClock.playing || !insideAudio) {
        if (playback.playing) await playback.pause();
        return;
      }

      final drift = playback.position.inMilliseconds.toDouble() - localMs;
      if (forceSeek || !playback.playing || drift.abs() > 80) {
        await playback.seekMs(localMs);
      }
      if (!playback.playing) await playback.play();
    } finally {
      _audioSyncBusy = false;
    }
  }

  Future<void> _seekAnimation(double ms) async {
    animationClock.seekMs(ms);
    await _syncAudioToClock(forceSeek: true);
    await _syncOptionalBlockAudio(forceSeek: true);
  }

  Future<void> _toggleAnimationPlayback() async {
    animationClock.playOrPause();
    await _syncAudioToClock(forceSeek: true);
    await _syncOptionalBlockAudio(forceSeek: true);
  }

  void _onRandomPassDuration(double passDurationMs) {
    final audioEnd = currentAudioPath == null
        ? 0.0
        : _audioOffsetMs + _audioDurationMs;
    final effective = effectiveTimelineDurationMs(
      selectedTrackEndMs: passDurationMs,
      explicitMinimumMs: _explicitDurationMs,
      audioEndMs: audioEnd,
    );
    _animationDurationMs = effective;
    animationClock.setDurationMs(effective);
    if (mounted) setState(() {});
  }

  Future<double> _resolveLoadedAudioDurationMs() async {
    final path = _playbackPath;
    if (!kIsWeb && path != null && p.extension(path).toLowerCase() == '.wav') {
      try {
        final duration = await readWavDurationMs(path);
        if (duration > 0) return duration;
      } catch (_) {}
    }
    return (await playback.waitForDuration()).inMilliseconds.toDouble();
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
    );
    if (result == null) return;
    final file = result.files.single;
    final before = _captureEditorState();

    await playback.raw.stop();
    await optionalBlockPlayback.raw.stop();
    _activeOptionalAudioGroupId = null;
    _activeOptionalAudioPath = null;
    animationClock.pause();
    await _cleanupPlayTmp();

    var source = file.path; // оригинал для проекта
    final workspace = _languageWorkspace;
    final character = _selectedCharacter;
    if (source != null && workspace != null && character != null) {
      final soundsDirectory = Directory(
        _languageWorkspaceService.soundsRootPath(workspace.rootPath),
      );
      await soundsDirectory.create(recursive: true);
      final destination = p.join(soundsDirectory.path, p.basename(source));
      if (p.normalize(source).toLowerCase() !=
          p.normalize(destination).toLowerCase()) {
        await File(source).copy(destination);
        source = destination;
      }
    }
    currentAudioPath = source;
    _peaks = null;
    _audioDurationMs = 0;
    setState(() {});

    // где будем играть
    String playPath;
    if (kIsWeb || source == null) {
      // (твоя старая веб-ветка остаётся как была)
      playPath = file.name;
    } else {
      if (p.extension(source).toLowerCase() == '.wav') {
        playPath = source;
      } else {
        // конвертируем в WAV
        final tmpDir = await Directory.systemTemp.createTemp('am2_wav_');
        _playTmpDir = tmpDir;
        playPath = await ensureWavForPlayback(source, outDir: tmpDir);
      }
    }

    _playbackPath = playPath;
    await playback.openPath(playPath);
    await playback.setLooping(false);
    _audioDurationMs = await _resolveLoadedAudioDurationMs();
    _animationDurationMs = math.max(
      _animationDurationMs,
      _audioOffsetMs + _audioDurationMs,
    );
    animationClock.setDurationMs(_animationDurationMs);
    if (source != null && _selectedAnimation != null) {
      _selectedSoundName = p.basenameWithoutExtension(source);
    }

    // пики считаем ВСЕГДА из WAV (если web — как раньше по bytes)
    try {
      const buckets = 1200;
      if (kIsWeb && file.bytes != null) {
        final ext = (file.extension ?? '').toLowerCase();
        if (ext == 'wav') {
          _peaks = await computePeaksFromWavBytes(
            file.bytes!,
            buckets: buckets,
          );
        } else {
          // (если надо — можно не строить пики на web для не-wav)
          _peaks = null;
        }
      } else if (_playbackPath != null &&
          p.extension(_playbackPath!).toLowerCase() == '.wav') {
        _peaks = await computePeaksFromWavFile(
          _playbackPath!,
          buckets: buckets,
        );
      }
    } catch (_) {
      _peaks = null;
    }
    _recordEditorState(before, label: 'replace audio');
    if (mounted) setState(() {});
  }

  Future<void> _removeAudio() async {
    if (currentAudioPath == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Are you sure?'),
            content: Text(
              'Remove ${p.basename(currentAudioPath!)} from this animation? '
              'The audio file will remain on disk.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove audio'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final before = _captureEditorState();
    animationClock.pause();
    await playback.raw.stop();
    await _cleanupPlayTmp();
    currentAudioPath = null;
    _playbackPath = null;
    _peaks = null;
    _audioDurationMs = 0;
    _audioOffsetMs = 0;
    _selectedSoundName = null;
    _animationDurationMs = effectiveTimelineDurationMs(
      selectedTrackEndMs: selectedTrackEndMs(marksCtrl.marks.value),
      explicitMinimumMs: _explicitDurationMs,
    );
    animationClock.setDurationMs(_animationDurationMs);
    _recordEditorState(before, label: 'remove audio');
    if (mounted) setState(() {});
  }

  Future<String?> _showIdentifierDialog({
    required String title,
    required String label,
    String initialValue = '',
    Set<String> unavailable = const {},
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: label,
              helperText: 'A-Z, 0-9 and underscore',
              errorText: error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final value = controller.text.trim().toUpperCase();
              if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(value)) {
                setDialogState(() => error = 'Invalid identifier');
              } else if (unavailable.contains(value)) {
                setDialogState(() => error = 'Identifier already exists');
              } else {
                Navigator.pop(context, value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim().toUpperCase();
                if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(value)) {
                  setDialogState(() => error = 'Invalid identifier');
                } else if (unavailable.contains(value)) {
                  setDialogState(() => error = 'Identifier already exists');
                } else {
                  Navigator.pop(context, value);
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirmSaveCurrentAnimation() async {
    if (!_hasUnsavedAnimation) return true;
    final animationName = _selectedAnimationName ?? 'animation';
    final choice = await showDialog<_UnsavedAnimationChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Save changes in $animationName?'),
        content: const Text(
          'Only the currently open animation has unsaved changes.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedAnimationChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedAnimationChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedAnimationChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    switch (choice) {
      case _UnsavedAnimationChoice.save:
        return _saveLanguageAnim();
      case _UnsavedAnimationChoice.discard:
        final character = _selectedCharacter;
        final animation = _selectedAnimation;
        if (character != null && animation != null) {
          await _loadWorkspaceAnimation(
            character,
            animation,
            force: true,
            guardUnsaved: false,
          );
        }
        return true;
      case _UnsavedAnimationChoice.cancel:
      case null:
        return false;
    }
  }

  Future<String?> _chooseLanguageAnimSavePath() async {
    final location = await getSaveLocation(
      suggestedName: 'LANGUAGE_ANIM.txt',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'LANGUAGE_ANIM', extensions: ['txt']),
      ],
    );
    if (location == null) return null;
    return p.extension(location.path).toLowerCase() == '.txt'
        ? location.path
        : '${location.path}.txt';
  }

  Future<void> _newLanguageAnim() async {
    final path = await _chooseLanguageAnimSavePath();
    if (path == null || !mounted) return;
    final id = await _showIdentifierDialog(
      title: 'Create first character',
      label: 'Character ID',
    );
    if (id == null || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    try {
      final workspace = await _languageWorkspaceService.create(path, id);
      if (!mounted) return;
      setState(() {
        _languageWorkspace = workspace;
        _selectedCharacterId = null;
        _selectedAnimationName = null;
      });
      final character = workspace.document.characters.first;
      await _loadWorkspaceAnimation(character, character.animations.first);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created ${p.basename(path)}.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot create LANGUAGE_ANIM: $error')),
      );
    }
  }

  Future<void> _saveLanguageAnimAs() async {
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    _ensureKnownOptionalAudioFits();
    final path = await _chooseLanguageAnimSavePath();
    if (path == null) return;
    final previousDocument = workspace.document;
    final edited = _editorAnimation;
    if (edited != null) {
      workspace.document = _documentReplacingCurrentAnimation(edited);
    }
    try {
      final saved = await _languageWorkspaceService.saveAs(workspace, path);
      final labelWarning = await _saveCurrentFrameLabels();
      if (!mounted) return;
      setState(() => _languageWorkspace = saved);
      await _rememberCurrentLanguageAnimSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved as $path${labelWarning ?? ''}')),
      );
    } catch (error) {
      workspace.document = previousDocument;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot save LANGUAGE_ANIM as: $error')),
      );
    }
  }

  LanguageAnimDocument _documentReplacingCurrentAnimation(
    AthmAnimation replacement,
  ) {
    final workspace = _languageWorkspace!;
    final characterId = _selectedCharacterId!.toUpperCase();
    final animationName = _selectedAnimationName!.toUpperCase();
    return workspace.document.copyWith(
      characters: workspace.document.characters.map((character) {
        if (character.id.toUpperCase() != characterId) return character;
        return character.copyWith(
          animations: character.animations.map((animation) {
            return animation.name.toUpperCase() == animationName
                ? replacement
                : animation;
          }).toList(),
        );
      }).toList(),
    );
  }

  Future<bool> _saveStructuralDocument(LanguageAnimDocument document) async {
    final workspace = _languageWorkspace;
    if (workspace == null) return false;
    final previous = workspace.document;
    workspace.document = document;
    try {
      await _languageWorkspaceService.save(workspace);
      final reopened = await _languageWorkspaceService.open(
        workspace.languageFilePath,
      );
      if (!mounted) return false;
      setState(() => _languageWorkspace = reopened);
      return true;
    } catch (error) {
      workspace.document = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot update LANGUAGE_ANIM: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _addCharacter() async {
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    final existing = workspace.document.characters
        .map((character) => character.id.toUpperCase())
        .toSet();
    final id = await _showIdentifierDialog(
      title: 'Add character',
      label: 'Character ID',
      unavailable: existing,
    );
    if (id == null || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final character = AthmCharacter(
      id: id,
      animations: [_languageWorkspaceService.defaultIdleAnimation(id)],
    );
    final updated = workspace.document.copyWith(
      characters: [...workspace.document.characters, character],
    );
    if (!await _saveStructuralDocument(updated)) return;
    final created = _languageWorkspace!.document.characterById(id)!;
    await _loadWorkspaceAnimation(created, created.animations.first);
  }

  Future<void> _addAnimation([AthmCharacter? targetCharacter]) async {
    final workspace = _languageWorkspace;
    final character = targetCharacter ?? _selectedCharacter;
    if (workspace == null || character == null) return;
    final existing = character.animations
        .map((animation) => animation.name.toUpperCase())
        .toSet();
    final name = await _showIdentifierDialog(
      title: 'Add animation to ${character.id}',
      label: 'Animation name',
      unavailable: existing,
    );
    if (name == null || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final created = _languageWorkspaceService.defaultAnimation(
      character.id,
      name,
    );
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters.map((item) {
        return item.id.toUpperCase() == character.id.toUpperCase()
            ? item.copyWith(animations: [...item.animations, created])
            : item;
      }).toList(),
    );
    if (!await _saveStructuralDocument(updated)) return;
    final reopenedCharacter = _languageWorkspace!.document.characterById(
      character.id,
    )!;
    final reopenedAnimation = reopenedCharacter.animations.firstWhere(
      (animation) => animation.name.toUpperCase() == name,
    );
    await _loadWorkspaceAnimation(reopenedCharacter, reopenedAnimation);
  }

  Future<void> _setCharacterBackground(AthmCharacter character) async {
    final initialWorkspace = _languageWorkspace;
    if (initialWorkspace == null || character.animations.isEmpty) return;
    final assets = initialWorkspace.statusFor(
      character.id,
      character.animations.first.name,
    );
    final candidates = {
      for (final entry in assets.backgroundCandidatesByName.entries)
        entry.key.toUpperCase(): entry.value,
    };
    final selection = await showDialog<AnimationBackgroundSelection>(
      context: context,
      builder: (context) => AnimationBackgroundDialog(
        title: '${character.id} character background',
        allowInherit: false,
        candidatesByName: candidates,
        currentValue: character.background,
      ),
    );
    if (selection == null || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;

    String? background;
    switch (selection.type) {
      case AnimationBackgroundSelectionType.inherit:
      case AnimationBackgroundSelectionType.setCharacter:
      case AnimationBackgroundSelectionType.none:
        background = null;
        break;
      case AnimationBackgroundSelectionType.custom:
        background = selection.name;
        break;
      case AnimationBackgroundSelectionType.import:
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Import character background',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        );
        final sourcePath = result?.files.single.path;
        if (sourcePath == null) return;
        try {
          final importedPath = await _languageWorkspaceService.importBackground(
            _languageWorkspace!,
            character.id,
            sourcePath,
          );
          background = p.basenameWithoutExtension(importedPath).toUpperCase();
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot import background: $error')),
          );
          return;
        }
        break;
    }

    final workspace = _languageWorkspace!;
    final selectedAnimationName = _selectedAnimationName;
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters.map((item) {
        return item.id.toUpperCase() == character.id.toUpperCase()
            ? item.copyWith(
                background: background,
                clearBackground: background == null,
              )
            : item;
      }).toList(),
    );
    if (!await _saveStructuralDocument(updated)) return;

    if (_selectedCharacterId?.toUpperCase() == character.id.toUpperCase() &&
        selectedAnimationName != null) {
      final reopenedCharacter = _languageWorkspace!.document.characterById(
        character.id,
      )!;
      final reopenedAnimation = reopenedCharacter.animations.firstWhere(
        (animation) =>
            animation.name.toUpperCase() == selectedAnimationName.toUpperCase(),
      );
      await _loadWorkspaceAnimation(
        reopenedCharacter,
        reopenedAnimation,
        force: true,
        guardUnsaved: false,
      );
    }
  }

  Future<bool> _confirmDelete(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _renameCharacter(AthmCharacter character) async {
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    final unavailable = workspace.document.characters
        .where((item) => item.id.toUpperCase() != character.id.toUpperCase())
        .map((item) => item.id.toUpperCase())
        .toSet();
    final id = await _showIdentifierDialog(
      title: 'Rename ${character.id}',
      label: 'Character ID',
      initialValue: character.id,
      unavailable: unavailable,
    );
    if (id == null || id == character.id || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters.map((item) {
        final renamed = item.id.toUpperCase() == character.id.toUpperCase()
            ? item.copyWith(id: id)
            : item;
        return renamed.variantOf?.toUpperCase() == character.id.toUpperCase()
            ? renamed.copyWith(variantOf: id)
            : renamed;
      }).toList(),
    );
    try {
      await _languageWorkspaceService.renameCharacterAssets(
        workspace,
        character.id,
        id,
      );
      if (!await _saveStructuralDocument(updated)) {
        await _languageWorkspaceService.renameCharacterAssets(
          workspace,
          id,
          character.id,
        );
        return;
      }
      try {
        await _labelConfig.renameCharacter(character.id, id);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Character renamed; label config: $error')),
          );
        }
      }
      if (_selectedCharacterId?.toUpperCase() == character.id.toUpperCase()) {
        _selectedCharacterId = id;
        final renamedCharacter = _languageWorkspace!.document.characterById(
          id,
        )!;
        final animation = renamedCharacter.animations.firstWhere(
          (item) =>
              item.name.toUpperCase() == _selectedAnimationName?.toUpperCase(),
          orElse: () => renamedCharacter.animations.first,
        );
        await _loadWorkspaceAnimation(renamedCharacter, animation);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot rename character: $error')),
      );
    }
  }

  Future<void> _deleteCharacter(AthmCharacter character) async {
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    if (workspace.document.characters.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A project must contain a character.')),
      );
      return;
    }
    final dependent = workspace.document.characters.where(
      (item) => item.variantOf?.toUpperCase() == character.id.toUpperCase(),
    );
    if (dependent.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete: used by ${dependent.map((e) => e.id).join(', ')}.',
          ),
        ),
      );
      return;
    }
    final confirmed = await _confirmDelete(
      'Delete ${character.id}?',
      'The character is removed from LANGUAGE_ANIM. Its media folder is kept.',
    );
    if (!confirmed || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final deletingSelected =
        _selectedCharacterId?.toUpperCase() == character.id.toUpperCase();
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters
          .where((item) => item.id.toUpperCase() != character.id.toUpperCase())
          .toList(),
    );
    if (!await _saveStructuralDocument(updated)) return;
    if (deletingSelected) {
      final next = _languageWorkspace!.document.characters.first;
      await _loadWorkspaceAnimation(next, next.animations.first);
    }
  }

  Future<void> _renameAnimation(
    AthmCharacter character,
    AthmAnimation animation,
  ) async {
    if (animation.name.toUpperCase() == 'IDLE') return;
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    final unavailable = character.animations
        .where(
          (item) => item.name.toUpperCase() != animation.name.toUpperCase(),
        )
        .map((item) => item.name.toUpperCase())
        .toSet();
    final name = await _showIdentifierDialog(
      title: 'Rename ${animation.name}',
      label: 'Animation name',
      initialValue: animation.name,
      unavailable: unavailable,
    );
    if (name == null || name == animation.name || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters.map((item) {
        if (item.id.toUpperCase() != character.id.toUpperCase()) return item;
        return item.copyWith(
          animations: item.animations.map((candidate) {
            return candidate.name.toUpperCase() == animation.name.toUpperCase()
                ? candidate.copyWith(name: name)
                : candidate;
          }).toList(),
        );
      }).toList(),
    );
    if (!await _saveStructuralDocument(updated)) return;
    final renamedCharacter = _languageWorkspace!.document.characterById(
      character.id,
    )!;
    if (_selectedCharacterId?.toUpperCase() == character.id.toUpperCase() &&
        _selectedAnimationName?.toUpperCase() == animation.name.toUpperCase()) {
      final renamedAnimation = renamedCharacter.animations.firstWhere(
        (item) => item.name.toUpperCase() == name,
      );
      await _loadWorkspaceAnimation(renamedCharacter, renamedAnimation);
    }
  }

  Future<void> _deleteAnimation(
    AthmCharacter character,
    AthmAnimation animation,
  ) async {
    if (animation.name.toUpperCase() == 'IDLE') return;
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    final confirmed = await _confirmDelete(
      'Delete ${animation.name}?',
      'The animation is removed from ${character.id}. Media files are kept.',
    );
    if (!confirmed || !mounted) return;
    if (!await _confirmSaveCurrentAnimation()) return;
    final deletingSelected =
        _selectedCharacterId?.toUpperCase() == character.id.toUpperCase() &&
        _selectedAnimationName?.toUpperCase() == animation.name.toUpperCase();
    final updated = workspace.document.copyWith(
      characters: workspace.document.characters.map((item) {
        if (item.id.toUpperCase() != character.id.toUpperCase()) return item;
        return item.copyWith(
          animations: item.animations
              .where(
                (candidate) =>
                    candidate.name.toUpperCase() !=
                    animation.name.toUpperCase(),
              )
              .toList(),
        );
      }).toList(),
    );
    if (!await _saveStructuralDocument(updated)) return;
    if (deletingSelected) {
      final reopenedCharacter = _languageWorkspace!.document.characterById(
        character.id,
      )!;
      final idle = reopenedCharacter.animations.firstWhere(
        (item) => item.name.toUpperCase() == 'IDLE',
      );
      await _loadWorkspaceAnimation(reopenedCharacter, idle);
    }
  }

  Future<void> _openLanguageAnim() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open LANGUAGE_ANIM.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!await _confirmSaveCurrentAnimation()) return;

    try {
      final workspace = await _languageWorkspaceService.open(path);
      if (!mounted) return;
      setState(() {
        _languageWorkspace = workspace;
        _selectedCharacterId = null;
        _selectedAnimationName = null;
      });
      final character = workspace.document.characters.first;
      final animation = _initialAnimationFor(character);
      await _loadWorkspaceAnimation(character, animation);
      if (!mounted) return;
      final migrated = workspace.document.wasMigratedFromLegacy
          ? ' Legacy format loaded and will be saved as ATHM v4.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded ${p.basename(path)}.$migrated')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open LANGUAGE_ANIM: $error')),
      );
    }
  }

  AthmAnimation _initialAnimationFor(AthmCharacter character) =>
      character.animations.firstWhere(
        (animation) => animation.name.toUpperCase() == 'IDLE',
        orElse: () => character.animations.first,
      );

  Future<void> _rememberCurrentLanguageAnimSession() async {
    final workspace = _languageWorkspace;
    final characterId = _selectedCharacterId;
    final animationName = _selectedAnimationName;
    if (workspace == null || characterId == null || animationName == null) {
      return;
    }
    await _languageSessionStore.save(
      languageFilePath: workspace.languageFilePath,
      characterId: characterId,
      animationName: animationName,
    );
  }

  Future<void> _restoreLastLanguageAnimSession() async {
    final session = await _languageSessionStore.load();
    if (session == null || !mounted || _languageWorkspace != null) return;
    if (!await File(session.languageFilePath).exists()) {
      await _languageSessionStore.clear();
      return;
    }

    try {
      final workspace = await _languageWorkspaceService.open(
        session.languageFilePath,
      );
      if (!mounted || _languageWorkspace != null) return;
      setState(() {
        _languageWorkspace = workspace;
        _selectedCharacterId = null;
        _selectedAnimationName = null;
      });

      final selection = resolveLanguageAnimSessionSelection(
        workspace.document,
        session,
      );
      await _loadWorkspaceAnimation(
        selection.character,
        selection.animation,
        force: true,
        guardUnsaved: false,
      );
    } catch (error) {
      await _languageSessionStore.clear();
      if (!mounted || _languageWorkspace != null) return;
      setState(() {
        _languageWorkspace = null;
        _selectedCharacterId = null;
        _selectedAnimationName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot restore the last project: $error')),
      );
    }
  }

  Future<void> _chooseAnimationBackground() async {
    final workspace = _languageWorkspace;
    final character = _selectedCharacter;
    if (workspace == null || character == null) return;
    final selection = await showDialog<AnimationBackgroundSelection>(
      context: context,
      builder: (context) => AnimationBackgroundDialog(
        candidatesByName: _backgroundCandidatesByName,
        currentValue: _animationBackground,
        inheritedName: character.background,
      ),
    );
    if (selection == null || !mounted) return;

    String? next;
    switch (selection.type) {
      case AnimationBackgroundSelectionType.inherit:
        next = null;
        break;
      case AnimationBackgroundSelectionType.setCharacter:
        await _setCharacterBackground(character);
        return;
      case AnimationBackgroundSelectionType.none:
        next = AthmAnimation.noBackground;
        break;
      case AnimationBackgroundSelectionType.custom:
        next = selection.name;
        break;
      case AnimationBackgroundSelectionType.import:
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Import animation background',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        );
        final sourcePath = result?.files.single.path;
        if (sourcePath == null) return;
        try {
          final importedPath = await _languageWorkspaceService.importBackground(
            workspace,
            character.id,
            sourcePath,
          );
          next = p.basenameWithoutExtension(importedPath).toUpperCase();
          _backgroundCandidatesByName = {
            ..._backgroundCandidatesByName,
            next: importedPath,
          };
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot import background: $error')),
          );
          return;
        }
        break;
    }

    final before = _captureEditorState();
    setState(() => _animationBackground = next);
    _recordEditorState(before, label: 'change animation background');
  }

  Future<void> _loadWorkspaceAnimation(
    AthmCharacter character,
    AthmAnimation animation, {
    bool force = false,
    bool guardUnsaved = true,
    bool closeLibrary = true,
  }) async {
    final workspace = _languageWorkspace;
    if (workspace == null) return;
    final alreadySelected =
        _selectedCharacterId?.toUpperCase() == character.id.toUpperCase() &&
        _selectedAnimationName?.toUpperCase() == animation.name.toUpperCase();
    if (alreadySelected && !force) {
      if (closeLibrary) _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (guardUnsaved && !await _confirmSaveCurrentAnimation()) return;
    final assets = workspace.statusFor(character.id, animation.name);
    final savedLabels = await _labelConfig.loadForCharacter(character.id);

    await playback.raw.stop();
    await optionalBlockPlayback.raw.stop();
    _activeOptionalAudioGroupId = null;
    _activeOptionalAudioPath = null;
    animationClock.pause();
    await _cleanupPlayTmp();
    currentAudioPath = assets.audioPath;
    _playbackPath = null;
    _peaks = null;
    _audioDurationMs = 0;
    _audioOffsetMs = animation.soundOffsetMs;
    _explicitDurationMs = animation.durationMs;
    _selectedSoundName = animation.sound;
    _animationBackground = animation.background;
    _backgroundCandidatesByName = {
      for (final entry in assets.backgroundCandidatesByName.entries)
        entry.key.toUpperCase(): entry.value,
    };

    final framePathsByName = {
      for (final entry in assets.framesByName.entries)
        entry.key.toUpperCase(): entry.value,
    };
    final editorImages = Map<String, String>.from(assets.framesByName);
    for (final entry in savedLabels.entries) {
      final imagePath = framePathsByName[entry.key.toUpperCase()];
      if (imagePath != null) editorImages[entry.value] = imagePath;
    }
    imgSvc.setAll(editorImages);
    if (assets.framesByName.isNotEmpty) {
      imgSvc.defaultImage = assets.framesByName.values.first;
    }

    var marks = <ClipMark>[];
    var startMs = 0.0;
    var lockNumber = 0;
    for (final entry in animation.track) {
      final locked =
          entry is AthmLockedSequence || entry is AthmOptionalLockedSequence;
      final lockedId = locked ? 'locked_${++lockNumber}' : null;
      final optionalChance = entry is AthmOptionalLockedSequence
          ? entry.chancePercent
          : null;
      final optionalSoundName = entry is AthmOptionalLockedSequence
          ? entry.sound
          : null;
      final optionalSoundOffsetMs = entry is AthmOptionalLockedSequence
          ? entry.soundOffsetMs
          : 0.0;
      final optionalSoundKey = optionalSoundName == null
          ? null
          : p
                .basenameWithoutExtension(
                  optionalSoundName.replaceAll('\\', '/'),
                )
                .toUpperCase();
      final optionalSoundPath = optionalSoundKey == null
          ? null
          : assets.soundsByName[optionalSoundKey];
      for (final segment in entry.segments) {
        final layoutDuration = segment.durationChoicesMs.first;
        marks.add(
          ClipMark(
            startMs: startMs,
            durationMs: layoutDuration,
            label:
                savedLabels[segment.previewFrame.trim().toUpperCase()] ??
                segment.previewFrame,
            frameChoices: segment.frameChoices
                .map(
                  (frame) => savedLabels[frame.trim().toUpperCase()] ?? frame,
                )
                .toList(),
            durationChoicesMs: List<double>.from(segment.durationChoicesMs),
            selectedFrameChoiceIndex: 0,
            selectedDurationChoiceIndex: 0,
            lockedSequenceId: lockedId,
            optionalChancePercent: optionalChance,
            optionalIncludedInPreview: true,
            optionalSoundName: optionalSoundName,
            optionalSoundPath: optionalSoundPath,
            optionalSoundOffsetMs: optionalSoundOffsetMs,
          ),
        );
        startMs += layoutDuration;
      }
    }
    marks = await _fitLoadedOptionalAudio(marks);
    startMs = selectedTrackEndMs(marks);
    _animationDurationMs = effectiveTimelineDurationMs(
      selectedTrackEndMs: startMs,
      explicitMinimumMs: _explicitDurationMs,
    );
    marksCtrl.setMarksSorted(marks);
    history.clear();

    if (assets.audioPath != null) {
      final source = assets.audioPath!;
      if (p.extension(source).toLowerCase() == '.wav') {
        _playbackPath = source;
      } else {
        _playTmpDir = await Directory.systemTemp.createTemp('am2_wav_');
        _playbackPath = await ensureWavForPlayback(source, outDir: _playTmpDir);
      }
      await playback.openPath(_playbackPath!);
      _audioDurationMs = await _resolveLoadedAudioDurationMs();
      _animationDurationMs = math.max(
        _animationDurationMs,
        _audioOffsetMs + _audioDurationMs,
      );
      try {
        _peaks = await computePeaksFromWavFile(_playbackPath!, buckets: 1200);
      } catch (_) {
        _peaks = null;
      }
    }
    await playback.setLooping(false);
    animationClock.setDurationMs(_animationDurationMs);
    animationClock.setLooping(animation.loop);
    animationClock.seekMs(0);

    if (!mounted) return;
    setState(() {
      _selectedCharacterId = character.id;
      _selectedAnimationName = animation.name;
      _loopEnabled = animation.loop;
    });
    unawaited(_rememberCurrentLanguageAnimSession());
    if (closeLibrary) _scaffoldKey.currentState?.closeDrawer();
    if (!assets.isComplete) {
      final details = [
        if (assets.expectsAudio && !assets.hasAudio) 'sound not found',
        if (assets.missingFrames.isNotEmpty)
          '${assets.missingFrames.length} frame(s) not found',
        if (assets.missingOptionalSounds.isNotEmpty)
          '${assets.missingOptionalSounds.length} block sound(s) not found; animation will still play',
        if (assets.missingBackground != null)
          'background ${assets.missingBackground} not found; animation will still play',
      ].join(', ');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Animation loaded; $details.')));
    }
  }

  String _savedFrameName(String editorLabel) {
    final imagePath = imgSvc.imageForLabelNullable(editorLabel);
    if (imagePath == null ||
        imagePath.isEmpty ||
        imagePath.startsWith('data:image/')) {
      return editorLabel;
    }
    final imageName = p.basenameWithoutExtension(imagePath).trim();
    return imageName.isEmpty ? editorLabel : imageName;
  }

  List<AthmTrackEntry> _trackFromMarks() => buildAthmTrackFromMarks(
    marksCtrl.marks.value,
    resolveFrameName: _savedFrameName,
  );

  Map<String, String> _currentFrameLabels() {
    final result = <String, String>{};
    for (final mark in marksCtrl.marks.value) {
      final choices = List<String>.from(
        mark.frameChoices ?? [mark.label ?? 'FRAME'],
      );
      if (choices.isEmpty) choices.add(mark.label ?? 'FRAME');
      if (choices.length == 1 && (mark.label?.trim().isNotEmpty ?? false)) {
        choices[0] = mark.label!.trim();
      }
      for (final label in choices) {
        final trimmed = label.trim();
        if (trimmed.isEmpty) continue;
        result[_savedFrameName(trimmed).toUpperCase()] = trimmed;
      }
    }
    return result;
  }

  Future<String?> _saveCurrentFrameLabels() async {
    final characterId = _selectedCharacterId;
    if (characterId == null) return null;
    try {
      await _labelConfig.updateCharacter(characterId, _currentFrameLabels());
      return null;
    } catch (error) {
      return ' Labels were not saved: $error';
    }
  }

  Future<bool> _saveLanguageAnim() async {
    final workspace = _languageWorkspace;
    _ensureKnownOptionalAudioFits();
    final updatedAnimation = _editorAnimation;
    if (workspace == null || updatedAnimation == null) return false;
    final previousDocument = workspace.document;
    workspace.document = _documentReplacingCurrentAnimation(updatedAnimation);

    try {
      await _languageWorkspaceService.save(workspace);
      final labelWarning = await _saveCurrentFrameLabels();
      _languageWorkspace = await _languageWorkspaceService.open(
        workspace.languageFilePath,
      );
      if (!mounted) return true;
      final refreshedAssets = _languageWorkspace!.statusFor(
        _selectedCharacterId!,
        _selectedAnimationName!,
      );
      _backgroundCandidatesByName = {
        for (final entry in refreshedAssets.backgroundCandidatesByName.entries)
          entry.key.toUpperCase(): entry.value,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ATHM v4. Backup: '
            '${p.basename(workspace.languageFilePath)}.bak'
            '${labelWarning ?? ''}',
          ),
        ),
      );
      setState(() {});
      return true;
    } catch (error) {
      workspace.document = previousDocument;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot save LANGUAGE_ANIM: $error')),
        );
      }
      return false;
    }
  }

  void _toggleSelectedLocked() {
    final selected = marksCtrl.selection.value;
    if (selected.isEmpty) return;
    final selectedMarks = marksCtrl.marks.value
        .where((mark) => selected.contains(mark.id))
        .toList();
    if (selectedMarks.isEmpty) {
      marksCtrl.clearSelection();
      return;
    }
    final unlock = selectedMarks.every((mark) => mark.lockedSequenceId != null);
    _setMarksLocked(selected, !unlock, historyLabel: 'toggle unskippable');
  }

  void _toggleMarkLocked(ClipMark mark) {
    final ids = mark.optionalChancePercent == null
        ? {mark.id}
        : marksCtrl.marks.value
              .where((item) => item.lockedSequenceId == mark.lockedSequenceId)
              .map((item) => item.id)
              .toSet();
    _setMarksLocked(
      ids,
      mark.lockedSequenceId == null,
      historyLabel: 'toggle frame unskippable',
    );
  }

  void _setMarksLocked(
    Set<String> ids,
    bool locked, {
    required String historyLabel,
  }) {
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final beforeSelection = Set<String>.from(marksCtrl.selection.value);
    final lockId = 'locked_${DateTime.now().microsecondsSinceEpoch}';
    final next = before.map((mark) {
      if (!ids.contains(mark.id)) return mark;
      return mark.copyWith(
        lockedSequenceId: locked ? lockId : null,
        clearLockedSequenceId: !locked,
        clearOptionalChancePercent: true,
        optionalIncludedInPreview: true,
        clearOptionalSoundName: !locked,
        clearOptionalSoundPath: !locked,
        optionalSoundOffsetMs: locked ? mark.optionalSoundOffsetMs : 0,
      );
    }).toList();
    history.record(
      beforeMarks: before,
      beforeSel: beforeSelection,
      afterMarks: next,
      afterSel: beforeSelection,
      label: historyLabel,
    );
    marksCtrl.marks.value = next;
  }

  Set<String> _selectedOptionalGroupIds() => _selectedMarks
      .where((mark) => mark.optionalChancePercent != null)
      .map((mark) => mark.lockedSequenceId)
      .whereType<String>()
      .toSet();

  Set<String> _optionalGroupTargetMarkIds() {
    final groups = _selectedOptionalGroupIds();
    if (groups.isEmpty) return marksCtrl.selection.value;
    return marksCtrl.marks.value
        .where((mark) => groups.contains(mark.lockedSequenceId))
        .map((mark) => mark.id)
        .toSet();
  }

  Future<double?> _askOptionalChance(double initial) async {
    final controller = TextEditingController(
      text: initial.toStringAsFixed(initial == initial.roundToDouble() ? 0 : 1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Random unskippable sequence'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Chance per loop (%)',
            helperText: 'Enter a value greater than 0 and up to 100.',
          ),
          onSubmitted: (_) {
            final value = double.tryParse(controller.text.trim());
            if (value != null && value > 0 && value <= 100) {
              Navigator.of(dialogContext).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value != null && value > 0 && value <= 100) {
                Navigator.of(dialogContext).pop(value);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _enableSelectedOptional() async {
    if (!_allSelectedMarksLocked) return;
    final selection = Set<String>.from(marksCtrl.selection.value);
    final hasGuaranteedFrameAfter = marksCtrl.marks.value.any(
      (mark) =>
          !selection.contains(mark.id) && mark.optionalChancePercent == null,
    );
    if (!hasGuaranteedFrameAfter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep at least one frame outside random sequences.'),
        ),
      );
      return;
    }
    final chance = await _askOptionalChance(_selectedOptionalChance ?? 50);
    if (chance == null || !mounted) return;
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final groupId = 'optional_${DateTime.now().microsecondsSinceEpoch}';
    final next = before.map((mark) {
      if (!selection.contains(mark.id)) return mark;
      return mark.copyWith(
        lockedSequenceId: groupId,
        optionalChancePercent: chance,
        optionalIncludedInPreview: true,
      );
    }).toList();
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'make unskippable sequence random',
    );
    marksCtrl.marks.value = next;
  }

  void _disableSelectedOptional() {
    final targets = _optionalGroupTargetMarkIds();
    if (targets.isEmpty) return;
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final selection = Set<String>.from(marksCtrl.selection.value);
    final next = before.map((mark) {
      if (!targets.contains(mark.id)) return mark;
      return mark.copyWith(
        clearOptionalChancePercent: true,
        optionalIncludedInPreview: true,
        clearOptionalSoundName: true,
        clearOptionalSoundPath: true,
        optionalSoundOffsetMs: 0,
      );
    }).toList();
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'make unskippable sequence deterministic',
    );
    marksCtrl.marks.value = next;
  }

  Future<void> _editSelectedOptionalChance() async {
    final current = _selectedOptionalChance;
    if (current == null) return;
    final chance = await _askOptionalChance(current);
    if (chance == null || !mounted || chance == current) return;
    final targets = _optionalGroupTargetMarkIds();
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final selection = Set<String>.from(marksCtrl.selection.value);
    final next = before
        .map(
          (mark) => targets.contains(mark.id)
              ? mark.copyWith(optionalChancePercent: chance)
              : mark,
        )
        .toList();
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'change random sequence chance',
    );
    marksCtrl.marks.value = next;
  }

  void _setSelectedOptionalPreview(bool included) {
    final targets = _optionalGroupTargetMarkIds();
    if (targets.isEmpty) return;
    marksCtrl.marks.value = marksCtrl.marks.value
        .map(
          (mark) => targets.contains(mark.id)
              ? mark.copyWith(optionalIncludedInPreview: included)
              : mark,
        )
        .toList();
    setState(() {});
  }

  Future<void> _pickOptionalBlockAudio() async {
    final groupId = _selectedOptionalGroupId;
    final workspace = _languageWorkspace;
    if (groupId == null || workspace == null) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose random block audio',
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
    );
    var source = result?.files.single.path;
    if (source == null) return;
    final soundsDirectory = Directory(
      _languageWorkspaceService.soundsRootPath(workspace.rootPath),
    );
    await soundsDirectory.create(recursive: true);
    final safeBaseName = p
        .basenameWithoutExtension(source)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final destination = p.join(
      soundsDirectory.path,
      '$safeBaseName${p.extension(source).toLowerCase()}',
    );
    if (p.normalize(source).toLowerCase() !=
        p.normalize(destination).toLowerCase()) {
      await File(source).copy(destination);
      source = destination;
    }
    final cacheKey = _optionalAudioCacheKey(source);
    _optionalAudioDurationByPath.remove(cacheKey);
    _optionalAudioPeaksByPath.remove(cacheKey);

    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final selection = Set<String>.from(marksCtrl.selection.value);
    final soundName = safeBaseName;
    var next = before
        .map(
          (mark) => mark.lockedSequenceId == groupId
              ? mark.copyWith(
                  optionalSoundName: soundName,
                  optionalSoundPath: source,
                )
              : mark,
        )
        .toList();
    final audioDurationMs = await _loadOptionalAudioDurationMs(source);
    if (audioDurationMs > 0) {
      next = fitOptionalAudioGroup(
        marks: next,
        groupId: groupId,
        audioDurationMs: audioDurationMs,
      ).marks;
    }
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'attach random block audio',
    );
    marksCtrl.marks.value = next;
    _refreshTimelineDurationFromMarks();
    _activeOptionalAudioGroupId = null;
    _activeOptionalAudioPath = null;
    await _syncOptionalBlockAudio(forceSeek: true);
  }

  Future<void> _removeOptionalBlockAudio() async {
    final groupId = _selectedOptionalGroupId;
    final current = _selectedOptionalGroupFirstMark;
    if (groupId == null || current?.optionalSoundName == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Are you sure?'),
            content: Text(
              'Remove ${current!.optionalSoundName} from this random block? '
              'The audio file will remain on disk.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove audio'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final selection = Set<String>.from(marksCtrl.selection.value);
    final next = before
        .map(
          (mark) => mark.lockedSequenceId == groupId
              ? mark.copyWith(
                  clearOptionalSoundName: true,
                  clearOptionalSoundPath: true,
                  optionalSoundOffsetMs: 0,
                )
              : mark,
        )
        .toList();
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'remove random block audio',
    );
    marksCtrl.marks.value = next;
    await optionalBlockPlayback.raw.stop();
    _activeOptionalAudioGroupId = null;
    _activeOptionalAudioPath = null;
  }

  Future<void> _editOptionalBlockAudioOffset() async {
    final groupId = _selectedOptionalGroupId;
    final current = _selectedOptionalGroupFirstMark;
    if (groupId == null || current?.optionalSoundName == null) return;
    final controller = TextEditingController(
      text: current!.optionalSoundOffsetMs.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block audio offset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Start after block begins (ms)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed != null && parsed.isFinite && parsed >= 0) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted || value == current.optionalSoundOffsetMs) {
      return;
    }
    final before = List<ClipMark>.from(marksCtrl.marks.value);
    final selection = Set<String>.from(marksCtrl.selection.value);
    var next = before
        .map(
          (mark) => mark.lockedSequenceId == groupId
              ? mark.copyWith(optionalSoundOffsetMs: value)
              : mark,
        )
        .toList();
    final path = current.optionalSoundPath;
    if (path != null) {
      final durationMs = await _loadOptionalAudioDurationMs(path);
      if (durationMs > 0) {
        next = fitOptionalAudioGroup(
          marks: next,
          groupId: groupId,
          audioDurationMs: durationMs,
        ).marks;
      }
    }
    history.record(
      beforeMarks: before,
      beforeSel: selection,
      afterMarks: next,
      afterSel: selection,
      label: 'change random block audio offset',
    );
    marksCtrl.marks.value = next;
    _refreshTimelineDurationFromMarks();
    await _syncOptionalBlockAudio(forceSeek: true);
  }

  Future<void> _editStepVariants(int markIndex, ClipMark mark) async {
    final frames = List<String>.from(
      mark.frameChoices ?? [mark.label ?? 'FRAME'],
    );
    if (frames.isEmpty) frames.add(mark.label ?? 'FRAME');
    final durations = List<double>.from(
      mark.durationChoicesMs ?? [mark.durationMs ?? 100],
    );
    if (durations.isEmpty) durations.add(mark.durationMs ?? 100);

    final result = await showDialog<StepVariantsResult>(
      context: context,
      builder: (context) => StepVariantsDialog(
        frames: frames,
        durationsMs: durations,
        selectedFrameIndex: mark.selectedFrameChoiceIndex,
        selectedDurationIndex: mark.selectedDurationChoiceIndex,
      ),
    );
    if (result == null || !mounted) return;

    final beforeMarks = List<ClipMark>.from(marksCtrl.marks.value);
    final beforeSelection = Set<String>.from(marksCtrl.selection.value);
    final next = <ClipMark>[];
    var cursor = 0.0;
    for (var index = 0; index < beforeMarks.length; index++) {
      final current = beforeMarks[index];
      final isEdited = index == markIndex;
      final nextFrames = isEdited
          ? result.frames
          : List<String>.from(
              current.frameChoices ?? [current.label ?? 'FRAME'],
            );
      final nextDurations = isEdited
          ? result.durationsMs
          : List<double>.from(
              current.durationChoicesMs ?? [current.durationMs ?? 100],
            );
      final frameChoice =
          (isEdited
                  ? result.selectedFrameIndex
                  : current.selectedFrameChoiceIndex)
              .clamp(0, nextFrames.length - 1);
      final durationChoice =
          (isEdited
                  ? result.selectedDurationIndex
                  : current.selectedDurationChoiceIndex)
              .clamp(0, nextDurations.length - 1);
      final selectedDuration = nextDurations[durationChoice];
      next.add(
        current.copyWith(
          startMs: cursor,
          durationMs: selectedDuration,
          label: nextFrames[frameChoice],
          frameChoices: nextFrames,
          durationChoicesMs: nextDurations,
          selectedFrameChoiceIndex: frameChoice,
          selectedDurationChoiceIndex: durationChoice,
        ),
      );
      cursor += selectedDuration;
    }
    final fitted = _fitKnownOptionalAudio(next);
    cursor = selectedTrackEndMs(fitted);

    final selection = Set<String>.from(marksCtrl.selection.value);
    history.record(
      beforeMarks: beforeMarks,
      beforeSel: beforeSelection,
      afterMarks: fitted,
      afterSel: selection,
      label: 'edit step variants',
    );
    marksCtrl.marks.value = fitted;
    _animationDurationMs = effectiveTimelineDurationMs(
      selectedTrackEndMs: cursor,
      explicitMinimumMs: _explicitDurationMs,
      audioEndMs: currentAudioPath == null
          ? 0
          : _audioOffsetMs + _audioDurationMs,
    );
    animationClock.setDurationMs(_animationDurationMs);
    setState(() {});
  }

  String _stepDescription(ClipMark mark) {
    final parts = <String>['starts at: ${mark.startMs.toStringAsFixed(0)} ms'];
    final durationChoices = mark.durationChoicesMs;
    if (durationChoices != null && durationChoices.length > 1) {
      final selectedIndex = mark.selectedDurationChoiceIndex.clamp(
        0,
        durationChoices.length - 1,
      );
      parts.add(
        'duration variants: ${durationChoices.length} '
        '(current: ${durationChoices[selectedIndex].toStringAsFixed(0)} ms)',
      );
    } else {
      parts.add('duration: ${(mark.durationMs ?? 0).toStringAsFixed(0)} ms');
    }

    final frameChoices = mark.frameChoices;
    if (frameChoices != null && frameChoices.length > 1) {
      final selectedIndex = mark.selectedFrameChoiceIndex.clamp(
        0,
        frameChoices.length - 1,
      );
      parts.add(
        'frame variants: ${frameChoices.length} '
        '(current: ${frameChoices[selectedIndex]})',
      );
    }
    if (mark.optionalChancePercent != null) {
      parts.add(
        'random unskippable: '
        '${mark.optionalChancePercent!.toStringAsFixed(0)}% '
        '(preview: ${mark.optionalIncludedInPreview ? 'included' : 'skipped'})',
      );
    }
    return parts.join(', ');
  }

  // ---------- Selection helpers / scroll ----------
  int _listIndexForMarkIndex(int markIndex) => markIndex * 2;

  Future<void> _scrollToMarkId(String id, {bool alsoFocus = false}) async {
    final markIndex = marksCtrl.marks.value.indexWhere((m) => m.id == id);
    if (markIndex < 0) return;

    await WidgetsBinding
        .instance
        .endOfFrame; // на всякий случай, чтобы список уже отрисовался

    if (!_itemScrollCtrl.isAttached) return;

    final listLen = marksCtrl.marks.value.length;
    if (listLen == 0) return;

    final target = _listIndexForMarkIndex(markIndex);
    final itemCount = listLen * 2 - 1;
    if (target < 0 || target >= itemCount) return;

    try {
      await _itemScrollCtrl.scrollTo(
        index: target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    } catch (_) {
      // повтор через кадр, как и было
      await Future<void>.delayed(const Duration(milliseconds: 0));
      if (_itemScrollCtrl.isAttached) {
        final mi2 = marksCtrl.marks.value.indexWhere((m) => m.id == id);
        if (mi2 >= 0) {
          final target2 = _listIndexForMarkIndex(mi2);
          await _itemScrollCtrl.scrollTo(
            index: target2,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
        }
      }
    }

    if (alsoFocus) {
      // ждём появления элемента среди видимых и только потом фокусим
      final targetIndex = _listIndexForMarkIndex(
        marksCtrl.marks.value.indexWhere((m) => m.id == id),
      );
      bool visible() =>
          _itemPositions.itemPositions.value.any((p) => p.index == targetIndex);

      if (!visible()) {
        final c = Completer<void>();
        void listener() {
          if (visible()) {
            _itemPositions.itemPositions.removeListener(listener);
            if (!c.isCompleted) c.complete();
          }
        }

        _itemPositions.itemPositions.addListener(listener);
        // защитный таймаут, чтобы не зависать
        await c.future.timeout(
          const Duration(milliseconds: 400),
          onTimeout: () {},
        );
      }

      // и ещё один кадр — чтобы TextField «прикрутился» к дереву
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestLabelFocus(id);
      });
    }
  }

  // Future<void> _scrollToMarkId(String id) async {
  //   final markIndex = marksCtrl.marks.value.indexWhere((m) => m.id == id);
  //   if (markIndex < 0) return;

  //   WidgetsBinding.instance.addPostFrameCallback((_) async {
  //     if (!_itemScrollCtrl.isAttached) return;
  //     final listLen = marksCtrl.marks.value.length;
  //     if (listLen == 0) return;

  //     final target = _listIndexForMarkIndex(markIndex);
  //     final itemCount = listLen * 2 - 1;
  //     if (target < 0 || target >= itemCount) return;

  //     try {
  //       await _itemScrollCtrl.scrollTo(
  //         index: target,
  //         duration: const Duration(milliseconds: 250),
  //         curve: Curves.easeInOut,
  //         alignment: 0.2,
  //       );
  //     } catch (_) {
  //       WidgetsBinding.instance.addPostFrameCallback((__) async {
  //         if (!_itemScrollCtrl.isAttached) return;
  //         final listLen2 = marksCtrl.marks.value.length;
  //         final itemCount2 = listLen2 * 2 - 1;
  //         final mi2 = marksCtrl.marks.value.indexWhere((m) => m.id == id);
  //         if (mi2 < 0) return;
  //         final target2 = _listIndexForMarkIndex(mi2);
  //         if (target2 < 0 || target2 >= itemCount2) return;
  //         await _itemScrollCtrl.scrollTo(
  //           index: target2,
  //           duration: const Duration(milliseconds: 200),
  //           curve: Curves.easeInOut,
  //           alignment: 0.2,
  //         );
  //       });
  //     }
  //   });
  // }

  // Future<void> _selectAndMaybeSeek(
  //   String id, {
  //   bool seek = true,
  //   bool scrollList = true,
  //   bool forceSeek = true,
  // }) async {
  //   final changed =
  //       !marksCtrl.selection.value.contains(id) ||
  //       marksCtrl.selection.value.length != 1;
  //   if (changed) {
  //     marksCtrl.selectOnly(id);
  //   }
  //   if (seek && (changed || forceSeek)) {
  //     final m = marksCtrl.marks.value.firstWhere(
  //       (e) => e.id == id,
  //       orElse: () => marksCtrl.marks.value.first,
  //     );
  //     await playback.seekMs(m.startMs);
  //   }
  //   if (scrollList) {
  //     _pendingScrollId = id;
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       final toScroll = _pendingScrollId;
  //       _pendingScrollId = null;
  //       if (toScroll != null) {
  //         _scrollToMarkId(toScroll);
  //       }
  //     });
  //   }
  // }

  Future<void> _selectAndMaybeSeek(
    String id, {
    bool seek = true,
    bool scrollList = true,
    bool forceSeek = true,
    bool focusLabelEditor = false, // NEW
  }) async {
    final changed =
        !marksCtrl.selection.value.contains(id) ||
        marksCtrl.selection.value.length != 1;
    if (changed) {
      marksCtrl.selectOnly(id);
    }
    if (seek && (changed || forceSeek)) {
      final m = marksCtrl.marks.value.firstWhere(
        (e) => e.id == id,
        orElse: () => marksCtrl.marks.value.first,
      );
      await _seekAnimation(m.startMs);
    }
    if (scrollList) {
      final wantFocus = focusLabelEditor; // захватим в замыкание
      _pendingScrollId = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final toScroll = _pendingScrollId;
        _pendingScrollId = null;
        if (toScroll != null) {
          _scrollToMarkId(toScroll, alsoFocus: wantFocus);
        }
      });
    } else if (focusLabelEditor) {
      // если скролл не нужен — просто сфокусируем
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestLabelFocus(id);
      });
    }
  }

  bool _applySelectionModifier(String id) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) {
      marksCtrl.toggleSelection(id);
      return true;
    }
    if (keyboard.isShiftPressed) {
      marksCtrl.selectRangeTo(id);
      return true;
    }
    return false;
  }

  Future<void> _activateTimelineMark(String id) async {
    if (_applySelectionModifier(id)) return;
    await _selectAndMaybeSeek(
      id,
      seek: true,
      scrollList: true,
      forceSeek: true,
    );
  }

  Future<void> _activateListMark(ClipMark mark) async {
    if (_applySelectionModifier(mark.id)) return;
    await _selectAndMaybeSeek(mark.id, seek: true, scrollList: true);
  }

  final Map<String, GlobalKey<InlineLabelEditorState>> _labelEditorKeyById = {};

  GlobalKey<InlineLabelEditorState> _labelEditorKey(String id) =>
      _labelEditorKeyById.putIfAbsent(
        id,
        () => GlobalKey<InlineLabelEditorState>(debugLabel: 'label_$id'),
      );

  void _requestLabelFocus(String id) {
    _labelEditorKey(id).currentState?.requestFocus();
  }

  void _disposeMissingLabelFoci() {
    final alive = marksCtrl.marks.value.map((m) => m.id).toSet();
    final toDrop = _labelEditorKeyById.keys
        .where((k) => !alive.contains(k))
        .toList();
    for (final k in toDrop) {
      _labelEditorKeyById.remove(k);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return GlobalHotkeys(
      onUndo: () => history.undo(),
      onRedo: () => history.redo(),
      onCopyFrames: _copySelectedFrames,
      onCutFrames: _cutSelectedFrames,
      onPasteFrames: _pasteCopiedFrames,
      onSaveAnimation: _saveLanguageAnim,

      focusNode: _hotkeysFocus,
      bindings: keymapCtrl.toKeyBindings(seekStepMs: 100, rateStep: 0.25),
      // bindings: KeyBindings.defaultDesktop(seekStepMs: 100, rateStep: 0.25),
      onPlayPause: _toggleAnimationPlayback,
      onAddMark: () {
        final ms = animationClock.position.inMilliseconds.toDouble();
        final id = marksCtrl.addAt(ms);
        _selectAndMaybeSeek(
          id,
          seek: true,
          scrollList: true,
          forceSeek: true,
          focusLabelEditor: true,
        );
      },
      onSeek: (d) {
        animationClock.stepMs(d);
        _syncAudioToClock(forceSeek: true);
      },
      onRate: (dr) {
        _playbackRate = (_playbackRate + dr).clamp(0.25, 2.0);
        animationClock.setRate(_playbackRate);
        playback.setRate(_playbackRate);
        optionalBlockPlayback.setRate(_playbackRate);
        setState(() {});
      },
      onCtrlChange: (down) => _timelineKey.currentState?.setCtrlDown(down),
      onDeleteSelected: () {
        marksCtrl.removeSelected();
        _refreshTimelineDurationFromMarks();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          /* твой _refocus(), если нужно */
        },

        child: Scaffold(
          key: _scaffoldKey,
          drawer: _languageWorkspace == null
              ? null
              : Drawer(
                  width: 360,
                  child: SafeArea(
                    child: LanguageAnimLibraryPanel(
                      workspace: _languageWorkspace!,
                      selectedCharacterId: _selectedCharacterId,
                      selectedAnimationName: _selectedAnimationName,
                      onSelected: _loadWorkspaceAnimation,
                      onCharacterSelected: (character, animation) =>
                          _loadWorkspaceAnimation(
                            character,
                            animation,
                            closeLibrary: false,
                          ),
                      onAddCharacter: _addCharacter,
                      onAddAnimation: _addAnimation,
                      onSetCharacterBackground: _setCharacterBackground,
                      onRenameCharacter: _renameCharacter,
                      onDeleteCharacter: _deleteCharacter,
                      onRenameAnimation: _renameAnimation,
                      onDeleteAnimation: _deleteAnimation,
                      onClose: () => _scaffoldKey.currentState?.closeDrawer(),
                    ),
                  ),
                ),
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(
              _selectedAnimation == null
                  ? 'Animation maker 2.0'
                  : '$_selectedCharacterId / $_selectedAnimationName${_hasUnsavedAnimation ? ' *' : ''}',
            ),
            actions: [
              if (_languageWorkspace == null)
                IconButton(
                  tooltip: 'Open LANGUAGE_ANIM.txt',
                  onPressed: _openLanguageAnim,
                  icon: const Icon(Icons.folder_open_outlined),
                )
              else
                IconButton(
                  tooltip: 'Animation library',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.video_library_outlined),
                ),
              if (_selectedAnimation != null)
                IconButton(
                  tooltip:
                      'Save $_selectedAnimationName${_hasUnsavedAnimation ? ' *' : ''} (Ctrl+S)',
                  onPressed: _saveLanguageAnim,
                  icon: const Icon(Icons.save_outlined),
                ),
              ProjectMenu(
                onOpenSettings: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => KeybindingsDialog(controller: keymapCtrl),
                  );
                  if (mounted) setState(() {}); // чтобы перебилдить хоткеи
                },
                currentLanguagePath: _languageWorkspace?.languageFilePath,
                currentAnimationName: _selectedAnimationName,
                hasUnsavedAnimation: _hasUnsavedAnimation,
                onNew: _newLanguageAnim,
                onOpen: _openLanguageAnim,
                onSaveAnimation: _selectedAnimation == null
                    ? null
                    : _saveLanguageAnim,
                onSaveAs: _languageWorkspace == null
                    ? null
                    : _saveLanguageAnimAs,
                onAddCharacter: _languageWorkspace == null
                    ? null
                    : _addCharacter,
                onAddAnimation: _selectedCharacter == null
                    ? null
                    : _addAnimation,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 310, // подгоните по вкусу
                        child: LabelImagesPanel(
                          imgSvc: imgSvc,
                          marksListenable: marksCtrl.marks,
                        ),
                      ),
                    ),
                    SizedBox(width: 150),

                    PlaybackLabelPreview(
                      positionStream: animationClock.positionStream,
                      initialPosition: animationClock.position,
                      cycleStream: animationClock.cycleStream,
                      onPassDurationResolved: _onRandomPassDuration,
                      marksListenable: marksCtrl.marks,
                      getImageSrcForLabel: imgSvc.imageForLabelNullable,
                      backgroundImageSrc: _effectiveBackgroundPath,
                      // height: 180,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      placeholder: const Text('Add picture to preview'),
                    ),
                    // SizedBox(width: 200),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickAudio,
                      icon: const Icon(Icons.audiotrack_outlined),
                      label: Text(
                        currentAudioPath == null
                            ? 'Load audio'
                            : 'Replace audio',
                      ),
                    ),
                    if (currentAudioPath != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remove audio without changing animation',
                        onPressed: _removeAudio,
                        icon: const Icon(Icons.link_off),
                      ),
                    ],
                    if (_selectedAnimation != null) ...[
                      const SizedBox(width: 16),
                      FilterChip(
                        selected: _loopEnabled,
                        avatar: const Icon(Icons.loop, size: 18),
                        label: Text(_loopEnabled ? 'LOOP=true' : 'LOOP=false'),
                        tooltip:
                            'Repeat animation preview and save the LOOP flag',
                        onSelected: (enabled) async {
                          final before = _captureEditorState();
                          animationClock.setLooping(enabled);
                          if (mounted) {
                            setState(() => _loopEnabled = enabled);
                            _recordEditorState(before, label: 'toggle loop');
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: Icon(
                          _isRequestedBackgroundMissing
                              ? Icons.broken_image_outlined
                              : Icons.wallpaper_outlined,
                          size: 18,
                        ),
                        label: Text(_backgroundControlLabel),
                        tooltip: _isRequestedBackgroundMissing
                            ? 'Background $_effectiveBackgroundName was not found'
                            : 'Choose the animation background',
                        onPressed: _chooseAnimationBackground,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _allSelectedMarksLocked,
                        avatar: Icon(
                          _allSelectedMarksLocked
                              ? Icons.lock
                              : Icons.lock_outline,
                          size: 18,
                        ),
                        label: Text(
                          marksCtrl.selection.value.isEmpty
                              ? 'UNSKIPPABLE'
                              : 'UNSKIPPABLE (${marksCtrl.selection.value.length})',
                        ),
                        tooltip: marksCtrl.selection.value.isEmpty
                            ? 'Select frames first'
                            : (_allSelectedMarksLocked
                                  ? 'Make selected frames skippable'
                                  : 'Mark selected frames unskippable'),
                        onSelected: marksCtrl.selection.value.isEmpty
                            ? null
                            : (_) => _toggleSelectedLocked(),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _allSelectedMarksOptional,
                        avatar: const Icon(Icons.casino_outlined, size: 18),
                        label: const Text('RANDOM'),
                        tooltip: !_allSelectedMarksLocked
                            ? 'Select unskippable frames first'
                            : (_allSelectedMarksOptional
                                  ? 'Make this sequence deterministic'
                                  : 'Randomly include this sequence per loop'),
                        onSelected: !_allSelectedMarksLocked
                            ? null
                            : (enabled) {
                                if (enabled) {
                                  _enableSelectedOptional();
                                } else {
                                  _disableSelectedOptional();
                                }
                              },
                      ),
                      if (_selectedOptionalChance case final chance?) ...[
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.percent, size: 18),
                          label: Text(chance.toStringAsFixed(0)),
                          tooltip: 'Edit chance per loop',
                          onPressed: _editSelectedOptionalChance,
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _selectedOptionalIncludedInPreview,
                          avatar: Icon(
                            _selectedOptionalIncludedInPreview
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _selectedOptionalIncludedInPreview
                                ? 'PREVIEW: INCLUDED'
                                : 'PREVIEW: SKIPPED',
                          ),
                          tooltip:
                              'Choose the branch shown in the editor preview',
                          onSelected: _setSelectedOptionalPreview,
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.music_note, size: 18),
                          label: Text(
                            _selectedOptionalGroupFirstMark
                                    ?.optionalSoundName ??
                                'ADD BLOCK AUDIO',
                          ),
                          tooltip:
                              'Attach or replace audio for this random block',
                          onPressed: _selectedOptionalGroupId == null
                              ? null
                              : _pickOptionalBlockAudio,
                        ),
                        if (_selectedOptionalGroupFirstMark
                                ?.optionalSoundName !=
                            null) ...[
                          const SizedBox(width: 8),
                          ActionChip(
                            avatar: const Icon(Icons.timer_outlined, size: 18),
                            label: Text(
                              '${_selectedOptionalGroupFirstMark!.optionalSoundOffsetMs.toStringAsFixed(0)} ms',
                            ),
                            tooltip: 'Edit block audio start offset',
                            onPressed: _editOptionalBlockAudioOffset,
                          ),
                          IconButton(
                            tooltip: 'Remove block audio',
                            onPressed: _removeOptionalBlockAudio,
                            icon: const Icon(Icons.music_off_outlined),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
              // ConvertRhubarbFileButton(),
              // AutoMarkButton(
              //   onMarksReady: (marksMs) {
              //     // Создай у себя метки без лейблов
              //     // например: marksMs.map((t) => ClipMark(startMs: t)).toList();
              //   },
              //   // Тоньше подкрутить чувствительность:
              //   threshold: 0.38,
              //   minSeparationMs: 90,
              //   windowMs: 20,
              //   hopMs: 10,
              //   smoothFrames: 3,
              // ),
              StreamBuilder<Duration>(
                stream: animationClock.durationStream,
                initialData: animationClock.duration,
                builder: (context, durSnap) {
                  final durationMs = _animationDurationMs;
                  return StreamBuilder<Duration>(
                    stream: animationClock.positionStream,
                    initialData: animationClock.position,
                    builder: (context, posSnap) {
                      final positionMs = (posSnap.data ?? Duration.zero)
                          .inMilliseconds
                          .toDouble();
                      return ValueListenableBuilder<List<ClipMark>>(
                        valueListenable: marksCtrl.marks,
                        builder: (context, list, _) {
                          final blockAudioClips = _timelineBlockAudioClips;
                          return ZoomableTimeline(
                            key: _timelineKey,
                            durationMs: durationMs,
                            // positionMs: _uiMs,
                            positionMs: positionMs,
                            marks: list,
                            peaks: _peaks,
                            audioDurationMs: _audioDurationMs,
                            audioOffsetMs: _audioOffsetMs,
                            audioLabel: currentAudioPath == null
                                ? null
                                : p.basename(currentAudioPath!),
                            blockAudioClips: blockAudioClips,
                            height: blockAudioClips.isEmpty ? 126 : 160,
                            onAudioOffsetChanged: _setAudioOffset,
                            onBlockAudioOffsetChanged: _setBlockAudioOffset,
                            onBlockAudioOffsetChangeStarted:
                                _beginBlockAudioOffsetChange,
                            onBlockAudioOffsetChangeEnded:
                                _endBlockAudioOffsetChange,
                            onDurationChanged: _setAnimationDuration,
                            onAudioOffsetChangeStarted:
                                _beginTimelineEditorChange,
                            onAudioOffsetChangeEnded: () =>
                                _endTimelineEditorChange('move audio'),
                            onDurationChangeStarted: _beginTimelineEditorChange,
                            onDurationChangeEnded: () =>
                                _endTimelineEditorChange('resize timeline'),
                            waveColor: primary.withValues(alpha: 0.35),

                            selectedIds: marksCtrl.selection.value,
                            selectedMarkId: marksCtrl.singleSelectedId,
                            // onMarkTapId: (id) => _selectAndMaybeSeek(
                            //   id,
                            //   seek: true,
                            //   scrollList: true,
                            //   forceSeek: true,
                            // ),
                            onSelectRange: (from, to) =>
                                marksCtrl.applyRangeSelection(from, to),
                            onGroupDragCommit: (delta) {
                              marksCtrl.commitGroupMove(delta);
                              final firstSel = marksCtrl.singleSelectedId;
                              if (firstSel != null) {
                                _selectAndMaybeSeek(
                                  firstSel,
                                  seek: true,
                                  scrollList: true,
                                  forceSeek: true,
                                );
                              }
                            },
                            onClearSelection: () => marksCtrl.clearSelection(),

                            onTapOrDragTo: _seekAnimation,
                            // onLongPressToAdd: (ms) {
                            //   final id = marksCtrl.addAt(ms);
                            //   _selectAndMaybeSeek(
                            //     id,
                            //     seek: true,
                            //     scrollList: true,
                            //     forceSeek: true,
                            //   );
                            // },
                            onLongPressToAdd: (ms) {
                              final id = marksCtrl.addAt(ms);
                              _selectAndMaybeSeek(
                                id,
                                seek: true,
                                scrollList: true,
                                forceSeek: true,
                                focusLabelEditor: true, // <-- фокус
                              );
                            },

                            // если кликаем по метке на таймлайне — фокус НЕ нужен:
                            onMarkTapId: _activateTimelineMark,
                            getImageSrcForLabel: imgSvc.imageForLabelNullable,
                            missingImageColor: Colors.red,
                            colorTextWhenMissing: true,
                            dragHitPx: 10.0,
                            draggingBarColor: theme.colorScheme.secondary,
                            selectionOutlineColor: const Color(0xFF00B0FF),
                            selectionFillColor: const Color(0x3300B0FF),
                          );
                        },
                      );
                    },
                  );
                },
              ), // Toolbar
              StreamBuilder<bool>(
                stream: animationClock.playingStream,
                initialData: animationClock.playing,
                builder: (ctx, snap) {
                  final isPlaying = snap.data ?? false;
                  return PlaybackToolbar(
                    enabled: hasPlaybackTimeline,
                    isPlaying: isPlaying,
                    rate: _playbackRate,
                    onTogglePlay: () {
                      _toggleAnimationPlayback();
                      _refocusHotkeys();
                    },
                    onRateChanged: (v) {
                      _playbackRate = v;
                      animationClock.setRate(v);
                      playback.setRate(v);
                      optionalBlockPlayback.setRate(v);
                      _refocusHotkeys();
                      setState(() {});
                    },
                    onAddMarkAtPlayhead: () {
                      final ms = animationClock.position.inMilliseconds
                          .toDouble();
                      final id = marksCtrl.addAt(ms);
                      _selectAndMaybeSeek(
                        id,
                        seek: true,
                        scrollList: true,
                        forceSeek: true,
                        focusLabelEditor: true, // <-- фокус
                      );
                      _refocusHotkeys(); // если нужно вернуть хоткеи позже — оставляй
                    },
                  );
                },
              ),
              const SizedBox(height: 8),

              // Список меток
              Expanded(
                child: ValueListenableBuilder<List<ClipMark>>(
                  valueListenable: marksCtrl.marks,
                  builder: (context, list, _) {
                    if (!hasPlaybackTimeline && _selectedAnimation == null) {
                      return const Center(
                        child: Text('Load audio file first (wav)'),
                      );
                    }
                    if (list.isEmpty) {
                      return const Center(child: Text('Marks are empty'));
                    }

                    return ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollCtrl,
                      itemPositionsListener: _itemPositions,
                      itemCount: list.length * 2 - 1,
                      itemBuilder: (context, i) {
                        if (i.isOdd) return const Divider(height: 1);
                        final idx = i ~/ 2;
                        final m = list[idx];
                        final selected = marksCtrl.selection.value.contains(
                          m.id,
                        );
                        final ip = imageProviderFor(
                          imgSvc.imageForLabelNullable(m.label),
                        );

                        return KeyedSubtree(
                          key: ValueKey('row_${m.id}'),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _activateListMark(m),
                            child: Container(
                              color: selected
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    )
                                  : null,
                              child: ListTile(
                                leading: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _activateListMark(m),
                                  child: CircleAvatar(
                                    backgroundImage: ip, // ⬅️ безопасно
                                    backgroundColor: ip == null
                                        ? (m.color != null
                                              ? Color(m.color!)
                                              : theme.colorScheme.primary)
                                        : null,
                                    child: ip == null
                                        ? const Icon(
                                            Icons.flag,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),

                                title: Row(
                                  children: [
                                    InlineLabelEditor(
                                      key: _labelEditorKey(m.id),
                                      initial: m.label ?? '',
                                      hint: 'put label here',
                                      autofocus: false,
                                      onChangedCommitted: (text) {
                                        marksCtrl.updateLabelAtIndex(idx, text);
                                        _refocusHotkeys();
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    const Spacer(),
                                    LabelImageSlot(
                                      label: m.label,
                                      src: imgSvc.imageForLabelNullable(
                                        m.label,
                                      ),
                                      onPick: () async {
                                        final chosen = await imgSvc.pickImage();
                                        if (chosen != null) {
                                          imgSvc.setImageForLabel(
                                            m.label,
                                            chosen,
                                          );
                                          setState(() {});
                                        }
                                        _refocusHotkeys();
                                      },
                                      onClear: () {
                                        imgSvc.clearImageForLabel(m.label);
                                        setState(() {});
                                        _refocusHotkeys();
                                      },
                                    ),
                                    const SizedBox(width: 20),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Text(_stepDescription(m)),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: m.lockedSequenceId == null
                                          ? 'Add frame to unskippable sequence'
                                          : (m.optionalChancePercent == null
                                                ? 'Remove frame from unskippable sequence'
                                                : 'Remove frame from random unskippable sequence'),
                                      icon: Icon(
                                        m.lockedSequenceId == null
                                            ? Icons.lock_open_outlined
                                            : (m.optionalChancePercent == null
                                                  ? Icons.lock
                                                  : Icons.casino),
                                        color: m.lockedSequenceId == null
                                            ? null
                                            : (m.optionalChancePercent == null
                                                  ? const Color(0xFFE65100)
                                                  : const Color(0xFF6A1B9A)),
                                      ),
                                      onPressed: () => _toggleMarkLocked(m),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit step variants',
                                      icon: const Icon(Icons.tune),
                                      onPressed: () =>
                                          _editStepVariants(idx, m),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete frame',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => marksCtrl.remove(m),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
