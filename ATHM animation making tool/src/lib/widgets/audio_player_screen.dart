// AudioMarksScreen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:animaker/widgets/inline_label_editor.dart';
import 'package:animaker/widgets/label_image_slot.dart';
import 'package:animaker/widgets/language_anim_popup_menu_button.dart';
import 'package:animaker/widgets/playback_player_preview.dart';
import 'package:animaker/widgets/zoomable_timeline.dart';
import 'package:animaker/widgets/zscript_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:path/path.dart' as p;
import 'package:file_selector/file_selector.dart';

import '../features/audio_marks/domain/entities/clip_mark.dart';

final _itemScrollCtrl = ItemScrollController();
final _itemPositions = ItemPositionsListener.create();

class AudioMarksScreen extends StatefulWidget {
  const AudioMarksScreen({super.key});

  @override
  State<AudioMarksScreen> createState() => _AudioMarksScreenState();
}

class _AudioMarksScreenState extends State<AudioMarksScreen> {
  late final Player player;
  final FocusNode _screenFocus = FocusNode(
    debugLabel: 'screenHotkeys',
    skipTraversal: true,
  );

  String? currentAudioPath;
  String? _projectPath;

  final ValueNotifier<List<ClipMark>> marks = ValueNotifier<List<ClipMark>>([]);
  double _playbackRate = 1.0;

  final _timelineKey = GlobalKey<ZoomableTimelineState>();

  List<double>? _peaks;

  // label -> image (путь на desktop; для web ниже покажу вариант с bytes)
  final Map<String, String> _labelImagePath = {};
  final String kNoLabelKey = '__NO_LABEL__';
  String? _pendingScrollId;

  Set<String> _selectedIds = <String>{};

  // Одиночный выбор берём из множества:
  String? get _singleSelectedId =>
      _selectedIds.length == 1 ? _selectedIds.first : null;

  // void _selectOnly(String id) {
  //   _selectedIds
  //     ..clear()
  //     ..add(id);
  //   _selectedMarkId = id;
  //   setState(() {});
  // }

  // рамка-выделение
  void _applyRangeSelection(double fromMs, double toMs) {
    final lo = math.min(fromMs, toMs);
    final hi = math.max(fromMs, toMs);
    final ids = marks.value
        .where((m) => m.startMs >= lo && m.startMs <= hi)
        .map((m) => m.id)
        .toSet();
    setState(() {
      _selectedIds = ids;
    });
  }

  void _removeMark(ClipMark m) {
    final list = List<ClipMark>.from(marks.value)..remove(m);
    marks.value = list;
    if (_selectedIds.contains(m.id)) {
      setState(() => _selectedIds = {..._selectedIds}..remove(m.id));
    }
  }

  void _commitGroupMove(double deltaMs) {
    if (_selectedIds.isEmpty || deltaMs == 0) return;

    final list = List<ClipMark>.from(marks.value);
    for (int i = 0; i < list.length; i++) {
      final m = list[i];
      if (_selectedIds.contains(m.id)) {
        final next = (m.startMs + deltaMs).clamp(
          0.0,
          player.state.duration.inMilliseconds.toDouble(),
        );
        list[i] = m.copyWith(startMs: next);
      }
    }
    // пересортировать по времени
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    marks.value = list;

    // оставить выделение и, например, привязать плейхед к первой
    if (_selectedIds.isNotEmpty) {
      final first = list.firstWhere((m) => _selectedIds.contains(m.id));
      _setSelectedMark(first.id, seek: true, scrollList: true, forceSeek: true);
    }
  }

  // нормализация ключа (чтобы ' Куплет ' и 'Куплет' считались одним)
  String _norm(String s) => s.trim();

  // установить/очистить картинку для лейбла
  // void _setImageForLabel(String label, String path) {
  //   setState(() => _labelImagePath[_norm(label)] = path);
  // }

  void _clearImageForLabel(String label) {
    setState(() => _labelImagePath.remove(_norm(label)));
  }

