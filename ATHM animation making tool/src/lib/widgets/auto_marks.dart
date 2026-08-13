import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fftea/fftea.dart';

/// Кнопка: выбрать WAV → посчитать авто-метки → отдать наружу в мс.
class AutoMarkButton extends StatelessWidget {
  final String buttonText;
  final void Function(List<double> marksMs) onMarksReady;

  /// Настройки детекции
  final double windowMs; // окно анализа, мс (например 20)
  final double hopMs; // шаг окна, мс (например 10)
  final double threshold; // порог пиков [0..1] (например 0.35)
  final int minSeparationMs; // минимальный интервал между метками
  final int smoothFrames; // сглаживание огибающей (скользящее среднее)

  const AutoMarkButton({
    super.key,
    required this.onMarksReady,
    this.buttonText = 'Авторазметка по аудио (WAV)',
    this.windowMs = 20,
    this.hopMs = 10,
    this.threshold = 0.35,
    this.minSeparationMs = 80,
    this.smoothFrames = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['wav'],
        );
        if (res == null || res.files.single.path == null) return;

        try {
          final bytes = await File(res.files.single.path!).readAsBytes();
          final wav = _parseWav(bytes);
          final marks = _detectMarks(
            samples: wav.samples,
            sampleRate: wav.sampleRate,
            windowMs: windowMs,
            hopMs: hopMs,
            threshold: threshold,
            minSeparationMs: minSeparationMs,
            smoothFrames: smoothFrames,
          );
          onMarksReady(marks);

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Метки: ${marks.length} шт.')));
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Ошибка авторазметки: $e')));
        }
      },
      child: Text(buttonText),
    );
  }
}

/// --- WAV PARSER (PCM 16-bit, mono/stereo) ---

class _WavData {
  final Float64List samples; // mono, [-1..1]
  final int sampleRate;
  _WavData(this.samples, this.sampleRate);
}

