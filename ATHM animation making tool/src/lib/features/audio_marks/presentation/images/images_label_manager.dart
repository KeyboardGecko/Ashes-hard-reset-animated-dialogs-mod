// lib/features/audio_marks/presentation/images/label_images_manager.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../application/label_images_io.dart';
import '../../domain/services/label_image_service.dart';

class LabelImagesManager extends StatelessWidget {
  const LabelImagesManager({super.key, required this.imgSvc});
  final LabelImageService imgSvc;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: AnimatedBuilder(
        animation: imgSvc,
        builder: (_, __) {
          // соберём список ключей (гарантированно добавим тайл для "без лейбла")
          final entries = <MapEntry<String, String?>>[];
          entries.add(MapEntry(imgSvc.kNoLabelKey, imgSvc.defaultImage));
          entries.addAll(
            imgSvc.map.entries.where((e) => e.key != imgSvc.kNoLabelKey),
          );

          return SizedBox(
            width: 560,
            height: 420,
            child: Column(
              children: [
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          exportLabelImagesSettings(context, imgSvc: imgSvc),
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('Export settings'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          importLabelImagesSettings(context, imgSvc: imgSvc),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import settings'),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Add or replace the image for "no label"',
                      onPressed: () async {
                        final chosen = await imgSvc.pickImage();
                        if (chosen != null) imgSvc.defaultImage = chosen;
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    itemCount: entries.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.0, // квадрат
                        ),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final key = e.key;
                      final src = e.value;

                      return _Tile(
                        label: key == imgSvc.kNoLabelKey ? '(no label)' : key,
                        src: src,
                        onPick: () async {
                          final chosen = await imgSvc.pickImage();
                          if (chosen != null) {
                            imgSvc.setImageForLabel(
                              key == imgSvc.kNoLabelKey ? null : key,
                              chosen,
                            );
                          }
                        },
                        onClear: () {
                          if (key == imgSvc.kNoLabelKey) {
                            imgSvc.defaultImage = null;
                          } else {
                            imgSvc.clearImageForLabel(key);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.src,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? src;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ip = _imageProviderFor(src);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPick,
        onLongPress: onClear,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ip == null
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                    ),
                    child: ip == null
                        ? const Center(
                            child: Opacity(
                              opacity: 0.5,
                              child: Icon(Icons.image_outlined, size: 32),
                            ),
                          )
                        : Image(image: ip, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.touch_app, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Tap: change · Long press: clear',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Унифицированный провайдер картинок:
/// - data: URL → MemoryImage
/// - file path (desktop) → FileImage
/// - http/https → NetworkImage
// ↓ исправленная функция
ImageProvider? _imageProviderFor(String? src) {
  if (src == null || src.isEmpty) return null;

  // data: URL → MemoryImage
  if (src.startsWith('data:image/')) {
    final i = src.indexOf(',');
    if (i > 0) {
      try {
        return MemoryImage(base64Decode(src.substring(i + 1)));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // http/https → NetworkImage
  if (src.startsWith('http://') || src.startsWith('https://')) {
    return NetworkImage(src);
  }

  // остальное считаем локальным файлом (desktop/mobile) → FileImage
  if (!kIsWeb) {
    try {
      return FileImage(File(src));
    } catch (_) {
      return null;
    }
  }

  // на Web для локального пути ничего сделать нельзя
  return null;
}
