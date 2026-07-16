// lib/features/audio_marks/application/audio_transcode.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wav/wav_file.dart';

Future<String> ensureWavForPlayback(
  String input, {
  String ffmpegExe = 'ffmpeg',
  Directory? outDir, // 👈 вот этот параметр нужен
}) async {
  if (p.extension(input).toLowerCase() == '.wav') return input;

  final dir = outDir ?? Directory(p.dirname(input));
  final out = p.join(dir.path, '${p.basenameWithoutExtension(input)}.wav');

  final res = await Process.run(ffmpegExe, [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    input,
    '-acodec',
    'pcm_s16le',
    out,
  ]);
  if (res.exitCode != 0) {
    throw Exception('FFmpeg failed: ${res.stderr}');
  }
  return out;
}

Future<double> readWavDurationMs(String path) async {
  final wav = await Wav.readFile(path);
  return wav.duration * 1000;
}
