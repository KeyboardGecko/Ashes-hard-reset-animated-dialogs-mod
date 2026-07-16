import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wav/wav_file.dart';
import 'package:path/path.dart' as p;

// ====== Инлайновый редактор для label ======
class InlineLabelEditor extends StatefulWidget {
  const InlineLabelEditor({
    super.key,
    required this.initial,
    required this.onChangedCommitted,
    this.hint,
    this.focusNode, // NEW
    this.autofocus = false, // NEW
    this.selectAllOnFocus = true, // NEW
  });

  final String initial;
  final String? hint;
  final ValueChanged<String> onChangedCommitted;

  final FocusNode? focusNode; // NEW
  final bool autofocus; // NEW
  final bool selectAllOnFocus; // NEW

  @override
  State<InlineLabelEditor> createState() => InlineLabelEditorState();
}

class InlineLabelEditorState extends State<InlineLabelEditor> {
  late final TextEditingController _ctl;
  FocusNode? _localFocus; // создаём, если внешний не передан
  FocusNode get _fn => widget.focusNode ?? (_localFocus ??= FocusNode());

  bool _didSelectAllThisFocus = false;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initial);
    _fn.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant InlineLabelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    // если поменяли внешний focusNode — перевесим слушатель
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _localFocus)?.removeListener(_onFocusChange);
      _fn.addListener(_onFocusChange);
    }

    // если initial снаружи обновился — синхронизируем контроллер
    if (oldWidget.initial != widget.initial && _ctl.text != widget.initial) {
      _ctl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _fn.removeListener(_onFocusChange);
    _ctl.dispose();
    // освобождаем только локальный узел
    _localFocus?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_fn.hasFocus) {
      if (widget.selectAllOnFocus && !_didSelectAllThisFocus) {
        _didSelectAllThisFocus = true;
        // выделим текст в следующий кадр, когда курсор уже внутри
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ctl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _ctl.text.length,
          );
        });
      }
    } else {
      _didSelectAllThisFocus = false;
      _commitAndRefocus();
    }
  }

  void _commitAndRefocus() {
    widget.onChangedCommitted(_ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 60, maxWidth: 150),
        child: TextField(
          controller: _ctl,
          focusNode: _fn, // NEW
          autofocus: widget.autofocus, // NEW
          maxLines: 1,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            hintText: widget.hint,
          ),
          onSubmitted: (_) => _commitAndRefocus(),
        ),
      ),
    );
  }
}

Future<List<double>?> computePeaksFromWavFile(
  String path, {
  required int buckets,
}) async {
  final wav = await Wav.readFile(path);
  return _peaksFromWav(wav, buckets: buckets);
}

/// Вариант для Web, когда у FilePicker есть только bytes.
Future<List<double>?> computePeaksFromWavBytes(
  Uint8List bytes, {
  required int buckets,
}) async {
  final wav = Wav.read(bytes);
  return _peaksFromWav(wav, buckets: buckets);
}

List<double> _peaksFromWav(Wav wav, {required int buckets}) {
  // wav.channels: List<Float64List> — значения в -1..1
  final channels = wav.channels;
  final n = channels.isNotEmpty ? channels[0].length : 0;
  if (n == 0 || buckets <= 0) return const [];

  // шаг по сэмплам на одно ведро
  final step = (n / buckets).ceil();
  final peaks = <double>[];
  for (int i = 0; i < n; i += step) {
    final end = (i + step < n) ? i + step : n;
    double maxAbs = 0.0;
    for (int j = i; j < end; j++) {
      double sampleAbsMax = 0.0;
      for (final ch in channels) {
        final a = ch[j].abs();
        if (a > sampleAbsMax) sampleAbsMax = a;
      }
      if (sampleAbsMax > maxAbs) maxAbs = sampleAbsMax;
    }
    // clamp защитно и добавляем
    peaks.add(maxAbs.clamp(0.0, 1.0));
  }
  return peaks;
}

Future<List<double>?> computePeaksFromOggFileIO(
  String oggPath, {
  required int buckets,
  required Future<List<double>?> Function(
    String wavPath, {
    required int buckets,
  })
  computePeaksFromWavFile,
}) async {
  final dir = p.dirname(oggPath);
  final tmp = p.join(dir, '${p.basenameWithoutExtension(oggPath)}.__tmp__.wav');

  final result = await Process.run('ffmpeg', [
    '-y',
    '-i',
    oggPath,
    '-vn',
    '-ac',
    '1',
    '-ar',
    '44100',
    '-acodec',
    'pcm_s16le',
    tmp,
  ]);

  if (result.exitCode != 0) {
    throw ProcessException(
      'ffmpeg',
      ['-i', oggPath],
      result.stderr?.toString() ??
          'ffmpeg failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }

  try {
    final peaks = await computePeaksFromWavFile(tmp, buckets: buckets);
    return peaks; // без !
  } finally {
    if (await File(tmp).exists()) {
      await File(tmp).delete();
    }
  }
}

ImageProvider? imageProviderFor(String? src) {
  if (src == null || src.isEmpty) return null;

  if (src.startsWith('data:image/')) {
    final i = src.indexOf(',');
    if (i <= 0) return null;
    final b64 = src.substring(i + 1);
    try {
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  if (kIsWeb) {
    // На web пусть будет NetworkImage (или верни null, если не URL)
    return NetworkImage(src);
  }

  final f = File(src);
  if (!f.existsSync()) return null;
  return FileImage(f);
}