  // сделать относительный путь относительно projectDir, если возможно
  String? _storePath(String? absOrDataUrl, String projectDir) {
    if (absOrDataUrl == null || absOrDataUrl.isEmpty) return null;
    if (kIsWeb) return absOrDataUrl; // web: оставляем как есть
    if (absOrDataUrl.startsWith('data:image/')) {
      return absOrDataUrl; // dataURL – оставляем
    }
    final normalized = p.normalize(absOrDataUrl);
    if (p.isWithin(projectDir, normalized)) {
      return p.relative(normalized, from: projectDir); // относительный
    }
    return normalized; // абсолютный
  }

  // превратить хранимое значение в абсолютный путь (или dataURL)
  String _resolvePath(String stored, String projectDir) {
    if (stored.startsWith('data:image/')) return stored;
    if (p.isAbsolute(stored)) return p.normalize(stored);
    return p.normalize(p.join(projectDir, stored));
  }

  Map<String, dynamic> _buildProjectMap({
    required String projectDir,
    required String? currentAudioPath,
    required List<ClipMark> clips,
    required String? Function(String? label) imageForLabelNullable,
    required String? defaultImagePath, // _labelImagePath[kNoLabelKey]
  }) {
    return {
      'version': 1,
      'audio': _storePath(currentAudioPath, projectDir),
      'clips': [
        for (final m in clips)
          {
            'image': _storePath(imageForLabelNullable(m.label), projectDir),
            'startMs': m.startMs,
            'label': m.label ?? '',
          },
      ],
      'defaultImage': _storePath(defaultImagePath, projectDir),
    };
  }

  Future<void> _applyProjectFromMap(
    Map<String, dynamic> map, {
    required String projectFilePath, // полный путь к *.json
    required void Function(List<ClipMark>)
    setClipsSorted, // marks.replaceFromJson(...)
    required void Function(String? absPath)
    setAudioPath, // присвоить currentAudioPath и открыть
    required void Function(String key, String path)
    setLabelImage, // _labelImagePath[key]=path; setState
    required void Function(String key) clearLabelImage, // удалить ключ
  }) async {
    final projectDir = p.dirname(projectFilePath);

    // audio
    final storedAudio = map['audio'] as String?;
    String? resolvedAudio;
    if (storedAudio != null && storedAudio.isNotEmpty) {
      resolvedAudio = _resolvePath(storedAudio, projectDir);
    }
    setAudioPath(resolvedAudio);

    // clips
    final rawClips = (map['clips'] as List?) ?? const [];
    final clips = <ClipMark>[];
    // по ходу загрузки восстановим соответствия label→image
    final tmpLabelToImage = <String, String>{};

    for (final e in rawClips) {
      final m = e as Map<String, dynamic>;
      final startMs = (m['startMs'] as num).toDouble();
      final labelRaw = (m['label'] as String?)?.trim();
      final imageStored = m['image'] as String?;

      // восстановление мапы картинок
      if (imageStored != null && imageStored.isNotEmpty) {
        final resolved = _resolvePath(imageStored, projectDir);
        final key = _labelKey(labelRaw);
        // последний побеждает — если хочешь «первый побеждает», проверяй containsKey
        tmpLabelToImage[key] = resolved;
      }

      clips.add(
        ClipMark(
          id: genId(), // ids заново, формат их не требует
          startMs: startMs,
          label: (labelRaw == null || labelRaw.isEmpty) ? null : labelRaw,
          color: _parseColor(m['color']), // <-- вот это добавили
        ),
      );
    }

    // defaultImage для пустого label
    final def = map['defaultImage'] as String?;
    if (def != null && def.isNotEmpty) {
      tmpLabelToImage[kNoLabelKey] = _resolvePath(def, projectDir);
    }

    // применяем label→image в UI
    // сначала чистим старое
    clearLabelImage(kNoLabelKey);
    // Здесь лучше пройти по всем известным ключам и очистить, если у тебя есть их список.
    // Для краткости — просто пишем новые:
    tmpLabelToImage.forEach((k, v) => setLabelImage(k, v));

    // клипы — отсортировано по времени на всякий
    clips.sort((a, b) => a.startMs.compareTo(b.startMs));
    setClipsSorted(clips);
  }

