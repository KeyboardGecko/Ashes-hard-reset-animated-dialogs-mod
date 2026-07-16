import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class ClipEntry {
  final String image;
  final double startMs;
  final String label;

  ClipEntry({required this.image, required this.startMs, required this.label});

  Map<String, dynamic> toJson() => {
    "image": image,
    "startMs": startMs,
    "label": label,
  };
}

// Rhubarb → ваши обозначения визем
const Map<String, String> visemeMap = {
  "A": "m",
  "B": "s",
  "C": "e",
  "D": "a",
  "E": "o",
  "G": "f",
  "H": "f",
  "X": "",
};

String convertRhubarbToJson(
  String rhubarbText, {
  String audio = "",
  String defaultImage = "",
  String Function(String label)? imageForLabel,
}) {
  final lines = rhubarbText.split(RegExp(r'\r?\n'));
  final clipList = <ClipEntry>[];

  final lineRegex = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)\s+([A-Za-z])\s*$');

  for (var raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith('//')) continue;

    final m = lineRegex.firstMatch(line);
    if (m == null) continue;

    final seconds = double.parse(m.group(1)!);
    final rhubarbLabel = m.group(2)!;

    final mappedLabel = visemeMap[rhubarbLabel] ?? rhubarbLabel;
    final startMs = seconds * 1000.0;
    final image = imageForLabel?.call(mappedLabel) ?? "";

    clipList.add(ClipEntry(image: image, startMs: startMs, label: mappedLabel));
  }

  clipList.sort((a, b) => a.startMs.compareTo(b.startMs));

  final jsonMap = {
    "version": 1,
    "audio": audio,
    "clips": clipList.map((e) => e.toJson()).toList(),
    "defaultImage": defaultImage,
  };

  return const JsonEncoder.withIndent('  ').convert(jsonMap);
}

class ConvertRhubarbFileButton extends StatelessWidget {
  /// Опционально: путь к аудиофайлу, который попадёт в JSON "audio".
  /// Если пусто — попробуем угадать как <basename>.wav рядом с .txt.
  final String audioPath;

  final String defaultImage;
  final String Function(String label)? imageForLabel;
  final void Function(String json)? onConverted;
  final String buttonText;

  const ConvertRhubarbFileButton({
    super.key,
    this.audioPath = "",
    this.defaultImage = "",
    this.imageForLabel,
    this.onConverted,
    this.buttonText = "Загрузить Rhubarb .txt и конвертировать",
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );
        if (result == null || result.files.single.path == null) return;

        final txtPath = result.files.single.path!;
        final rhubarbText = await File(txtPath).readAsString();

        // Определяем audio для JSON:
        String audioForJson = audioPath;
        if (audioForJson.isEmpty) {
          // пробуем взять <basename>.wav рядом с txt
          final txtFile = File(txtPath);
          final dir = txtFile.parent.path;
          final base = txtFile.uri.pathSegments.last; // e.g., name.txt
          final stem = base.replaceFirst(RegExp(r'\.[^.]+$'), ''); // name
          final guess = File('$dir${Platform.pathSeparator}$stem.wav');
          if (guess.existsSync()) {
            audioForJson = guess.path;
          } else {
            // можно также попробовать .mp3/.flac при желании
            audioForJson = "";
          }
        }

        final json = convertRhubarbToJson(
          rhubarbText,
          audio: audioForJson,
          defaultImage: defaultImage,
          imageForLabel: imageForLabel,
        );

        await Clipboard.setData(ClipboardData(text: json));
        onConverted?.call(json);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Сконвертировано. ${audioForJson.isEmpty ? "(audio не найдено)" : "audio: $audioForJson"}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
      child: Text(buttonText),
    );
  }
}
