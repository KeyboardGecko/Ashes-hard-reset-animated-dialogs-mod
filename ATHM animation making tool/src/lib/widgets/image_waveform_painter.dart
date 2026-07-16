import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ImageWaveformPainter extends CustomPainter {
  final ui.Image image;
  final double playhead;
  final double zoom;
  final double waveformScale;

  ImageWaveformPainter(
    this.image,
    this.playhead, {
    required this.zoom,
    required this.waveformScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintWidth = image.width * zoom * waveformScale;

    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, paintWidth, size.height),
      image: image,
      fit: BoxFit.fill,
    );

    final headPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2;

    final playX = playhead * zoom * waveformScale;
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), headPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
