import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;

import '../features/audio_marks/domain/entities/clip_mark.dart';

enum SeekTrigger { down, up }

class ZoomableTimeline extends StatefulWidget {
  const ZoomableTimeline({
    this.onClearSelection,

    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.marks,
    required this.onTapOrDragTo,
    required this.onLongPressToAdd,
    this.onMarkTapId,
    this.peaks,
    this.waveColor,
    this.audioDurationMs = 0,
    this.audioOffsetMs = 0,
    this.audioLabel,
    this.onAudioOffsetChanged,
    this.onDurationChanged,
    this.onAudioOffsetChangeStarted,
    this.onAudioOffsetChangeEnded,
    this.onDurationChangeStarted,
    this.onDurationChangeEnded,
    this.minPxPerMs = 0.05,
    this.maxPxPerMs = 2.0,
    this.initialPxPerMs = 0.3,
    this.height = 126,
    this.edgePadding = 24,

    this.getImageSrcForLabel, // String? Function(String? label)
    this.missingImageColor = Colors.red,
    this.colorTextWhenMissing = true,

    this.selectedMarkId,
    this.onMarkDragCommit,
    this.dragHitPx = 10.0,
    this.draggingBarColor,

    this.selectedIds,
    this.onSelectRange,
    this.onGroupDragCommit,
    this.selectionOutlineColor = const Color(0xFF00B0FF),
    this.selectionFillColor = const Color(0x3300B0FF),

    this.seekTrigger = SeekTrigger.up,
  });
  final VoidCallback? onClearSelection;
  final SeekTrigger seekTrigger;

  final String? selectedMarkId;
  final void Function(String id, double newMs)? onMarkDragCommit;
  final double dragHitPx;
  final Color? draggingBarColor;

  final Set<String>? selectedIds;
  final void Function(double fromMs, double toMs)? onSelectRange;
  final void Function(double deltaMs)? onGroupDragCommit;
  final Color selectionOutlineColor;
  final Color selectionFillColor;

  final String? Function(String? label)? getImageSrcForLabel;
  final Color missingImageColor;
  final bool colorTextWhenMissing;

  final double durationMs;
  final double positionMs;
  final List<ClipMark> marks;
  final ValueChanged<double> onTapOrDragTo;
  final ValueChanged<double> onLongPressToAdd;
  final ValueChanged<String>? onMarkTapId;

  final List<double>? peaks;
  final Color? waveColor;
  final double audioDurationMs;
  final double audioOffsetMs;
  final String? audioLabel;
  final ValueChanged<double>? onAudioOffsetChanged;
  final ValueChanged<double>? onDurationChanged;
  final VoidCallback? onAudioOffsetChangeStarted;
  final VoidCallback? onAudioOffsetChangeEnded;
  final VoidCallback? onDurationChangeStarted;
  final VoidCallback? onDurationChangeEnded;

  final double minPxPerMs;
  final double maxPxPerMs;
  final double initialPxPerMs;
  final double height;
  final double edgePadding;

  @override
  State<ZoomableTimeline> createState() => ZoomableTimelineState();
}

class ZoomableTimelineState extends State<ZoomableTimeline> {
  late final ScrollController _hScroll;
  late double _pxPerMs;
  bool _ctrlDown = false;
  double _viewportW = 0;