_WavData _parseWav(Uint8List data) {
  // Очень простой парсер RIFF/WAVE PCM16. Без лишних зависимостей.
  final b = ByteData.sublistView(data);

  // Проверки заголовков
  String tag(int off) => String.fromCharCodes(data.sublist(off, off + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw 'Не WAV/RIFF файл';
  }

  int offset = 12;
  int? audioFormat;
  int? numChannels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  while (offset + 8 <= data.length) {
    final chunkId = tag(offset);
    final chunkSize = b.getUint32(offset + 4, Endian.little);
    final chunkDataOff = offset + 8;

    if (chunkId == 'fmt ') {
      audioFormat = b.getUint16(chunkDataOff, Endian.little);
      numChannels = b.getUint16(chunkDataOff + 2, Endian.little);
      sampleRate = b.getUint32(chunkDataOff + 4, Endian.little);
      bitsPerSample = b.getUint16(chunkDataOff + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataOff;
      dataSize = chunkSize;
    }

    offset = chunkDataOff + chunkSize;
    if (offset.isOdd) offset += 1; // выравнивание
  }

  if (audioFormat != 1) throw 'Поддерживается только PCM (audioFormat=1)';
  if (numChannels == null || sampleRate == null || bitsPerSample == null) {
    throw 'Некорректный WAV fmt';
  }
  if (bitsPerSample != 16) throw 'Поддерживается только 16-бит PCM';
  if (dataOffset == null || dataSize == null) {
    throw 'Нет data-чанка';
  }

  final bytesPerSample = bitsPerSample ~/ 8;
  final frames = dataSize ~/ (bytesPerSample * numChannels);
  final mono = Float64List(frames);

  int p = dataOffset;
  for (int i = 0; i < frames; i++) {
    double sum = 0.0;
    for (int ch = 0; ch < numChannels; ch++) {
      final s = b.getInt16(p, Endian.little) / 32768.0;
      p += 2;
      sum += s;
    }
    mono[i] = sum / numChannels;
  }

  return _WavData(mono, sampleRate);
}

/// --- Детекция меток ---
/// Комбинируем нормализованную RMS-энергию и спектральную новизну (flux),
/// сглаживаем, ищем пики выше порога и с минимальным интервалом.
List<double> _detectMarks({
  required Float64List samples,
  required int sampleRate,
  double windowMs = 20,
  double hopMs = 10,
  double threshold = 0.35,
  int minSeparationMs = 80,
  int smoothFrames = 3,
}) {
  final win = math.max(32, (windowMs * sampleRate / 1000).round());
  final hop = math.max(16, (hopMs * sampleRate / 1000).round());
  final nFrames = ((samples.length - win) / hop).floor() + 1;

  // RMS
  final rms = Float64List(nFrames);
  for (int i = 0; i < nFrames; i++) {
    int start = i * hop;
    double sum2 = 0.0;
    for (int j = 0; j < win; j++) {
      final v = samples[start + j];
      sum2 += v * v;
    }
    rms[i] = math.sqrt(sum2 / win);
  }
  _minMaxNormInPlace(rms);

  // Спектральная новизна (flux)
  final fftLen = _nextPow2(win);
  final fft = FFT(fftLen);
  final lastMag = Float64List(fftLen ~/ 2);
  final flux = Float64List(nFrames);

  // Предварительное окно Хэннинга
  final hann = List<double>.generate(
    win,
    (i) => 0.5 * (1 - math.cos(2 * math.pi * i / (win - 1))),
  );

  for (int i = 0; i < nFrames; i++) {
    int start = i * hop;
    final buf = List<double>.filled(fftLen, 0.0);
    for (int j = 0; j < win; j++) {
      buf[j] = samples[start + j] * hann[j];
    }
    final spec = fft.realFft(buf).magnitudes();

    double sumPos = 0.0;
    for (int k = 0; k < spec.length; k++) {
      final d = spec[k] - lastMag[k];
      if (d > 0) sumPos += d;
      lastMag[k] = spec[k];
    }
    flux[i] = sumPos;
  }
  _minMaxNormInPlace(flux);

  // Комбинированная новизна
  final novelty = Float64List(nFrames);
  for (int i = 0; i < nFrames; i++) {
    novelty[i] = 0.5 * (rms[i] + flux[i]);
  }

  // Сглаживание (скользящее среднее)
  if (smoothFrames > 1) {
    final sm = Float64List(novelty.length);
    final R = smoothFrames;
    for (int i = 0; i < novelty.length; i++) {
      int a = math.max(0, i - R);
      int b = math.min(novelty.length - 1, i + R);
      double s = 0.0;
      for (int k = a; k <= b; k++) {
        s += novelty[k];
      }
      sm[i] = s / (b - a + 1);
    }
    for (int i = 0; i < novelty.length; i++) {
      novelty[i] = sm[i];
    }
  }

  // Пики
  final peaks = <int>[];
  for (int i = 1; i < novelty.length - 1; i++) {
    if (novelty[i] >= threshold &&
        novelty[i] > novelty[i - 1] &&
        novelty[i] >= novelty[i + 1]) {
      peaks.add(i);
    }
  }

  // Преобразуем в мс, учитываем минимальный интервал
  final marksMs = <double>[];
  int minSepFrames = (minSeparationMs / hopMs).round();
  int? lastPeak;
  for (final p in peaks) {
    if (lastPeak == null || (p - lastPeak) >= minSepFrames) {
      final centerSample = p * hop;
      final tMs = centerSample * 1000.0 / sampleRate;
      marksMs.add(tMs);
      lastPeak = p;
    } else {
      // если слишком близко — оставляем более высокий локальный пик
      // (упрощённо: заменим, если текущий новее и выше)
      if (novelty[p] > novelty[lastPeak]) {
        // заменить последнюю метку
        marksMs.removeLast();
        final tMs = p * hop * 1000.0 / sampleRate;
        marksMs.add(tMs);
        lastPeak = p;
      }
    }
  }

  return marksMs;
}

void _minMaxNormInPlace(Float64List v) {
  double minV = double.infinity, maxV = -double.infinity;
  for (final x in v) {
    if (x < minV) minV = x;
    if (x > maxV) maxV = x;
  }
  final d = (maxV - minV).abs();
  if (d <= 1e-12) {
    for (int i = 0; i < v.length; i++) {
      v[i] = 0.0;
    }
  } else {
    for (int i = 0; i < v.length; i++) {
      v[i] = (v[i] - minV) / d;
    }
  }
}

int _nextPow2(int n) {
  int p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}
