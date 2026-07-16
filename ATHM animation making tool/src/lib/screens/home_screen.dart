// lib/screens/home_screen.dart
import 'dart:convert';

import 'package:animaker/models/timeline_clip_model.dart';
import 'package:animaker/widgets/animation_preview.dart';
import 'package:animaker/widgets/image_waveform_painter.dart';
import 'package:animaker/widgets/side_menu.dart';
import 'package:animaker/widgets/time_ruler.dart';
import 'package:animaker/widgets/timeline_clip.dart';
import 'package:animaker/widgets/waveform_interaction_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<List<TimelineClipModel>> _undoStack = [];
  final List<List<TimelineClipModel>> _redoStack = [];
  File? defaultImageFile;

  List<File> imageFiles = [];
  List<File> timelineImages = [];
  List<TimelineClipModel> _timelineClips = [];

  final double basePxPerMs = 0.2; // например: 1 секунда = 200px при зуме 1.0

  File? audioFile;
  ui.Image? waveformImage;
  double playhead = 0.0;
  Timer? playbackTimer;
  double _waveformZoom = 1.0;
  final Player _player = Player();
  Duration _currentPosition = Duration.zero;
  final _scrollController = ScrollController();
  bool _isDragging = false;
  Future<void> _pickImages() async {
    final typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'png', 'jpeg'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    if (files.isEmpty) return;

    final newFiles = files.map((xfile) => File(xfile.path));

    setState(() {
      final existingPaths = imageFiles.map((f) => f.path).toSet();

      imageFiles.addAll(
        newFiles.where((file) => !existingPaths.contains(file.path)),
      );
    });
  }

  void _saveStateForUndo() {
    // Создаём глубокую копию (важно!)
    final snapshot = _timelineClips
        .map(
          (clip) => TimelineClipModel(
            imageFile: clip.imageFile,
            startMs: clip.startMs,
            durationMs: clip.durationMs,
          ),
        )
        .toList();

    _undoStack.add(snapshot);

    if (_undoStack.length > 10) {
      _undoStack.removeAt(0);
    }

    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;

    _redoStack.add(_timelineClips);
    if (_undoStack.length > 10) {
      _undoStack.removeAt(0);
    }

    final previous = _undoStack.removeLast();
    setState(() {
      _timelineClips = previous;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;

    _undoStack.add(_timelineClips);

    final next = _redoStack.removeLast();
    setState(() {
      _timelineClips = next;
    });
  }

  void _createNewProject() {
    setState(() {
      imageFiles.clear();
      _timelineClips.clear();
      audioFile = null;
      waveformImage = null;
      playhead = 0.0;
      _currentPosition = Duration.zero;
    });
    _player.stop();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Новый проект создан')));
  }

  Future<void> _saveProjectAsJson() async {
    final location = await FileSelectorPlatform.instance.getSaveLocation(
      options: const SaveDialogOptions(suggestedName: 'timeline_project.json'),
      acceptedTypeGroups: [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );

    if (location == null) return;

    final projectData = {
      'audio': audioFile?.path,
      'clips': _timelineClips.map((clip) => clip.toJson()).toList(),
      'defaultImage': defaultImageFile?.path,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(projectData);

    final file = File(location.path);
    await file.writeAsString(jsonString);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Проект сохранён: ${location.path}')),
    );
  }

  Future<void> _loadProjectFromJson() async {
    final typeGroup = XTypeGroup(label: 'project', extensions: ['json']);

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    final projectFile = File(file.path);
    if (!projectFile.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Файл проекта не найден')));
      return;
    }

    final jsonString = await projectFile.readAsString();
    final jsonData = jsonDecode(jsonString);

    final String? audioPath = jsonData['audio'];
    final List<dynamic> clipsJson = jsonData['clips'] ?? [];
    final String? defaultImagePath = jsonData['defaultImage'];

    final audio = audioPath != null ? File(audioPath) : null;

    final timelineClips = clipsJson
        .map((clipJson) => TimelineClipModel.fromJson(clipJson))
        .where((clip) => clip.imageFile.existsSync())
        .toList();

    final imageSet = <String, File>{};
    for (final clip in timelineClips) {
      final file = clip.imageFile;
      if (file.existsSync()) {
        imageSet[file.path] = file;
      }
    }

    File? defaultImage;
    if (defaultImagePath != null) {
      final file = File(defaultImagePath);
      if (file.existsSync()) {
        defaultImage = file;
        imageSet[file.path] = file;
      }
    }

    setState(() {
      _timelineClips.clear();
      imageFiles.clear();
      audioFile = audio?.existsSync() == true ? audio : null;
      _timelineClips = timelineClips;
      imageFiles = imageSet.values.toList();
      defaultImageFile = defaultImage;
    });

    if (audioFile != null) {
      await _player.open(Media(audioFile!.path), play: false);
      await _generateWaveformImage(audioFile!.path);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Проект загружен')));
  }

  Future<void> _pickAudio() async {
    final typeGroup = XTypeGroup(
      label: 'audio',
      extensions: ['mp3', 'wav', 'm4a'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      audioFile = File(file.path);
      waveformImage = null;
      await _generateWaveformImage(file.path);
      await _player.open(Media(file.path), play: false);
    }
    setState(() {});
  }

  Future<void> _generateWaveformImage(String path) async {
    final ffmpegPath = 'windows/runner/ffmpeg/ffmpeg.exe';
    final outputPng =
        '${Directory.systemTemp.path}/waveform_${DateTime.now().millisecondsSinceEpoch}.png';

    final result = await Process.run(ffmpegPath, [
      '-y',
      '-i',
      path,
      '-filter_complex',
      'aformat=channel_layouts=mono,showwavespic=s=1000x100:colors=0x0000ff',
      '-frames:v',
      '1',
      outputPng,
    ]);

    if (result.exitCode == 0 && File(outputPng).existsSync()) {
      final bytes = await File(outputPng).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        waveformImage = frame.image;
      });
    } else {
      setState(() {});
    }
  }

  void _startPlayback() {
    if (waveformImage == null || audioFile == null) return;
    playbackTimer?.cancel();
    const interval = Duration(milliseconds: 100);
    _player.play();
    playbackTimer = Timer.periodic(interval, (timer) async {
      final position = _player.state.position;
      final duration = _player.state.duration;
      setState(() {
        _currentPosition = position;
        playhead =
            position.inMilliseconds *
            waveformImage!.width /
            duration.inMilliseconds;
        if (position >= duration) {
          playhead = 0.0;
          timer.cancel();
        }
      });
    });
  }

  void _stopPlayback() {
    playbackTimer?.cancel();
    _player.stop();
    setState(() {
      _currentPosition = Duration.zero;
    });
  }

  void _seekToFromGlobalTap(Offset globalPosition, BuildContext context) {
    final duration = _player.state.duration;
    if (waveformImage == null || duration <= Duration.zero) return;

    final box = context.findRenderObject() as RenderBox;
    final localDx = box.globalToLocal(globalPosition).dx;

    final waveformWidth = duration.inMilliseconds * basePxPerMs * _waveformZoom;

    final relativeX = localDx / waveformWidth;
    final clampedRatio = relativeX.clamp(0.0, 1.0);

    final target = Duration(
      milliseconds: (clampedRatio * duration.inMilliseconds).toInt(),
    );

    _player.seek(target);
    setState(() {
      _currentPosition = target;
      playhead = clampedRatio * waveformImage!.width;
    });
  }

  @override
  void dispose() {
    playbackTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = playbackTimer?.isActive ?? false;

    final double waveformWidth = (waveformImage?.width ?? 2000) * _waveformZoom;
    final double durationWidth =
        _player.state.duration.inMilliseconds.toDouble() *
        basePxPerMs *
        _waveformZoom;
    final double timelineWidth = waveformWidth > durationWidth
        ? waveformWidth
        : durationWidth;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyZ &&
              HardwareKeyboard.instance.isControlPressed) {
            _undo();
          } else if (event.logicalKey == LogicalKeyboardKey.keyY &&
              HardwareKeyboard.instance.isControlPressed) {
            _redo();
          } else if (event.logicalKey == LogicalKeyboardKey.space) {
            if (isPlaying) {
              _stopPlayback();
            } else {
              _startPlayback();
            }
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // leading: PopupMenuButton<String>(
          //   onSelected: (value) async {
          //     if (value == 'new') {
          //       _createNewProject();
          //     } else if (value == 'save') {
          //       await _saveProjectAsJson();
          //     } else if (value == 'load') {
          //       await _loadProjectFromJson();
          //     }
          //   },
          //   itemBuilder: (context) => const [
          //     PopupMenuItem(value: 'new', child: Text('🆕 Новый проект')),
          //     PopupMenuItem(value: 'load', child: Text('📁 Открыть проект')),
          //     PopupMenuItem(value: 'save', child: Text('💾 Сохранить проект')),
          //   ],
          //   icon: const Icon(Icons.menu),
          //   tooltip: 'Управление проектом',
          // ),
          title: const Text('Animation Editor'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'new') {
                  _createNewProject();
                } else if (value == 'save') {
                  await _saveProjectAsJson();
                } else if (value == 'load') {
                  await _loadProjectFromJson();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new', child: Text('🆕 Новый проект')),
                PopupMenuItem(value: 'load', child: Text('📁 Открыть проект')),
                PopupMenuItem(
                  value: 'save',
                  child: Text('💾 Сохранить проект'),
                ),
              ],
              icon: const Icon(Icons.menu),
              tooltip: 'Project',
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _pickImages,
              tooltip: 'Upload images',
            ),
            IconButton(
              icon: const Icon(Icons.audiotrack),
              onPressed: _pickAudio,
              tooltip: 'Load audio',
            ),
            IconButton(
              icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
              onPressed: () {
                if (isPlaying) {
                  _stopPlayback();
                } else {
                  _startPlayback();
                }
              },
              tooltip: isPlaying ? 'Остановить' : 'Воспроизвести',
            ),
          ],
        ),
        drawer: const SideMenu(),

        body: Row(
          children: [
            // 🔹 Левый сайдбар с изображениями
            Container(
              width: 200,
              color: Colors.grey[850],
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: imageFiles.length,
                itemBuilder: (context, index) {
                  final file = imageFiles[index];
                  return Draggable<File>(
                    data: file,
                    feedback: Opacity(
                      opacity: 0.8,
                      child: Image.file(
                        file,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: GestureDetector(
                      onSecondaryTapDown: (details) async {
                        final selected = await showMenu<String>(
                          context: context,
                          position: RelativeRect.fromLTRB(
                            details.globalPosition.dx,
                            details.globalPosition.dy,
                            details.globalPosition.dx,
                            details.globalPosition.dy,
                          ),
                          items: const [
                            PopupMenuItem(
                              value: 'setDefault',
                              child: Text('Set as default image'),
                            ),
                            PopupMenuItem(
                              value: 'open',
                              child: Text('Open in explorer'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete image'),
                            ),
                          ],
                        );

                        if (selected == 'setDefault') {
                          setState(() {
                            defaultImageFile = file;
                          });
                        } else if (selected == 'open') {
                          final folder = file.parent.path;
                          if (Platform.isWindows) {
                            await Process.run('explorer', [folder]);
                          } else if (Platform.isMacOS) {
                            await Process.run('open', [folder]);
                          } else if (Platform.isLinux) {
                            await Process.run('xdg-open', [folder]);
                          }
                        } else if (selected == 'delete') {
                          setState(() {
                            imageFiles.removeAt(index);
                            if (defaultImageFile?.path == file.path) {
                              defaultImageFile =
                                  null; // сброс, если удалили дефолт
                            }
                          });
                        } else if (selected == 'open') {
                          final imagePath = file.path;
                          final folder = File(imagePath).parent.path;

                          if (Platform.isWindows) {
                            await Process.run('explorer', [folder]);
                          } else if (Platform.isMacOS) {
                            await Process.run('open', [folder]);
                          } else if (Platform.isLinux) {
                            await Process.run('xdg-open', [folder]);
                          }
                        }
                      },
                      child: Stack(
                        fit: StackFit
                            .expand, // ✅ заставим Stack занимать всю ячейку
                        children: [
                          Image.file(file, fit: BoxFit.cover),
                          if (file == defaultImageFile)
                            Text(
                              'default\nimage',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.amber,
                              ),
                            ),
                        ],
                      ),

                      // child: Container(
                      //   decoration: BoxDecoration(
                      //     border: Border.all(
                      //       color: file == defaultImageFile
                      //           ? Colors.amber
                      //           : Colors.transparent,
                      //       width: 2,
                      //     ),
                      //   ),
                      //   child: Image.file(file, fit: BoxFit.cover),
                      // ),
                    ),
                  );
                },
              ),
            ),

            // 🔹 Центральная панель
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: AnimationPreview(
                      currentPosition: _currentPosition,
                      timelineClips: _timelineClips,
                      defaultImageFile: defaultImageFile,
                    ),
                  ),

                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔹 Scrollable timeline
                        Expanded(
                          child: Listener(
                            onPointerSignal: (event) {
                              if (event is PointerScrollEvent) {
                                const zoomStep = 0.1;
                                final oldZoom = _waveformZoom;
                                double newZoom = oldZoom;

                                if (event.scrollDelta.dy > 0) {
                                  newZoom = (oldZoom - zoomStep).clamp(
                                    0.5,
                                    5.0,
                                  );
                                } else {
                                  newZoom = (oldZoom + zoomStep).clamp(
                                    0.5,
                                    5.0,
                                  );
                                }

                                if (newZoom == oldZoom) return;

                                final scrollX = _scrollController.offset;

                                // Координата мыши относительно ScrollView
                                final mouseX = event.localPosition.dx;

                                // Точка на временной шкале в мс
                                final timeAtCursor =
                                    (scrollX + mouseX) /
                                    (basePxPerMs * oldZoom);

                                // Новый scrollOffset, чтобы timeAtCursor осталась на том же экране
                                final newScrollOffset =
                                    timeAtCursor * (basePxPerMs * newZoom) -
                                    mouseX;

                                setState(() {
                                  _waveformZoom = newZoom;
                                });

                                // Применяем новый scroll
                                _scrollController.jumpTo(
                                  newScrollOffset.clamp(
                                    0.0,
                                    _scrollController.position.maxScrollExtent,
                                  ),
                                );
                              }
                            },
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              thickness: 4,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: timelineWidth,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 🔹 Шкала времени
                                      SizedBox(
                                        height: 30,
                                        child: WaveformInteractionOverlay(
                                          onTapSeekFromGlobal:
                                              _seekToFromGlobalTap,
                                          scrollController: _scrollController,
                                          isDragging: _isDragging,
                                          onDragChange: (drag) => setState(
                                            () => _isDragging = drag,
                                          ),
                                          child: TimeRuler(
                                            totalDurationMs: _player
                                                .state
                                                .duration
                                                .inMilliseconds
                                                .toDouble(),
                                            pxPerMs:
                                                basePxPerMs * _waveformZoom,
                                          ),
                                        ),
                                      ),

                                      // 🔹 Timeline с draggable клипами
                                      Expanded(
                                        child: Container(
                                          color: Colors.blueGrey[900],
                                          child: DragTarget<File>(
                                            onAcceptWithDetails: (details) {
                                              final dropPosition =
                                                  details.offset.dx +
                                                  _scrollController.offset -
                                                  200; // ✅ с учетом скролла
                                              final startMs =
                                                  dropPosition /
                                                  (basePxPerMs * _waveformZoom);

                                              setState(() {
                                                _timelineClips.add(
                                                  TimelineClipModel(
                                                    imageFile: details.data,
                                                    startMs: startMs.clamp(
                                                      0,
                                                      double.infinity,
                                                    ),
                                                    durationMs:
                                                        100, // или 1, если решишь уменьшить
                                                  ),
                                                );
                                              });
                                            },
                                            builder:
                                                (
                                                  context,
                                                  candidateData,
                                                  rejectedData,
                                                ) {
                                                  return Stack(
                                                    children: _timelineClips.map((
                                                      clip,
                                                    ) {
                                                      return TimelineClip(
                                                        key: ValueKey(clip),
                                                        allClips:
                                                            _timelineClips,
                                                        clip: clip,
                                                        pxPerMs:
                                                            basePxPerMs *
                                                            _waveformZoom,
                                                        onUpdate:
                                                            (
                                                              newStart,
                                                              newDuration,
                                                            ) {
                                                              setState(() {
                                                                clip.startMs =
                                                                    newStart;
                                                                clip.durationMs =
                                                                    newDuration;
                                                              });
                                                            },
                                                        onDelete: () {
                                                          setState(() {
                                                            _timelineClips
                                                                .remove(clip);
                                                          });
                                                        },
                                                        onStartEdit:
                                                            _saveStateForUndo,
                                                      );
                                                    }).toList(),
                                                  );
                                                },
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      // 🔹 Волна
                                      Expanded(
                                        child: Container(
                                          color: Colors.black,
                                          child: waveformImage != null
                                              ? WaveformInteractionOverlay(
                                                  onTapSeekFromGlobal:
                                                      _seekToFromGlobalTap,
                                                  scrollController:
                                                      _scrollController,
                                                  isDragging: _isDragging,
                                                  onDragChange: (drag) =>
                                                      setState(
                                                        () =>
                                                            _isDragging = drag,
                                                      ),
                                                  child: CustomPaint(
                                                    painter: ImageWaveformPainter(
                                                      waveformImage!,
                                                      playhead,
                                                      zoom: _waveformZoom,
                                                      waveformScale:
                                                          (_player
                                                                      .state
                                                                      .duration
                                                                      .inMilliseconds >
                                                                  0
                                                              ? _player
                                                                    .state
                                                                    .duration
                                                                    .inMilliseconds
                                                                    .toDouble()
                                                              : 1.0) *
                                                          basePxPerMs /
                                                          waveformImage!.width,
                                                    ),
                                                    child:
                                                        const SizedBox.expand(),
                                                  ),
                                                )
                                              : const Center(
                                                  child: Text(
                                                    'Waveform not loaded',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),

                                      // 🔹 Таймер
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          right: 8,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '${_formatDuration(_currentPosition)} / ${_formatDuration(_player.state.duration)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 🔹 Слайдер зума
                        Slider(
                          min: 0.5,
                          max: 5.0,
                          divisions: 9,
                          label: '${_waveformZoom.toStringAsFixed(1)}x',
                          value: _waveformZoom,
                          onChanged: (value) {
                            setState(() => _waveformZoom = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