  @override
  void initState() {
    super.initState();
    _hScroll = ScrollController();
    _pxPerMs = widget.initialPxPerMs;
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void setCtrlDown(bool v) {
    if (_ctrlDown != v) setState(() => _ctrlDown = v);
  }

  void _zoomAtPointer({
    required double viewportX,
    required double dy,
    required double viewportWidth,
  }) {
    if (widget.durationMs <= 0) return;

    final contentLeftPx = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final pointerContentPx = contentLeftPx + viewportX;
    final tMs = ((pointerContentPx - widget.edgePadding) / _pxPerMs).clamp(
      0.0,
      widget.durationMs,
    );

    final k = math.exp(-dy * 0.002); // dy>0 -> зум ин
    final nextPxPerMs = (_pxPerMs * k).clamp(
      widget.minPxPerMs,
      widget.maxPxPerMs,
    );

    final newPointerContentPx = widget.edgePadding + tMs * nextPxPerMs;
    double newContentLeft = newPointerContentPx - viewportX;
    final maxLeft = math.max(0.0, _contentWidth(nextPxPerMs) - viewportWidth);
    newContentLeft = newContentLeft.clamp(0.0, maxLeft);

    setState(() => _pxPerMs = nextPxPerMs);
    if (_hScroll.hasClients) {
      _hScroll.jumpTo(newContentLeft);
    }
  }

  double _trackWidth(double pxPerMs) =>
      (widget.durationMs * pxPerMs).clamp(1.0, double.infinity);

  double _contentWidth(double pxPerMs) =>
      _trackWidth(pxPerMs) + widget.edgePadding * 2;

  void _scrollToMs(
    double ms, {
    double alignment = 0.1,
    Duration duration = const Duration(milliseconds: 180),
  }) {
    if (!_hScroll.hasClients || _viewportW <= 0) return;
    final contentW = _contentWidth(_pxPerMs);
    final maxLeft = math.max(0.0, contentW - _viewportW);
    final x =
        widget.edgePadding + (ms * _pxPerMs).clamp(0.0, _trackWidth(_pxPerMs));
    final targetLeft = (x - alignment * _viewportW).clamp(0.0, maxLeft);
    _hScroll.animateTo(
      targetLeft,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        _viewportW = constraints.maxWidth; // 👈 ДОБАВИТЬ
        final viewportW = _viewportW;
        final trackW = _trackWidth(_pxPerMs);

        final physics = _ctrlDown
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics();

        final timeline = SizedBox(
          width: trackW,
          height: widget.height,
          child: _TimelineGesturesAndPaint(
            onClearSelection: widget.onClearSelection,
            seekTrigger: widget.seekTrigger,
            durationMs: widget.durationMs,
            positionMs: widget.positionMs,
            marks: widget.marks,
            peaks: widget.peaks,
            waveColor: widget.waveColor,
            audioDurationMs: widget.audioDurationMs,
            audioOffsetMs: widget.audioOffsetMs,
            audioLabel: widget.audioLabel,
            onAudioOffsetChanged: widget.onAudioOffsetChanged,
            onDurationChanged: widget.onDurationChanged,
            onAudioOffsetChangeStarted: widget.onAudioOffsetChangeStarted,
            onAudioOffsetChangeEnded: widget.onAudioOffsetChangeEnded,
            onDurationChangeStarted: widget.onDurationChangeStarted,
            onDurationChangeEnded: widget.onDurationChangeEnded,
            pxPerMs: _pxPerMs,
            onTapOrDragTo: widget.onTapOrDragTo,
            onLongPressToAdd: widget.onLongPressToAdd,
            onMarkTapId: widget.onMarkTapId,

            getImageSrcForLabel: widget.getImageSrcForLabel,
            missingImageColor: widget.missingImageColor,
            colorTextWhenMissing: widget.colorTextWhenMissing,

            selectedMarkId: widget.selectedMarkId,
            onMarkDragCommit: widget.onMarkDragCommit,
            dragHitPx: widget.dragHitPx,
            draggingBarColor:
                widget.draggingBarColor ??
                Theme.of(context).colorScheme.secondary,
            selectedIds: widget.selectedIds ?? const <String>{},
            onSelectRange: widget.onSelectRange,
            onGroupDragCommit: widget.onGroupDragCommit,
            selectionOutlineColor: widget.selectionOutlineColor,
            selectionFillColor: widget.selectionFillColor,
            requestScrollToMs: (ms) => _scrollToMs(ms, alignment: 0.08),
          ),
        );

        return Column(
          children: [
            Listener(
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent) {
                  if (_ctrlDown) {
                    // ===== ЗУМ ПРИ CTRL + КОЛЕСО =====
                    _zoomAtPointer(
                      viewportX: signal.localPosition.dx,
                      dy: signal.scrollDelta.dy,
                      viewportWidth: viewportW,
                    );
                  } else {
                    // ===== ГОРИЗОНТАЛЬНАЯ ПРОКРУТКА БЕЗ CTRL =====
                    if (_hScroll.hasClients) {
                      final contentW = _contentWidth(_pxPerMs);
                      final maxLeft = (contentW - viewportW).clamp(
                        0.0,
                        double.infinity,
                      );

                      // Берём вертикальный delta как основной; если трекпад даёт dx — используем его
                      final raw = signal.scrollDelta.dy != 0
                          ? signal.scrollDelta.dy
                          : signal.scrollDelta.dx;

                      // Коэффициент «скорости» прокрутки — подбери по вкусу
                      const k = 1.0; // можно 1.5–2.0, если кажется медленно

                      double next = _hScroll.offset + raw * k;

                      next = next.clamp(0.0, maxLeft);
                      _hScroll.jumpTo(next);
                    }
                  }
                }
              },
              child: Scrollbar(
                controller: _hScroll,
                thickness: 3,
                interactive: true,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  // когда Ctrl зажат — мы сами обрабатываем колесо для зума,
                  physics: physics,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.edgePadding,
                    ),
                    child: timeline,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineGesturesAndPaint extends StatefulWidget {
  const _TimelineGesturesAndPaint({
    required this.seekTrigger,
    required this.durationMs,
    required this.positionMs,
    required this.marks,
    required this.onTapOrDragTo,
    required this.onLongPressToAdd,
    this.onMarkTapId,
    required this.pxPerMs,
    this.peaks,
    this.waveColor,
    required this.audioDurationMs,
    required this.audioOffsetMs,
    this.audioLabel,
    this.onAudioOffsetChanged,
    this.onDurationChanged,
    this.onAudioOffsetChangeStarted,
    this.onAudioOffsetChangeEnded,
    this.onDurationChangeStarted,
    this.onDurationChangeEnded,

    this.getImageSrcForLabel,
    required this.missingImageColor,
    required this.colorTextWhenMissing,

    this.selectedMarkId,
    this.onMarkDragCommit,
    required this.dragHitPx,
    required this.draggingBarColor,

    required this.selectedIds,
    this.onSelectRange,
    this.onGroupDragCommit,
    required this.selectionOutlineColor,
    required this.selectionFillColor,
    required this.requestScrollToMs,
    this.onClearSelection,
  });
  final SeekTrigger seekTrigger;
  final void Function(double ms) requestScrollToMs;

  final double durationMs;
  final double positionMs;
  final List<ClipMark> marks;
  final ValueChanged<double> onTapOrDragTo;
  final ValueChanged<double> onLongPressToAdd;
  final ValueChanged<String>? onMarkTapId;

  final double pxPerMs;
  final List<double>? peaks;
  final Color? waveColor;
  final double audioDurationMs;
  final double audioOffsetMs;
  final String? audioLabel;
  final ValueChanged<double>? onAudioOffsetChanged;
  final ValueChanged<double>? onDurationChanged;
  final VoidCallback? onAudioOffsetChangeStarted;
  final VoidCallback? onAudioOffsetChangeEnded;
  final VoidCallback? onDurationChangeStarted;
  final VoidCallback? onDurationChangeEnded;

  final String? Function(String? label)? getImageSrcForLabel;
  final Color missingImageColor;
  final bool colorTextWhenMissing;

  // одиночный drag
  final String? selectedMarkId;
  final void Function(String id, double newMs)? onMarkDragCommit;
  final double dragHitPx;
  final Color draggingBarColor;

  // marquee + group
  final Set<String> selectedIds;
  final void Function(double fromMs, double toMs)? onSelectRange;
  final void Function(double deltaMs)? onGroupDragCommit;
  final Color selectionOutlineColor;
  final Color selectionFillColor;
  final VoidCallback? onClearSelection;

  @override
  State<_TimelineGesturesAndPaint> createState() =>
      _TimelineGesturesAndPaintState();
}

class _TimelineGesturesAndPaintState extends State<_TimelineGesturesAndPaint> {
  // одиночный перенос
  String? _draggingId;
  double? _draggingMs;

  // групповое перетаскивание
  bool _groupDragging = false;
  double _groupDeltaMs = 0.0;
  double? _groupAnchorMs;

  // рамка-выделение
  double? _selStartX;
  double? _selEndX;

  // hover-курсор
  bool _hoveringSelected = false;
  bool _hoveringDurationHandle = false;
  bool _resizingDuration = false;
  double? _durationResizeAnchorX;
  bool _durationResizeStarted = false;
  bool _draggingAudio = false;
  double _audioDragAnchorX = 0;
  double _audioDragStartMs = 0;
  String? _downHitId; // id метки под курсором в момент Down

  Offset? _pointerDownPx;
  static const double _clickEps =
      6.0; // допуск пикселей для "это был клик, не drag"

  double _msFromX(double x) =>
      (x / widget.pxPerMs).clamp(0.0, widget.durationMs);

  String? _hitTestMarkId(double x) {
    final hit = widget.dragHitPx;
    String? best;
    double bestDx = double.infinity;
    for (final m in widget.marks) {
      final mx = m.startMs * widget.pxPerMs;
      final dx = (mx - x).abs();
      if (dx <= hit && dx < bestDx) {
        bestDx = dx;
        best = m.id;
      }
    }
    return best;
  }

  bool _isOverSelected(double x) {
    final id = _hitTestMarkId(x);
    return id != null &&
        (widget.selectedIds.contains(id) || id == widget.selectedMarkId);
  }

  bool _isOverDurationHandle(Offset position) =>
      position.dy <= 34 &&
      (position.dx - widget.durationMs * widget.pxPerMs).abs() <= 12;

  void _resetPointerInteraction() {
    _groupDragging = false;
    _groupDeltaMs = 0.0;
    _groupAnchorMs = null;
    _draggingId = null;
    _draggingMs = null;
    _selStartX = null;
    _selEndX = null;
    _downHitId = null;
    _pointerDownPx = null;
    _resizingDuration = false;
    _durationResizeAnchorX = null;
    _durationResizeStarted = false;
    _draggingAudio = false;
  }

  (double min, double max) _allowedGroupDeltaRange() {
    if (widget.selectedIds.isEmpty) return (0.0, 0.0);
    double minStart = double.infinity;
    double maxStart = -double.infinity;
    for (final m in widget.marks) {
      if (!widget.selectedIds.contains(m.id)) continue;
      if (m.startMs < minStart) minStart = m.startMs;
      if (m.startMs > maxStart) maxStart = m.startMs;
    }
    final left = -minStart;
    final right = widget.durationMs - maxStart;
    return (left, right);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          (_groupDragging ||
              _draggingId != null ||
              _hoveringSelected ||
              _hoveringDurationHandle ||
              _resizingDuration ||
              _draggingAudio)
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.basic,
      onHover: (e) {
        final over = _isOverSelected(e.localPosition.dx);
        final overDurationHandle = _isOverDurationHandle(e.localPosition);
        if (over != _hoveringSelected ||
            overDurationHandle != _hoveringDurationHandle) {
          setState(() {
            _hoveringSelected = over;
            _hoveringDurationHandle = overDurationHandle;
          });
        }
      },
      onExit: (_) {
        if (_hoveringSelected || _hoveringDurationHandle) {
          setState(() {
            _hoveringSelected = false;
            _hoveringDurationHandle = false;
          });
        }
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (ev) {
          _pointerDownPx = ev.localPosition;
          final x = ev.localPosition.dx;
          final hitId = _hitTestMarkId(x);
          _downHitId = hitId; // 👈 запомнили кандидата

          final atDurationHandle = _isOverDurationHandle(ev.localPosition);
          final audioLeft = widget.audioOffsetMs * widget.pxPerMs;
          final audioRight =
              (widget.audioOffsetMs + widget.audioDurationMs) * widget.pxPerMs;
          final inAudio =
              ev.localPosition.dy >= 38 &&
              x >= audioLeft &&
              x <= audioRight &&
              widget.audioDurationMs > 0;

          if (atDurationHandle) {
            _resizingDuration = true;
            _durationResizeAnchorX = x;
            _durationResizeStarted = false;
            widget.onDurationChangeStarted?.call();
            setState(() {});
            return;
          }
          if (hitId == null && inAudio) {
            _draggingAudio = true;
            _audioDragAnchorX = x;
            _audioDragStartMs = widget.audioOffsetMs;
            widget.onAudioOffsetChangeStarted?.call();
            setState(() {});
            return;
          }

          if (hitId != null) {
            final inGroup = widget.selectedIds.contains(hitId);
            if (inGroup) {
              // A click stays a click. Group dragging starts only after the
              // pointer has crossed [_clickEps].
              _groupAnchorMs = _msFromX(x);
            }
          } else {
            if (widget.selectedIds.isNotEmpty ||
                widget.selectedMarkId != null) {
              widget.onClearSelection?.call();
            }
            _selStartX = x;
            _selEndX = x;
            setState(() {});
          }
        },

        onPointerMove: (ev) {
          final movedEnough =
              _pointerDownPx != null &&
              (_pointerDownPx! - ev.localPosition).distance > _clickEps;

          if (_resizingDuration) {
            final anchor = _durationResizeAnchorX ?? ev.localPosition.dx;
            if (!_durationResizeStarted &&
                (ev.localPosition.dx - anchor).abs() <= _clickEps) {
              return;
            }
            _durationResizeStarted = true;
            widget.onDurationChanged?.call(
              math.max(1, ev.localPosition.dx / widget.pxPerMs),
            );
          } else if (_draggingAudio) {
            final deltaMs =
                (ev.localPosition.dx - _audioDragAnchorX) / widget.pxPerMs;
            final maximum = math.max(
              0,
              widget.durationMs - widget.audioDurationMs,
            );
            widget.onAudioOffsetChanged?.call(
              (_audioDragStartMs + deltaMs).clamp(0, maximum).toDouble(),
            );
          } else if (_groupDragging) {
            _groupAnchorMs ??= _msFromX(ev.localPosition.dx);
            final desired = _msFromX(ev.localPosition.dx) - _groupAnchorMs!;
            final (minD, maxD) = _allowedGroupDeltaRange();
            _groupDeltaMs = desired.clamp(minD, maxD);
            setState(() {});
          } else if (_selStartX != null) {
            _selEndX = ev.localPosition.dx;
            setState(() {});
          } else if (_downHitId != null &&
              movedEnough &&
              widget.selectedIds.contains(_downHitId)) {
            _groupDragging = true;
            _groupAnchorMs ??= _msFromX(_pointerDownPx!.dx);
            final desired = _msFromX(ev.localPosition.dx) - _groupAnchorMs!;
            final (minD, maxD) = _allowedGroupDeltaRange();
            _groupDeltaMs = desired.clamp(minD, maxD);
            setState(() {});
          }
        },

        onPointerUp: (ev) {
          if (_resizingDuration || _draggingAudio) {
            if (_resizingDuration) widget.onDurationChangeEnded?.call();
            if (_draggingAudio) widget.onAudioOffsetChangeEnded?.call();
            _resetPointerInteraction();
            setState(() {});
            return;
          }
          final hadGroupDrag = _groupDragging;
          final hadRect = _selStartX != null && _selEndX != null;
          final wasClickLike =
              _pointerDownPx != null &&
              (_pointerDownPx! - ev.localPosition).distance <= _clickEps;

          final hitIdAtUp = _hitTestMarkId(ev.localPosition.dx);

          if (hadGroupDrag) {
            widget.onGroupDragCommit?.call(_groupDeltaMs);
          } else if (hadRect) {
            if (wasClickLike) {
              if (hitIdAtUp != null) {
                widget.onMarkTapId?.call(hitIdAtUp);
              } else {
                widget.onClearSelection?.call();
                if (widget.seekTrigger == SeekTrigger.up) {
                  widget.onTapOrDragTo(_msFromX(ev.localPosition.dx));
                }
              }
            } else {
              final fromMs = _msFromX(_selStartX!);
              final toMs = _msFromX(_selEndX!);
              widget.onSelectRange?.call(fromMs, toMs);
            }
          } else {
            if (wasClickLike) {
              if (hitIdAtUp != null) {
                widget.onMarkTapId?.call(hitIdAtUp);
              } else {
                widget.onClearSelection?.call();
                if (widget.seekTrigger == SeekTrigger.up) {
                  widget.onTapOrDragTo(_msFromX(ev.localPosition.dx));
                }
              }
            }
          }

          // сброс
          _resetPointerInteraction();
          setState(() {});
        },
        onPointerCancel: (_) {
          if (_resizingDuration) widget.onDurationChangeEnded?.call();
          if (_draggingAudio) widget.onAudioOffsetChangeEnded?.call();
          _resetPointerInteraction();
          setState(() {});
        },

        child: CustomPaint(
          painter: TimelinePainter(
            waveColor: Colors.black12,
            durationMs: widget.durationMs,
            positionMs: widget.positionMs,
            marks: widget.marks,
            peaks: widget.peaks,
            audioDurationMs: widget.audioDurationMs,
            audioOffsetMs: widget.audioOffsetMs,
            audioLabel: widget.audioLabel,
            pxPerMs: widget.pxPerMs,
            bgColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            markerColor: Theme.of(context).colorScheme.primary,
            playheadColor: Theme.of(context).colorScheme.tertiary,
            textColor: Theme.of(context).colorScheme.onSurface,

            getImageSrcForLabel: widget.getImageSrcForLabel,
            missingImageColor: widget.missingImageColor,
            colorTextWhenMissing: widget.colorTextWhenMissing,

            // визуал
            draggingId: _draggingId,
            draggingMs: _draggingMs,
            draggingBarColor: widget.draggingBarColor,
            groupDragging: _groupDragging,
            groupDeltaMs: _groupDeltaMs,
            selectedIds: widget.selectedIds,

            selectionFromX: (_selStartX != null && _selEndX != null)
                ? math.max(0.0, math.min(_selStartX!, _selEndX!))
                : null,
            selectionToX: (_selStartX != null && _selEndX != null)
                ? math.max(_selStartX!, _selEndX!)
                : null,
            selectionOutlineColor: widget.selectionOutlineColor,
            selectionFillColor: widget.selectionFillColor,
          ),
        ),
      ),
    );
  }
}

class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.durationMs,
    required this.positionMs,
    required this.marks,
    required this.bgColor,
    required this.markerColor,
    required this.playheadColor,
    required this.textColor,
    required this.pxPerMs,
    this.peaks,
    required this.audioDurationMs,
    required this.audioOffsetMs,
    this.audioLabel,
    required this.waveColor,

    this.getImageSrcForLabel,
    required this.missingImageColor,
    required this.colorTextWhenMissing,

    this.draggingId,
    this.draggingMs,
    required this.draggingBarColor,

    required this.selectedIds,
    this.groupDragging = false,
    this.groupDeltaMs = 0.0,
    required this.selectionFromX,
    required this.selectionToX,
    required this.selectionOutlineColor,
    required this.selectionFillColor,
  });

  final String? Function(String? label)? getImageSrcForLabel;
  final Color missingImageColor;
  final bool colorTextWhenMissing;

  final String? draggingId;
  final double? draggingMs;
  final Color draggingBarColor;

  final Set<String> selectedIds;
  final bool groupDragging;
  final double groupDeltaMs;

  final Color selectionOutlineColor;
  final Color selectionFillColor;

  final double durationMs;
  final double positionMs;
  final List<ClipMark> marks;
  final double pxPerMs; // ← масштаб
  final List<double>? peaks;
  final double audioDurationMs;
  final double audioOffsetMs;
  final String? audioLabel;
  final Color bgColor, markerColor, playheadColor, textColor, waveColor;

  final double? selectionFromX;
  final double? selectionToX;
  static const lockedColor = Color(0xFFE65100);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 ||
        size.height <= 0 ||
        !pxPerMs.isFinite ||
        pxPerMs <= 0) {
      return;
    }

