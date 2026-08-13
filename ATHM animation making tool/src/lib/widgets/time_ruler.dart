import 'package:flutter/material.dart';

class TimeRuler extends StatelessWidget {
  final double totalDurationMs;
  final double pxPerMs;

  const TimeRuler({
    super.key,
    required this.totalDurationMs,
    required this.pxPerMs,
  });

  @override
  Widget build(BuildContext context) {
    final totalWidth = totalDurationMs * pxPerMs;

    return SizedBox(
      width: totalWidth,
      height: 30,
      child: CustomPaint(painter: _TimeRulerPainter(totalDurationMs, pxPerMs)),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  final double totalDurationMs;
  final double pxPerMs;

  _TimeRulerPainter(this.totalDurationMs, this.pxPerMs);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final height = size.height;

    const majorStepMs = 1000; // каждая 1000мс = 1с
    const minorStepMs = 100; // деления каждые 100мс

    final totalMs = totalDurationMs.ceil();

    for (int ms = 0; ms <= totalMs; ms += 1) {
      final x = ms * pxPerMs;

      if (ms % majorStepMs == 0) {
        // длинная линия и подпись
        canvas.drawLine(Offset(x, 0), Offset(x, height), paint);

        final label = '${(ms / 1000).toStringAsFixed(1)}s';
        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(fontSize: 10, color: Colors.white),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 0));
      } else if (ms % minorStepMs == 0) {
        // короткая линия
        canvas.drawLine(Offset(x, height - 8), Offset(x, height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