  Future<void> _saveProjectTo(String path) async {
    final map = _buildProjectMap(
      projectDir: p.dirname(path),
      currentAudioPath: currentAudioPath,
      clips: marks.value,
      imageForLabelNullable: imageForLabelNullable,
      defaultImagePath: _labelImagePath[kNoLabelKey],
    );

    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(map);

      if (kIsWeb) {
        // на web можно оставить твой диалог с JSON либо реализовать скачивание (conditional import)
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('project.json'),
            content: SingleChildScrollView(child: Text(jsonStr)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final file = File(path);
      await file.writeAsString(jsonStr);

      _projectPath = path;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Сохранено: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  Future<void> saveProjectJson() async {
    if (_projectPath == null) {
      await saveProjectJsonAs();
    } else {
      await _saveProjectTo(_projectPath!);
    }
  }

  Future<void> saveProjectJsonAs() async {
    // Web: оставляем твой существующий путь (показать JSON/скачать)
    if (kIsWeb) {
      await saveProjectJson();
      return;
    }

    // Мобилки: у file_selector нет "save location" → используем file_picker
    if (Platform.isAndroid || Platform.isIOS) {
      final output = await FilePicker.platform.saveFile(
        dialogTitle: 'Выберите место для project.json',
        fileName: 'project.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (output == null) return;
      final withExt = p.extension(output).toLowerCase() == '.json'
          ? output
          : '$output.json';
      await _saveProjectTo(withExt);
      return;
    }

    // Десктоп (Windows/macOS/Linux): file_selector → getSaveLocation
    const fileName = 'project.json';
    final loc = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;

    final path = p.extension(loc.path).toLowerCase() == '.json'
        ? loc.path
        : '${loc.path}.json';
    await _saveProjectTo(path);
  }

  Future<void> loadProjectJson() async {
    if (kIsWeb) {
      // web-ветка по желанию
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    try {
      final text = await File(path).readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;

      await _applyProjectFromMap(
        map,
        projectFilePath: path,
        setClipsSorted: (clips) {
          clips.sort((a, b) => a.startMs.compareTo(b.startMs));
          marks.value = List<ClipMark>.from(clips);
        },
        setAudioPath: (absPath) async {
          currentAudioPath = absPath;
          await player.stop();
          if (absPath != null) {
            await player.open(Media(absPath));
            // при загрузке — пересчитать пики, как ты уже сделал ранее
            _peaks = null;
            try {
              if (absPath.toLowerCase().endsWith('.wav')) {
                const buckets = 1200;
                _peaks = await computePeaksFromWavFile(
                  absPath,
                  buckets: buckets,
                );
              }
            } catch (_) {
              _peaks = null;
            }
            if (mounted) setState(() {});
          }
        },
        setLabelImage: (key, pathToImg) {
          setState(() => _labelImagePath[key] = pathToImg);
        },
        clearLabelImage: (key) {
          setState(() => _labelImagePath.remove(key));
        },
      );

      _projectPath = path; // ← запоминаем где лежит проект
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Загружено: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    }
  }

  int? _parseColor(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt(); // 0.0 -> 0
    return null;
  }

  String _labelKey(String? label) {
    if (label == null || label.trim().isEmpty) {
      return kNoLabelKey; // "__NO_LABEL__" для "без лейбла"
    }
    return label.trim(); // убираем пробелы для обычных лейблов
  }

  String? _imagePathForLabel(String? label) =>
      _labelImagePath[_labelKey(label)];

  // Получить картинку по label; если label == null → берём "без лейбла"
  String? imageForLabelNullable(String? label) {
    if (label == null) return _labelImagePath[kNoLabelKey];
    final key = label.trim();
    if (key.isEmpty) return _labelImagePath[kNoLabelKey];
    return _labelImagePath[key];
  }

  Future<void> pickImageForLabel(String? label) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: kIsWeb, // на web пригодятся bytes
    );
    if (res == null) return;

    final key = _labelKey(label);

    if (kIsWeb) {
      final bytes = res.files.single.bytes;
      if (bytes == null) return;
      final ext = res.files.single.extension ?? 'png';
      final dataUrl = 'data:image/$ext;base64,${base64Encode(bytes)}';
      setState(() => _labelImagePath[key] = dataUrl);
    } else {
      final path = res.files.single.path;
      if (path == null) return;
      setState(() => _labelImagePath[key] = path);
    }
  }

  bool _isEditingOrDropdownFocused() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;

    // Текстовые поля — не трогаем хоткеи
    final isEditing =
        ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isEditing) return true;

    // Любая часть DropdownButton или его меню в Overlay
    final inDropdown =
        ctx.findAncestorWidgetOfExactType<DropdownButton<dynamic>>() != null ||
        ctx.findAncestorWidgetOfExactType<DropdownMenuItem<dynamic>>() != null;
    return inDropdown;
  }

  bool _onGlobalKeyBool(KeyEvent e) {
    if (_isEditingOrDropdownFocused()) {
      return false; // пропускаем событие дальше
    }

    final focus = FocusManager.instance.primaryFocus;
    final isEditing =
        focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isEditing) return false;

    if (e is KeyRepeatEvent) {
      return true; // игнор повтора (не дублировать действие)
    }

    if (e is KeyDownEvent) {
      final k = e.logicalKey;
      if (k == LogicalKeyboardKey.space) {
        player.playOrPause();
        return true;
      }
      if (k == LogicalKeyboardKey.keyB) {
        addMarkAt(player.state.position.inMilliseconds.toDouble());
        return true;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        stepMs(100);
        return true;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        stepMs(-100);
        return true;
      }
      if (k == LogicalKeyboardKey.equal) {
        _changePlaybackRate(0.25);
        return true;
      }
      if (k == LogicalKeyboardKey.minus) {
        _changePlaybackRate(-0.25);
        return true;
      }
      if (k == LogicalKeyboardKey.controlLeft ||
          k == LogicalKeyboardKey.controlRight) {
        _timelineKey.currentState?.setCtrlDown(true);
        return true;
      }
    }

    if (e is KeyUpEvent &&
        (e.logicalKey == LogicalKeyboardKey.controlLeft ||
            e.logicalKey == LogicalKeyboardKey.controlRight)) {
      _timelineKey.currentState?.setCtrlDown(false);
      return true;
    }

    return false; // не наш хоткей
  }