    // фон
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(r, Paint()..color = bgColor);

    final animationRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 2, size.width, 30),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      animationRect,
      Paint()..color = markerColor.withValues(alpha: 0.14),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - 4, 2, 4, 30),
      Paint()..color = markerColor,
    );
    _paintTrackLabel(canvas, 'ANIMATION  ${durationMs.round()} ms', 8, 9);

    final audioLeft = (audioOffsetMs * pxPerMs)
        .clamp(0.0, size.width)
        .toDouble();
    final audioWidth = (audioDurationMs * pxPerMs)
        .clamp(0.0, math.max(0.0, size.width - audioLeft))
        .toDouble();
    final audioRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(audioLeft, 38, audioWidth, size.height - 64),
      const Radius.circular(6),
    );
    if (audioWidth > 0) {
      canvas.drawRRect(
        audioRect,
        Paint()..color = waveColor.withValues(alpha: 0.24),
      );
      _paintTrackLabel(
        canvas,
        'AUDIO  ${audioLabel ?? ''}',
        audioLeft.toDouble() + 8,
        42,
      );
    }

    // волна
    if (peaks != null && peaks!.isNotEmpty) {
      _paintPeaks(canvas, audioRect.outerRect);
    }

    _paintLockedRanges(canvas, size);

    // метки
    const markerW = 4.0;
    const pad = 4.0;
    final markerTop = 20.0;
    final markerBottom = size.height - pad;

    for (final m in marks) {
      double xMs;
      if (draggingId != null && draggingMs != null && m.id == draggingId) {
        xMs = draggingMs!;
      } else if (groupDragging && selectedIds.contains(m.id)) {
        xMs = (m.startMs + groupDeltaMs).clamp(0.0, durationMs);
      } else {
        xMs = m.startMs;
      }
      final x = (xMs * pxPerMs).clamp(0.0, size.width);

      final hasImage = () {
        final src = getImageSrcForLabel?.call(m.label);
        return src != null && src.trim().isNotEmpty;
      }();

      final baseBar = m.lockedSequenceId != null
          ? lockedColor
          : (draggingId != null && m.id == draggingId)
          ? draggingBarColor
          : (hasImage ? safeColor(m.color, markerColor) : missingImageColor);

      final labelColor = (hasImage || !colorTextWhenMissing)
          ? safeColor(m.color, textColor)
          : missingImageColor;

      final label = (m.label?.isNotEmpty == true)
          ? _ellipsis(m.label!, 12)
          : '';
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 11,
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 100);
        final textX = (x - tp.width / 2)
            .clamp(0.0, math.max(0.0, size.width - tp.width))
            .toDouble();
        tp.paint(canvas, Offset(textX, size.height - 18));
      }

      final rect = Rect.fromLTWH(
        x - markerW / 2,
        markerTop,
        markerW,
        markerBottom - markerTop,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rrect, Paint()..color = baseBar);

      if (selectedIds.contains(m.id)) {
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = selectionOutlineColor;
        canvas.drawRRect(rrect.inflate(1), stroke);
      }
    }

    // плейхед
    final phX = (positionMs * pxPerMs).clamp(0.0, size.width);
    canvas.drawRect(
      Rect.fromLTWH(phX - 1, 0, 2, size.height),
      Paint()..color = playheadColor,
    );

    // рамка
    if (selectionFromX != null && selectionToX != null) {
      final left = selectionFromX!.clamp(0.0, size.width);
      final right = selectionToX!.clamp(0.0, size.width);
      if (right > left) {
        final rr = RRect.fromRectAndRadius(
          Rect.fromLTRB(left, 0, right, size.height),
          const Radius.circular(2),
        );
        final fill = Paint()..color = selectionFillColor;
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = selectionOutlineColor;
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, stroke);
      }
    }
  }

  // ⬇️ ВНЕ paint
  void _paintTrackLabel(Canvas canvas, String text, double x, double y) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 220);
    painter.paint(canvas, Offset(x, y));
  }

  void _paintPeaks(Canvas canvas, Rect rect) {
    final data = peaks!;
    if (data.isEmpty || rect.width <= 0 || rect.height <= 0) return;

    final w = rect.width.toInt();
    final mid = rect.center.dy;
    final amp = rect.height * 0.36;

    final n = data.length;
    final paintWave = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..isAntiAlias = false;

    for (int x = 0; x < w; x++) {
      final t = x / w;
      final idx = (t * (n - 1)).round().clamp(0, n - 1);
      final vRaw = data[idx];

      final v = vRaw.isNaN ? 0.0 : vRaw.clamp(0.0, 1.0);
      final y0 = (mid - v * amp).clamp(rect.top, rect.bottom);
      final y1 = (mid + v * amp).clamp(rect.top, rect.bottom);
      canvas.drawLine(
        Offset(rect.left + x, y0),
        Offset(rect.left + x, y1),
        paintWave,
      );
    }
  }

  void _paintLockedRanges(Canvas canvas, Size size) {
    var index = 0;
    while (index < marks.length) {
      if (marks[index].lockedSequenceId == null) {
        index++;
        continue;
      }
      final startIndex = index;
      while (index + 1 < marks.length &&
          marks[index + 1].lockedSequenceId != null) {
        index++;
      }
      final endIndex = index;
      final startX = (marks[startIndex].startMs * pxPerMs)
          .clamp(0.0, size.width)
          .toDouble();
      final endMs = endIndex + 1 < marks.length
          ? marks[endIndex + 1].startMs
          : durationMs;
      final endX = (endMs * pxPerMs).clamp(startX, size.width).toDouble();
      final rect = Rect.fromLTRB(startX, 18, endX, size.height - 20);
      canvas.drawRect(
        rect,
        Paint()..color = lockedColor.withValues(alpha: 0.10),
      );
      canvas.drawRect(
        Rect.fromLTWH(startX, 18, math.max(2, endX - startX), 3),
        Paint()..color = lockedColor,
      );
      if (endX - startX >= 52) {
        final label = TextPainter(
          text: const TextSpan(
            text: 'LOCKED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: lockedColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(startX + 4, 22));
      }
      index++;
    }
  }

  Color safeColor(dynamic value, Color fallback) {
    if (value == null) return fallback;
    if (value is int) return Color(value);
    if (value is num) return Color(value.toInt());
    return fallback;
  }

  String _ellipsis(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  @override
  bool shouldRepaint(covariant TimelinePainter old) {
    return old.durationMs != durationMs ||
        old.positionMs != positionMs ||
        !identical(old.marks, marks) ||
        old.bgColor != bgColor ||
        old.markerColor != markerColor ||
        old.playheadColor != playheadColor ||
        old.textColor != textColor ||
        old.pxPerMs != pxPerMs ||
        !listEquals(old.peaks, peaks) ||
        old.audioDurationMs != audioDurationMs ||
        old.audioOffsetMs != audioOffsetMs ||
        old.audioLabel != audioLabel ||
        old.waveColor != waveColor ||
        old.getImageSrcForLabel != getImageSrcForLabel ||
        old.missingImageColor != missingImageColor ||
        old.colorTextWhenMissing != colorTextWhenMissing ||
        old.draggingId != draggingId ||
        old.draggingMs != draggingMs ||
        old.draggingBarColor != draggingBarColor ||
        old.groupDragging != groupDragging ||
        old.groupDeltaMs != groupDeltaMs ||
        old.selectionFromX != selectionFromX ||
        old.selectionToX != selectionToX ||
        old.selectionOutlineColor != selectionOutlineColor ||
        old.selectionFillColor != selectionFillColor ||
        !setEquals(old.selectedIds, selectedIds);
  }
}
