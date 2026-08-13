import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LabelImageSlot extends StatelessWidget {
  final String? label;
  final String? src;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const LabelImageSlot({
    super.key,
    required this.label,
    required this.src,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // фон/превью
            if (src == null)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined),
              )
            else if (kIsWeb && src!.startsWith('data:image/'))
              Image.network(src!, fit: BoxFit.cover)
            else
              Image.file(File(src!), fit: BoxFit.cover),

            // оверлей с действиями
            Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.08),
                child: InkWell(
                  onTap: onPick,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.upload_file, size: 18),
                          color: Colors.white,
                          onPressed: onPick,
                          tooltip: 'Add pic',
                        ),
                        if (src != null && onClear != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.clear, size: 18),
                            color: Colors.white,
                            onPressed: onClear,
                            tooltip: 'Remove pic',
                          ),
                      ],
                    ),
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
