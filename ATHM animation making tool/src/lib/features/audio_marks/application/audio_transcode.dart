// lib/features/audio_marks/application/audio_transcode.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wav/wav_file.dart';

String resolveFfmpegExecutable({
  String? executablePath,
  String fallback = 'ffmpeg',
  bool? isWindows,
  bool Function(String path)? fileExists,
  String? workingDirectory,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (!windows) return fallback;

  final applicationPath = executablePath ?? Platform.resolvedExecutable;
  final bundled = p.join(
    p.dirname(applicationPath),
    'data',
    'tools',
    'ffmpeg.exe',
  );
  final exists = fileExists ?? ((path) => File(path).existsSync());
  if (exists(bundled)) return bundled;

  final sourceRoots = <String>[workingDirectory ?? Directory.current.path];
  var ancestor = p.dirname(applicationPath);
  for (var i = 0; i < 10; i++) {
    sourceRoots.add(ancestor);
    final parent = p.dirname(ancestor);
    if (p.equals(parent, ancestor)) break;
    ancestor = parent;
  }
  for (final root in sourceRoots) {
    final sourceBundle = p.join(
      root,
      'windows',
      'third_party',
      'ffmpeg',
      'bin',
      'ffmpeg.exe',
    );
    if (exists(sourceBundle)) return sourceBundle;
  }
  return fallback;
}

Future<String> ensureWavForPlayback(
  String input, {
  String? ffmpegExe,
  Directory? outDir, // 👈 вот этот параметр нужен
}) async {
  if (p.extension(input).toLowerCase() == '.wav') return input;

  final dir = outDir ?? Directory(p.dirname(input));
  final out = p.join(dir.path, '${p.basenameWithoutExtension(input)}.wav');

  final executable = ffmpegExe ?? resolveFfmpegExecutable();
  ProcessResult res;
  try {
    res = await Process.run(executable, [
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
  } on ProcessException catch (error) {
    throw Exception(
      'FFmpeg could not be started at "$executable". '
      'Rebuild Animaker with the bundled Windows tool. $error',
    );
  }
  if (res.exitCode != 0) {
    throw Exception('FFmpeg failed (${res.exitCode}): ${res.stderr}');
  }
  return out;
}

Future<double> readWavDurationMs(String path) async {
  final wav = await Wav.readFile(path);
  return wav.duration * 1000;
}