  // 2) Регистрация/удаление
  late final bool Function(KeyEvent) _keyHandlerBool;

  @override
  void initState() {
    super.initState();
    player = Player();
    _keyHandlerBool = _onGlobalKeyBool;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _screenFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    player.dispose();
    _screenFocus.dispose();

    super.dispose();
  }

  // GlobalKey _keyForId(String id) => _tileKeys[id] ??= GlobalKey();

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'wav',
        'mp3',
        'm4a',
        'aac',
        'flac',
        'ogg',
      ], // что хочешь
    );
    if (result == null) return;

    final file = result.files.single;

    await player.stop();
    currentAudioPath = file.path; // на Web может быть null — ок
    marks.value = [];
    _peaks = null;
    setState(() {});
    await player.open(
      Media(currentAudioPath ?? file.name),
    ); // media_kit сам разберётся

    // считаем пики только для WAV (для других форматов можно позже добавить декодер)
    final isWav = (file.extension?.toLowerCase() == 'wav');
    if (!isWav) return;

    // setState(() => _peaksLoading = true);

    // Хотим, чтобы число "бакетов" было близко к пикселям таймлайна.
    // Если таймлайн ~600-1000px шириной, возьмём 1200 для гладкости.
    const buckets = 1200;

    try {
      if (kIsWeb && file.bytes != null) {
        _peaks = await computePeaksFromWavBytes(file.bytes!, buckets: buckets);
      } else if (file.path != null) {
        _peaks = await computePeaksFromWavFile(file.path!, buckets: buckets);
      }
    } catch (_) {
      _peaks = null; // если что-то пошло не так — без волны
    } finally {
      // if (mounted) setState(() => _peaksLoading = false);
    }
  }

  void _changePlaybackRate(double delta) {
    _playbackRate = (_playbackRate + delta).clamp(0.25, 2.0);
    player.setRate(_playbackRate);
    setState(() {});
  }

  void _setPlaybackRate(double v) {
    _playbackRate = v.clamp(0.25, 2.0);
    player.setRate(_playbackRate);
    setState(() {});
  }

  /// Добавить метку на позицию [ms].
  /// - анти-дубликат по времени: если есть метка ближе чем [epsilon] мс — ничего не вставляем,
  ///   просто выделяем найденную метку;
  /// - если вставили новую — сразу выделяем её и (опционально) делаем seek/проскролл.
  /// Возвращает id выбранной/добавленной метки.
  Future<String> addMarkAt(
    double ms, {
    String? label,
    int? color,
    double epsilon = 20.0,
    bool seek = true,
    bool scrollList = true,
  }) async {
    final list = List<ClipMark>.from(marks.value);

    // 1) анти-дубликат: ищем существующую близко к ms
    final existingIndex = list.indexWhere(
      (m) => (m.startMs - ms).abs() < epsilon,
    );
    if (existingIndex != -1) {
      final existing = list[existingIndex];
      // Можно обновить label/color, если переданы (по желанию):
      if ((label != null && label.trim().isNotEmpty) || color != null) {
        list[existingIndex] = existing.copyWith(
          label: (label == null || label.trim().isEmpty)
              ? existing.label
              : label.trim(),
          color: color ?? existing.color,
        );
        marks.value = list;
      }
      await _setSelectedMark(
        existing.id,
        seek: true,
        scrollList: scrollList,
        forceSeek: true,
      );
      return existing.id;
    }

    // 2) создаём новую метку
    final mark = ClipMark(
      id: genId(),
      startMs: ms,
      label: (label == null || label.trim().isEmpty) ? null : label.trim(),
      color: color,
    );

    // 3) бинарный поиск позиции вставки по startMs
    int lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].startMs < mark.startMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    list.insert(lo, mark);
    marks.value = list;

    // 4) сразу выделяем новую метку
    await _setSelectedMark(
      mark.id,
      seek: seek,
      scrollList: scrollList,
      forceSeek: true,
    );
    return mark.id;
  }

  // обновление label инлайном: создаём новый объект и заменяем в списке
  void _updateMarkLabel(int index, String? newLabel) {
    final oldList = marks.value;
    if (index < 0 || index >= oldList.length) return;
    final updated = oldList[index].copyWith(
      label: (newLabel == null)
          // label: (newLabel == null || newLabel.trim().isEmpty)
          ? null
          : newLabel.trim(),
    );
    final newList = List<ClipMark>.from(oldList)..[index] = updated;
    marks.value = newList;
  }

  int _listIndexForMarkIndex(int markIndex) => markIndex * 2;

  Future<void> _scrollToMarkId(String id) async {
    final markIndex = marks.value.indexWhere((m) => m.id == id);
    if (markIndex < 0) return;

    // Ждём, пока применится setState/ValueListenable и список посчитает новый itemCount
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_itemScrollCtrl.isAttached) return;

      final listLen = marks.value.length;
      if (listLen == 0) return;

      final target = _listIndexForMarkIndex(markIndex);
      final itemCount = listLen * 2 - 1;
      if (target < 0 || target >= itemCount) return; // страховка

      try {
        await _itemScrollCtrl.scrollTo(
          index: target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.2,
        );
      } catch (_) {
        // Если во время анимации снова вставили метку — пробуем ещё раз после следующего кадра
        WidgetsBinding.instance.addPostFrameCallback((__) async {
          if (!_itemScrollCtrl.isAttached) return;
          final listLen2 = marks.value.length;
          final itemCount2 = listLen2 * 2 - 1;
          final mi2 = marks.value.indexWhere((m) => m.id == id);
          if (mi2 < 0) return;
          final target2 = _listIndexForMarkIndex(mi2);
          if (target2 < 0 || target2 >= itemCount2) return;
          await _itemScrollCtrl.scrollTo(
            index: target2,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: 0.2,
          );
        });
      }
    });
  }

  // программное выделение (и при создании новой метки тоже сюда попадаем)
  Future<void> _setSelectedMark(
    String id, {
    bool seek = true,
    bool scrollList = true,
    bool forceSeek = true,
  }) async {
    final changed = !_selectedIds.contains(id) || _selectedIds.length != 1;
    if (changed) {
      setState(() {
        _selectedIds = {id};
      });
    }
    if (seek && (changed || forceSeek)) {
      final m = marks.value.firstWhere(
        (e) => e.id == id,
        orElse: () => marks.value.first,
      );
      await player.seek(Duration(milliseconds: m.startMs.round()));
    }
    if (scrollList) {
      _pendingScrollId = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final toScroll = _pendingScrollId;
        _pendingScrollId = null;
        if (toScroll != null) _scrollToMarkId(toScroll);
      });
    }
  }

  // шаг по времени (не по кадрам, для аудио это логично)
  void stepMs(int deltaMs) {
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    final next = (pos + deltaMs).clamp(0, dur);
    player.seek(Duration(milliseconds: next));
  }

  void _handleKeyEvent(KeyEvent e) {
    final focus = FocusManager.instance.primaryFocus;
    final isEditing =
        focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

    if (isEditing) return;
    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.space) {
        player.playOrPause();
      } else if (e.logicalKey == LogicalKeyboardKey.keyB) {
        final ms = player.state.position.inMilliseconds.toDouble();
        addMarkAt(ms);
      } else if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
        stepMs(100); // 100 мс вперед
      } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
        stepMs(-100); // 100 мс назад
      } else if (e.logicalKey == LogicalKeyboardKey.equal) {
        _changePlaybackRate(0.25); // '+'
      } else if (e.logicalKey == LogicalKeyboardKey.minus) {
        _changePlaybackRate(-0.25); // '-'
      } else if ((e.logicalKey == LogicalKeyboardKey.controlLeft ||
          e.logicalKey == LogicalKeyboardKey.controlRight)) {
        _timelineKey.currentState?.setCtrlDown(true);
      }
    }
    if (e is KeyUpEvent &&
        (e.logicalKey == LogicalKeyboardKey.controlLeft ||
            e.logicalKey == LogicalKeyboardKey.controlRight)) {
      _timelineKey.currentState?.setCtrlDown(false);
    }
  }

  late KeyEventResult Function(KeyEvent) _keyHandler;

  bool get _isEditing {
    final focus = FocusManager.instance.primaryFocus;
    // не трогаем хоткеи, если курсор в поле ввода
    return focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onGlobalKey(KeyEvent e) {
    // Не мешаем набору текста
    final focus = FocusManager.instance.primaryFocus;
    final isEditing =
        focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isEditing) return KeyEventResult.ignored;

    if (e is KeyRepeatEvent) return KeyEventResult.handled;

    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.space) {
        player.playOrPause();
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyB) {
        final ms = player.state.position.inMilliseconds.toDouble();
        // добавить метку и сразу выделить
        addMarkAt(ms);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
        stepMs(100);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
        stepMs(-100);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.equal) {
        _changePlaybackRate(0.25); // '+'
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.minus) {
        _changePlaybackRate(-0.25); // '-'
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.controlLeft ||
          e.logicalKey == LogicalKeyboardKey.controlRight) {
        _timelineKey.currentState?.setCtrlDown(true);
        return KeyEventResult.handled;
      }
    }

    if (e is KeyUpEvent &&
        (e.logicalKey == LogicalKeyboardKey.controlLeft ||
            e.logicalKey == LogicalKeyboardKey.controlRight)) {
      _timelineKey.currentState?.setCtrlDown(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _refocus() {
    if (!mounted) return;
    if (!_screenFocus.hasFocus) _screenFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = currentAudioPath != null;

    return Focus(
      focusNode: _screenFocus,
      autofocus: true,
      onKeyEvent: (node, event) => _onGlobalKey(event),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          final ctx = FocusManager.instance.primaryFocus?.context;
          final typing =
              ctx != null &&
              (ctx.widget is EditableText ||
                  ctx.findAncestorWidgetOfExactType<EditableText>() != null);
          if (!typing) {
            _refocus();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Animation maker 2.0'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Проект',
                onSelected: (v) async {
                  if (v == 'new') {
                    marks.value = [];
                    _projectPath = null; // сбросим текущий путь
                    await saveProjectJsonAs();
                  } else if (v == 'save') {
                    await saveProjectJson();
                  } else if (v == 'save_as') {
                    await saveProjectJsonAs();
                  } else if (v == 'load') {
                    await loadProjectJson();
                  } else if (v == 'export') {
                    await ZScriptIO.exportInteractive(
                      context,
                      currentAudioPath: currentAudioPath,
                      getTotalDurationMs: () =>
                          player.state.duration.inMilliseconds,
                      marks: marks.value,
                      imageForLabelNullable: imageForLabelNullable,
                    );
                  } else if (v == 'import') {
                    final imported = await ZScriptIO.importInteractive(
                      context,
                      idFactory: () => genId(),
                    );
                    if (imported != null) {
                      // применяешь как обычно
                      imported.sort((a, b) => a.startMs.compareTo(b.startMs));
                      marks.value = List<ClipMark>.from(imported);
                    }
                  } else if (v == 'export_language_anim') {
                    await exportLanguageAnimFromJsonBatch(context);
                    _refocus(); // твой helper, чтобы вернуть фокус экрану
                  }
                },
                itemBuilder: (ctx) => [
                  if (_projectPath != null)
                    PopupMenuItem(
                      enabled: false,
                      value: 'current',
                      child: Text(
                        p.basename(_projectPath!),
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'new',
                    child: Text('🆕 Новый проект'),
                  ),
                  const PopupMenuItem(
                    value: 'load',
                    child: Text('📁 Открыть проект'),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: Text('💾 Сохранить'),
                  ),
                  const PopupMenuItem(
                    value: 'save_as',
                    child: Text('💾 Сохранить как…'),
                  ),

                  PopupMenuItem(value: 'export', child: Text('Экспорт .zc')),
                  PopupMenuItem(value: 'import', child: Text('Импорт .zc')),
                  const PopupMenuItem(
                    value: 'export_language_anim',
                    child: Text('Export LANGUAGE_ANIM.txt…'),
                  ),
                ],
                icon: const Icon(Icons.menu),
              ),
            ],
          ),
          body: Column(
            children: [
              // BatchJsonProjectsToZScriptButton(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: PlaybackLabelPreview(
                  player: player,
                  marksListenable: marks, // твой ValueNotifier<List<ClipMark>>
                  getImageSrcForLabel: imageForLabelNullable,
                  height: 180,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  placeholder: const Text('Add picture to preview'),
                ),
              ),

              // ZScriptIOButtons(
              //   currentAudioPath: currentAudioPath,
              //   getTotalDurationMs: () => player.state.duration.inMilliseconds,
              //   marksListenable: marks, // ValueNotifier<List<ClipMark>>
              //   imageForLabelNullable: imageForLabelNullable,
              //   onImportMarks: (list) {
              //     // применяем в ваше состояние
              //     list.sort((a, b) => a.startMs.compareTo(b.startMs));
              //     marks.value = List<ClipMark>.from(list);
              //   },
              // ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  onPressed: _pickAudio,
                  icon: const Icon(Icons.audiotrack_outlined),
                  label: const Text('Load audio'),
                ),
              ),

              // Таймлайн + позиция
              StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: player.state.duration,
                builder: (context, durSnap) {
                  final durationMs = (durSnap.data ?? Duration.zero)
                      .inMilliseconds
                      .toDouble();
                  return StreamBuilder<Duration>(
                    stream: player.stream.position,
                    initialData: player.state.position,
                    builder: (context, posSnap) {
                      final positionMs = (posSnap.data ?? Duration.zero)
                          .inMilliseconds
                          .toDouble();
                      return ValueListenableBuilder<List<ClipMark>>(
                        valueListenable: marks,
                        builder: (context, list, _) {
                          return Column(
                            children: [
                              ZoomableTimeline(
                                key: _timelineKey,
                                durationMs: durationMs,
                                positionMs: positionMs,
                                marks: list,
                                peaks: _peaks,
                                waveColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.35),

                                // выбор
                                selectedIds: _selectedIds,
                                selectedMarkId:
                                    _singleSelectedId, // из геттера!
                                onMarkTapId: (id) => _setSelectedMark(
                                  id,
                                  seek: true,
                                  scrollList:
                                      true, // ← важно, чтобы по клику на таймлайне скроллило список
                                  forceSeek: true,
                                ),
                                onSelectRange:
                                    _applyRangeSelection, // рамка-выделение (групповое)
                                onGroupDragCommit:
                                    _commitGroupMove, // перенос группы
                                onClearSelection: () {
                                  if (_selectedIds.isNotEmpty) {
                                    setState(() => _selectedIds = <String>{});
                                  }
                                },
                                // навигация по таймлайну
                                onTapOrDragTo: (ms) => player.seek(
                                  Duration(milliseconds: ms.round()),
                                ),
                                onLongPressToAdd: (ms) => addMarkAt(ms),

                                // подсветка «нет картинки»
                                getImageSrcForLabel: imageForLabelNullable,
                                missingImageColor: Colors.red,
                                colorTextWhenMissing: true,

                                dragHitPx: 10.0,
                                draggingBarColor: Theme.of(
                                  context,
                                ).colorScheme.secondary,
                                selectionOutlineColor: const Color(0xFF00B0FF),
                                selectionFillColor: const Color(0x3300B0FF),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),

              // верх: кнопки управления
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (hasAudio)
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (ctx, snap) {
                          final isPlaying = snap.data ?? false;
                          return ElevatedButton.icon(
                            onPressed: () {
                              player.playOrPause();
                              _refocus();
                            },
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(isPlaying ? 'Pause' : 'Play'),
                          );
                        },
                      ),
                    if (hasAudio)
                      DropdownButton<double>(
                        value: _playbackRate,
                        items: const [
                          DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                          DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                          DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                          DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                          DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                          DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                        ],
                        onChanged: (v) {
                          if (v != null) _setPlaybackRate(v);
                          // вернуть фокус «экрану» после закрытия меню
                          Future.microtask(() => _screenFocus.requestFocus());
                          _refocus();
                        },
                      ),
                    if (hasAudio)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          final ms = player.state.position.inMilliseconds
                              .toDouble();
                          addMarkAt(ms);
                          _refocus();
                        },
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('+ Clipmark'),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // список меток с инлайновым редактированием label
              Expanded(
                child: ValueListenableBuilder<List<ClipMark>>(
                  valueListenable: marks,
                  builder: (context, list, _) {
                    if (!hasAudio) {
                      return const Center(
                        child: Text('Загрузите аудио, чтобы добавлять метки'),
                      );
                    }
                    if (list.isEmpty) {
                      return const Center(child: Text('Метки отсутствуют'));
                    }

                    return ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollCtrl,
                      itemPositionsListener: _itemPositions,
                      itemCount: list.length * 2 - 1, // элементы + разделители
                      itemBuilder: (context, i) {
                        if (i.isOdd) return const Divider(height: 1);
                        final idx = i ~/ 2;
                        final m = list[idx];
                        final selected = _selectedIds.contains(m.id);

                        // СТАБИЛЬНЫЙ обычный ключ по id — и больше ничего
                        return KeyedSubtree(
                          key: ValueKey('row_${m.id}'),
                          child: Container(
                            color: selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.08)
                                : null,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: m.color != null
                                    ? Color(m.color!)
                                    : Theme.of(context).colorScheme.primary,
                                child: const Icon(
                                  Icons.flag,
                                  color: Colors.white,
                                ),
                              ),
                              title: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  InlineLabelEditor(
                                    // hotkeysNode: _hotkeysNode,
                                    initial: m.label ?? '',
                                    hint: 'put label here',
                                    onChangedCommitted: (text) {
                                      _updateMarkLabel(idx, text);
                                      _refocus();
                                    },
                                  ),
                                  LabelImageSlot(
                                    label: m.label,
                                    src: _imagePathForLabel(m.label),
                                    onPick: () => pickImageForLabel(m.label),
                                    onClear: () {
                                      final lbl = m.label;
                                      if (lbl != null &&
                                          lbl.trim().isNotEmpty) {
                                        _clearImageForLabel(lbl);
                                      }
                                      _refocus();
                                    },
                                  ),

                                  Container(width: 20),
                                ],
                              ),
                              subtitle: Text(
                                '${m.startMs.toStringAsFixed(0)} ms',
                              ),
                              onTap: () => _setSelectedMark(
                                m.id,
                                seek: true,
                                scrollList: false,
                              ),

                              trailing: IconButton(
                                tooltip: 'Удалить',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeMark(m),
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
