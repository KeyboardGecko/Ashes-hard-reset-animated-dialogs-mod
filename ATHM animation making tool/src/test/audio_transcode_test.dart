import 'dart:io';
import 'dart:typed_data';

import 'package:animaker/features/audio_marks/application/audio_transcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wav/wav_file.dart';

void main() {
  test('reads duration directly from a stopped-player WAV source', () async {
    final directory = await Directory.systemTemp.createTemp('athm_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}one_second.wav';
    await Wav([Float64List(8000)], 8000).writeFile(path);

    expect(await readWavDurationMs(path), closeTo(1000, 0.01));
  });
}
