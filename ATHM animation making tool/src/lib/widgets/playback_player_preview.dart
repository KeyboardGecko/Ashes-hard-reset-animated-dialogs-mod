import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../features/audio_marks/domain/entities/clip_mark.dart';
import '../features/audio_marks/application/random_preview_timeline.dart';

/// Превью картинки по текущей позиции плеера.
/// - Без анимации.
/// - Картинка берётся по label активной метки (последняя метка с startMs <= позиция).
/// - Если label отсутствует → используем картинку "для отсутствующего лейбла".
class PlaybackLabelPreview extends StatefulWidget {
  const PlaybackLabelPreview({
    super.key,
    this.player,
    this.positionStream,
    this.initialPosition,
    this.cycleStream,
    this.onPassDurationResolved,
    required this.marksListenable,
    required this.getImageSrcForLabel, // String? Function(String? label)
    this.width = 240 * 2,
    this.height = 160 * 2,
    this.fit = BoxFit.contain, // показываем всё изображение
    this.placeholder,
    this.zoom = 1.5,
    this.backgroundColor,
    this.backgroundImageSrc,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final Player? player;
  final Stream<Duration>? positionStream;
  final Duration? initialPosition;
  final Stream<int>? cycleStream;
  final ValueChanged<double>? onPassDurationResolved;
  final ValueListenable<List<ClipMark>> marksListenable;
  final double zoom;

  /// Возвращает путь/URL/ data: URL для картинки.
  /// Если label == null → это "картинка для отсутствующего лейбла".
  final String? Function(String? label) getImageSrcForLabel;

  final double width;
  final double height;
  final BoxFit fit;
  final Widget? placeholder;
  final Color? backgroundColor;
  final String? backgroundImageSrc;
  final BorderRadius borderRadius;

  @override
  State<PlaybackLabelPreview> createState() => _PlaybackLabelPreviewState();
}

class _PlaybackLabelPreviewState extends State<PlaybackLabelPreview> {
  List<RandomPreviewSpan> _pass = const [];
  StreamSubscription<int>? _cycleSubscription;
  StreamSubscription<bool>? _playerCompletedSubscription;

  @override
  void initState() {
    super.initState();
    widget.marksListenable.addListener(_marksChanged);
    _resolvePass(notify: false);
    _subscribeToCycles();
  }

  @override
  void didUpdateWidget(covariant PlaybackLabelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marksListenable != widget.marksListenable) {
      oldWidget.marksListenable.removeListener(_marksChanged);
      widget.marksListenable.addListener(_marksChanged);
      _resolvePass();
    }
    if (oldWidget.cycleStream != widget.cycleStream ||
        oldWidget.player != widget.player) {
      _subscribeToCycles();
    }
  }

  void _subscribeToCycles() {
    _cycleSubscription?.cancel();
    _playerCompletedSubscription?.cancel();
    _cycleSubscription = widget.cycleStream?.listen((_) => _resolvePass());
    _playerCompletedSubscription = widget.player?.stream.completed.listen((
      done,
    ) {
      if (done) _resolvePass();
    });
  }

  void _marksChanged() => _resolvePass();

  void _resolvePass({bool notify = true}) {
    _pass = buildSelectedPreviewTimeline(widget.marksListenable.value);
    if (_pass.isNotEmpty && widget.onPassDurationResolved != null) {
      final durationMs = _pass.last.endMs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPassDurationResolved?.call(durationMs);
      });
    }
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.marksListenable.removeListener(_marksChanged);
    _cycleSubscription?.cancel();
    _playerCompletedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          color:
              widget.backgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: StreamBuilder<Duration>(
            stream: widget.positionStream ?? widget.player?.stream.position,
            initialData:
                widget.initialPosition ?? widget.player?.state.position,
            builder: (context, posSnap) {
              final posMs = (posSnap.data ?? Duration.zero).inMilliseconds
                  .toDouble();
              final label = _activeLabelForPosition(posMs);
              final src =
                  widget.getImageSrcForLabel(label) ??
                  widget.getImageSrcForLabel(null);
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  if (widget.backgroundImageSrc != null)
                    _buildImage(
                      widget.backgroundImageSrc,
                      showPlaceholder: false,
                    ),
                  _buildImage(src, showPlaceholder: true),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Возвращаем label последней метки с startMs <= posMs.
  /// Если такой нет или label пустой — вернём null (будет показана "картинка для отсутствующего").
  String? _activeLabelForPosition(double posMs) {
    if (_pass.isEmpty) return null;
    const eps = 5.0; // мс допуска: 20–40 обычно ок

    // бинарный поиск "последний <= posMs + eps"
    final target = posMs + eps;
    int lo = 0, hi = _pass.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_pass[mid].startMs <= target) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (ans == -1) return null;

    final raw = _pass[ans].label;
    final lab = (raw == null || raw.trim().isEmpty) ? null : raw.trim();
    return lab;
  }

  Widget _buildImage(String? src, {required bool showPlaceholder}) {
    final provider = _imageProviderFor(src);
    if (provider == null) {
      if (!showPlaceholder) return const SizedBox.shrink();
      if (widget.placeholder != null) return Center(child: widget.placeholder);
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Opacity(
          opacity: 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.image_outlined, size: 28),
              SizedBox(height: 6),
              Text('No picture'),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Transform.scale(
        scale: widget.zoom,
        alignment: Alignment.center,
        child: Image(
          image: provider,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => showPlaceholder
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Opacity(
                    opacity: 0.6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.broken_image_outlined, size: 28),
                        SizedBox(height: 6),
                        Text('Failed to load image'),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  ImageProvider? _imageProviderFor(String? src) {
    if (src == null || src.isEmpty) return null;

    // data: URL -> MemoryImage (везде)
    if (src.startsWith('data:image/')) {
      final i = src.indexOf(',');
      if (i <= 0) return null;
      try {
        return MemoryImage(base64Decode(src.substring(i + 1)));
      } catch (_) {
        return null;
      }
    }

    // Web: только сети/блоб/файл-URL
    if (kIsWeb) {
      return NetworkImage(src);
    }

    // Desktop/Mobile: локальный файл, иначе сеть (если есть схема)
    try {
      final f = File(src);
      if (f.existsSync()) return FileImage(f);
    } catch (_) {}
    final uri = Uri.tryParse(src);
    if (uri != null && uri.hasScheme) return NetworkImage(src);

    return null;
  }
}
