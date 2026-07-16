import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/clip_mark.dart';
import '../../application/label_images_io.dart';
import '../../domain/services/label_image_service.dart';

class LabelImagesPanel extends StatelessWidget {
  const LabelImagesPanel({
    super.key,
    required this.imgSvc,
    required this.marksListenable,
  });

  final LabelImageService imgSvc;
  final ValueListenable<List<ClipMark>> marksListenable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: AnimatedBuilder(
        animation: imgSvc as Listenable, // слушаем изменения картинок
        builder: (_, __) {
          return ValueListenableBuilder<List<ClipMark>>(
            valueListenable: marksListenable, // слушаем новые лейблы из меток
            builder: (_, marks, __) {
              // множество лейблов из проекта
              final labelsFromMarks = <String>{};
              for (final m in marks) {
                final lab = (m.label ?? '').trim();
                labelsFromMarks.add(lab); // '' = no-label
              }

              // объединяем: (лейблы из меток) ∪ (ключи из imgSvc.map) ∪ (ключ no-label)
              final keys = <String>{imgSvc.kNoLabelKey};
              keys.addAll(
                labelsFromMarks.map((s) => s.isEmpty ? imgSvc.kNoLabelKey : s),
              );
              keys.addAll(imgSvc.map.keys);

              final entries =
                  keys
                      .where((k) => k.isNotEmpty) // защита
                      .toList()
                    ..sort((a, b) {
                      // "(no label)" первым
                      if (a == imgSvc.kNoLabelKey) return -1;
                      if (b == imgSvc.kNoLabelKey) return 1;
                      return a.toLowerCase().compareTo(b.toLowerCase());
                    });

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Label images',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Export settings',
                            child: IconButton(
                              icon: const Icon(Icons.upload_outlined),
                              onPressed: () => exportLabelImagesSettings(
                                context,
                                imgSvc: imgSvc,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Import settings',
                            child: IconButton(
                              icon: const Icon(Icons.download_outlined),
                              onPressed: () => importLabelImagesSettings(
                                context,
                                imgSvc: imgSvc,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: GridView.builder(
                          physics: const ClampingScrollPhysics(),
                          itemCount: entries.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 1.0, // квадрат
                              ),
                          itemBuilder: (_, i) {
                            final key = entries[i];
                            final display = key == imgSvc.kNoLabelKey
                                ? '(no label)'
                                : key;
                            final src = key == imgSvc.kNoLabelKey
                                ? imgSvc.defaultImage
                                : imgSvc.map[key];
                            return _Tile(
                              label: display,
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
                ),
              );
            },
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
    final ip = _imageProviderFromSrc(src);
    final radius = BorderRadius.circular(10);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick, // тап по тайлу — выбрать/заменить изображение
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Картинка / плейсхолдер
            if (ip != null)
              Image(image: ip, fit: BoxFit.cover)
            else
              Center(
                child: Opacity(
                  opacity: .5,
                  child: Icon(
                    Icons.image_outlined,
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),

            // Жёлтый чип с лейблом (сверху-слева)
            Positioned(
              left: 6,
              top: 6,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),

            // Кнопка-«крестик» очистки (снизу-справа)
            Positioned(
              right: 6,
              bottom: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.38),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear, // очистить связь лейбл ↔ картинка
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ImageProvider? _imageProviderFromSrc(String? src) {
  if (src == null || src.isEmpty) return null;

  if (src.startsWith('data:image/')) {
    final comma = src.indexOf(',');
    if (comma > 0) {
      try {
        return MemoryImage(base64Decode(src.substring(comma + 1)));
      } catch (_) {}
    }
    return null;
  }
  if (src.startsWith('http://') || src.startsWith('https://')) {
    return NetworkImage(src);
  }
  if (!kIsWeb) {
    return FileImage(File(src));
  }
  return null;
}
