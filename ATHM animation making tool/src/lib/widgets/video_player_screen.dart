// video_player_with_timeline_improved.dart
import 'dart:convert';
import 'dart:io';

import 'package:animaker/widgets/side_menu.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

class VideoPlayerWithTimeline extends StatefulWidget {
  const VideoPlayerWithTimeline({super.key});

  @override
  State<VideoPlayerWithTimeline> createState() =>
      _VideoPlayerWithTimelineState();
}

class _VideoPlayerWithTimelineState extends State<VideoPlayerWithTimeline> {
  late final Player player;
  late final VideoController controller;

  String? currentVideoPath;

  Directory? _exportDir; // куда сохранять кадры и JSON
  String? _audioFilePath; // опционально: путь к аудио
  String? _defaultImagePath; // опционально: путь к дефолтной картинке

  /// Храним метки отдельно, чтобы не триггерить rebuild всего экрана по каждой позиции.
  final ValueNotifier<List<ClipMark>> marks = ValueNotifier<List<ClipMark>>([]);

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _pickExportDir() async {
    // На Web недоступно
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выбор папки не поддержан в Web')),
        );
      }
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      setState(() => _exportDir = Directory(path));
    }
  }

  // Future<void> _pickAudio() async {
  //   final result = await FilePicker.platform.pickFiles(type: FileType.audio);
  //   final path = result?.files.single.path;
  //   if (path != null) setState(() => _audioFilePath = path);
  // }

  // Future<void> _pickDefaultImage() async {
  //   final result = await FilePicker.platform.pickFiles(type: FileType.image);
  //   final path = result?.files.single.path;
  //   if (path != null) setState(() => _defaultImagePath = path);
  // }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    await player.stop(); // сброс проигрывателя
    currentVideoPath = path;
    marks.value = []; // очищаем метки под новый файл
    setState(() {}); // показать видеоплеер и кнопки
    await player.open(Media(path));
  }

  void _insertMarkSorted(double startMs, {double epsilon = 50}) {
    final list = List<ClipMark>.from(marks.value);

    // не добавляем дубликаты рядом
    if (list.any((m) => (m.startMs - startMs).abs() < epsilon)) return;

    // бинарный поиск позиции вставки
    int lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].startMs < startMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    list.insert(lo, ClipMark(startMs: startMs));
    marks.value = list;
  }

  void _removeLastMark() {
    final list = List<ClipMark>.from(marks.value);
    if (list.isEmpty) return;
    list.removeLast();
    marks.value = list;
  }

  Future<void> _exportFramesAndJson() async {
    final list = List<ClipMark>.from(marks.value);
    if (list.isEmpty) return;

    // 1) Посчитаем длительности
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    for (int i = 0; i < list.length - 1; i++) {
      final d = (list[i + 1].startMs - list[i].startMs).clamp(
        100,
        double.infinity,
      );
      list[i].durationMs = d.toDouble();
    }
    final totalMs = player.state.duration.inMilliseconds.toDouble();
    if (totalMs > 0) {
      final last = list.last;
      last.durationMs ??= (totalMs - last.startMs).clamp(100, double.infinity);
    } else {
      list.last.durationMs ??= 1000;
    }

    // 2) Директория сохранения
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Экспорт на Web не реализован в этом примере'),
          ),
        );
      }
      return;
    }

    final dir =
        _exportDir ?? Directory(p.join(Directory.current.path, 'exports'));
    await dir.create(recursive: true);

    // 3) Сохраняем кадры frame_1.png, frame_2.png, ...
    for (int i = 0; i < list.length; i++) {
      final m = list[i];
      await player.seek(Duration(milliseconds: m.startMs.round()));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      Uint8List? bytes;
      for (int attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bytes = await player.screenshot();
        if (bytes != null) break;
      }
      if (bytes == null) continue;

      final filename = 'frame_${i + 1}.png';
      final fullPath = p.join(dir.path, filename);
      await File(fullPath).writeAsBytes(bytes);
      m.imagePath = fullPath; // важно: путь попадёт в JSON
    }

    // 4) JSON в требуемом формате
    final jsonData = {
      'audio': _audioFilePath,
      'clips': list
          .map(
            (m) => {
              'image': m.imagePath,
              'startMs': m.startMs,
              'durationMs': m.durationMs,
            },
          )
          .toList(),
      'defaultImage': _defaultImagePath,
    };

    final jsonFile = File(p.join(dir.path, 'clips.json'));
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonData),
    );

    marks.value = list;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Сохранено в: ${dir.path}\n'
            'Кадры: ${list.where((m) => m.imagePath != null).length}\n'
            'JSON: ${jsonFile.path}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  double _playbackRate = 1.0;

  void _setPlaybackRate(double rate) {
    _playbackRate = rate;
    player.setRate(rate);
    setState(() {});
  }

  void changePlaybackRate(double delta) {
    _playbackRate = (_playbackRate + delta).clamp(0.25, 2.0);
    player.setRate(_playbackRate);

    setState(() {});
  }

  void stepFrame(int frames, {int fps = 30}) {
    final frameDurationMs = (1000 / fps).round();
    final posMs = player.state.position.inMilliseconds;
    final newPosMs = (posMs + frames * frameDurationMs).clamp(
      0,
      player.state.duration.inMilliseconds,
    );
    player.seek(Duration(milliseconds: newPosMs.toInt()));
    Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = currentVideoPath != null;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyB) {
            final ms = player.state.position.inMilliseconds.toDouble();
            _insertMarkSorted(ms);
          }
          if (event.logicalKey == LogicalKeyboardKey.space) {
            player.playOrPause();
          }
          if (event.logicalKey == LogicalKeyboardKey.equal) {
            changePlaybackRate(0.25);
          }
          if (event.logicalKey == LogicalKeyboardKey.minus) {
            changePlaybackRate(-0.25);
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            stepFrame(1);
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            stepFrame(-1);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Видео + Таймлайн (улучшено)')),
        drawer: const SideMenu(),

        body: Column(
          children: [
            // Кнопки управления
            if (hasVideo) Expanded(child: Video(controller: controller)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Загрузить видео'),
                  ),
                  if (hasVideo)
                    StreamBuilder<bool>(
                      stream: player
                          .stream
                          .playing, // true — играет, false — на паузе
                      initialData: player.state.playing,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return ElevatedButton.icon(
                          onPressed: () => player.playOrPause(),
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(isPlaying ? 'Pause' : ' Play'),
                        );
                      },
                    ),
                  if (hasVideo)
                    DropdownButton<double>(
                      value: _playbackRate,
                      items: const [
                        DropdownMenuItem(value: 0.25, child: Text('0.25x')),
                        DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                        DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                        DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                        DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                        DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                        DropdownMenuItem(value: 1.75, child: Text('1.75x')),
                        DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                      ],
                      onChanged: (v) {
                        if (v != null) _setPlaybackRate(v);
                      },
                    ),
                  if (hasVideo)
                    OutlinedButton.icon(
                      onPressed: _removeLastMark,
                      icon: const Icon(Icons.undo),
                      label: const Text('Удалить последнюю'),
                    ),
                  if (hasVideo)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Очистить метки?'),
                            content: const Text('Действие нельзя отменить.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Очистить'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) marks.value = [];
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Очистить метки'),
                    ),
                  if (hasVideo)
                    OutlinedButton.icon(
                      onPressed: _pickExportDir,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                        _exportDir == null
                            ? 'Папка экспорта'
                            : 'Папка: ${p.basename(_exportDir!.path)}',
                      ),
                    ),

                  if (hasVideo)
                    FilledButton.icon(
                      onPressed: _exportFramesAndJson,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Сохранить кадры + JSON'),
                    ),
                ],
              ),
            ),

            if (hasVideo)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // Таймлайн с кастомным painter и drag-scrub
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
                                return SizedBox(
                                  height: 40,
                                  child: TimelineBar(
                                    durationMs: durationMs,
                                    positionMs: positionMs,
                                    marks: list,
                                    onTapOrDragTo: (ms) async {
                                      await player.seek(
                                        Duration(milliseconds: ms.round()),
                                      );
                                    },
                                    onAddMarkAt: (ms) => _insertMarkSorted(ms),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 6),

                    // Быстрая кнопка "метка по текущей"
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final ms = player.state.position.inMilliseconds
                                .toDouble();
                            _insertMarkSorted(ms);
                          },
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Метка по текущей позиции'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Инфо
                    ValueListenableBuilder<List<ClipMark>>(
                      valueListenable: marks,
                      builder: (context, list, _) {
                        return Text(
                          'Метки: ${list.length} — '
                          'текущая: ${player.state.position.inMilliseconds} / ${player.state.duration.inMilliseconds} мс',
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Таймлайн с кастомным рендером и управлением мышью/тачем
class TimelineBar extends StatefulWidget {
  const TimelineBar({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.marks,
    required this.onTapOrDragTo,
    required this.onAddMarkAt,
  });

  final double durationMs;
  final double positionMs;
  final List<ClipMark> marks;
  final ValueChanged<double> onTapOrDragTo;
  final ValueChanged<double> onAddMarkAt;

  @override
  State<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<TimelineBar> {
  void _seekFromLocalX(Offset localPos, double width) {
    final ms = widget.durationMs <= 0
        ? 0.0
        : (localPos.dx.clamp(0, width) / width) * widget.durationMs;
    widget.onTapOrDragTo(ms);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return SizedBox(
          width: c.maxWidth,
          height: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _seekFromLocalX(d.localPosition, c.maxWidth);
              // Второй тап по playhead зоне можно поменять на onAddMarkAt, но сейчас — ЛКМ добавляет метку с LongPress:
            },
            onLongPressStart: (d) {
              final ms = widget.durationMs <= 0
                  ? 0.0
                  : (d.localPosition.dx.clamp(0, c.maxWidth) / c.maxWidth) *
                        widget.durationMs;
              widget.onAddMarkAt(ms);
            },
            onHorizontalDragStart: (d) =>
                _seekFromLocalX(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _seekFromLocalX(d.localPosition, c.maxWidth),
            child: CustomPaint(
              painter: _TimelinePainter(
                durationMs: widget.durationMs,
                positionMs: widget.positionMs,
                marks: widget.marks,
                surfaceColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                markerColor: Theme.of(context).colorScheme.primary,
                playheadColor: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.durationMs,
    required this.positionMs,
    required this.marks,
    required this.surfaceColor,
    required this.markerColor,
    required this.playheadColor,
  });

  final double durationMs;
  final double positionMs;
  final List<ClipMark> marks;
  final Color surfaceColor;
  final Color markerColor;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    final bgPaint = Paint()..color = surfaceColor;
    canvas.drawRRect(r, bgPaint);

    double xForMs(double ms) =>
        durationMs <= 0 ? 0 : (ms / durationMs) * size.width;

    // Маркеры
    final markerPaint = Paint()..color = markerColor;
    const markerWidth = 4.0;
    final markerTop = 4.0;
    final markerBottom = size.height - 4.0;

    for (final m in marks) {
      final x = xForMs(m.startMs).clamp(0.0, size.width);
      final rect = Rect.fromLTWH(
        x - markerWidth / 2,
        markerTop,
        markerWidth,
        markerBottom - markerTop,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rr, markerPaint);
    }

    // Плейхед
    final phX = xForMs(positionMs).clamp(0.0, size.width);
    final playheadPaint = Paint()..color = playheadColor;
    canvas.drawRect(Rect.fromLTWH(phX - 1, 0, 2, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) {
    return old.durationMs != durationMs ||
        old.positionMs != positionMs ||
        !listEquals(old.marks, marks) ||
        old.surfaceColor != surfaceColor ||
        old.markerColor != markerColor ||
        old.playheadColor != playheadColor;
  }
}

class ClipMark {
  ClipMark({required this.startMs, this.imagePath, this.durationMs});
  final double startMs;
  String? imagePath;
  double? durationMs;

  Map<String, dynamic> toJson() => {
    'image': imagePath,
    'startMs': startMs,
    'durationMs': durationMs,
  };

  @override
  bool operator ==(Object other) {
    return other is ClipMark &&
        other.startMs == startMs &&
        other.imagePath == imagePath &&
        other.durationMs == durationMs;
  }

  @override
  int get hashCode => Object.hash(startMs, imagePath, durationMs);
}
