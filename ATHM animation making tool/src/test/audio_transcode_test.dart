import 'dart:io';
import 'dart:typed_data';

import 'package:animaker/features/audio_marks/application/audio_transcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wav/wav_file.dart';

void main() {
  test('reads duration directly from a stopped-player WAV source', () async {
    final directory = await Directory.systemTemp.createTemp('athm_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}one_second.wav';
    await Wav([Float64List(8000)], 8000).writeFile(path);

    expect(await readWavDurationMs(path), closeTo(1000, 0.01));
  });

  test('Windows prefers FFmpeg bundled beside the Animaker executable', () {
    final executable = p.join('C:', 'Animaker', 'animaker.exe');
    final expected = p.join('C:', 'Animaker', 'data', 'tools', 'ffmpeg.exe');

    expect(
      resolveFfmpegExecutable(
        executablePath: executable,
        isWindows: true,
        fileExists: (path) => p.equals(path, expected),
      ),
      expected,
    );
  });

  test('Windows falls back to PATH when bundled FFmpeg is absent', () {
    expect(
      resolveFfmpegExecutable(
        executablePath: p.join('C:', 'Animaker', 'animaker.exe'),
        isWindows: true,
        fileExists: (_) => false,
      ),
      'ffmpeg',
    );
  });

  test('Windows finds FFmpeg in the Flutter project during development', () {
    final project = p.join('D:', 'Projects', 'Animaker');
    final executable = p.join(
      project,
      'build',
      'windows',
      'x64',
      'runner',
      'Debug',
      'animaker.exe',
    );
    final expected = p.join(
      project,
      'windows',
      'third_party',
      'ffmpeg',
      'bin',
      'ffmpeg.exe',
    );

    expect(
      resolveFfmpegExecutable(
        executablePath: executable,
        workingDirectory: p.join('D:', 'Elsewhere'),
        isWindows: true,
        fileExists: (path) => p.equals(path, expected),
      ),
      expected,
    );
  });

  test('non-Windows platforms keep the configured command', () {
    expect(
      resolveFfmpegExecutable(isWindows: false, fallback: 'custom-ffmpeg'),
      'custom-ffmpeg',
    );
  });
}
