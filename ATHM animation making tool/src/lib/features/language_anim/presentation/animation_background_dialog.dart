import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/language_anim_models.dart';

enum AnimationBackgroundSelectionType {
  inherit,
  setCharacter,
  none,
  custom,
  import,
}

class AnimationBackgroundSelection {
  const AnimationBackgroundSelection(this.type, [this.name]);

  final AnimationBackgroundSelectionType type;
  final String? name;
}

class AnimationBackgroundDialog extends StatefulWidget {
  const AnimationBackgroundDialog({
    super.key,
    required this.candidatesByName,
    required this.currentValue,
    this.inheritedName,
    this.allowInherit = true,
    this.title = 'Animation background',
  });

  final Map<String, String> candidatesByName;
  final String? currentValue;
  final String? inheritedName;
  final bool allowInherit;
  final String title;

  @override
  State<AnimationBackgroundDialog> createState() =>
      _AnimationBackgroundDialogState();
}

class _AnimationBackgroundDialogState extends State<AnimationBackgroundDialog> {
  String _query = '';

  bool _isSelected(String? value) {
    final current = widget.currentValue?.trim().toLowerCase();
    return current == value?.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final candidates =
        widget.candidatesByName.entries
            .where((entry) => entry.key.toLowerCase().contains(query))
            .toList()
          ..sort(
            (left, right) =>
                left.key.toLowerCase().compareTo(right.key.toLowerCase()),
          );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          children: [
            if (widget.allowInherit)
              ListTile(
                leading: const Icon(Icons.wallpaper_outlined),
                title: const Text('Set character background'),
                subtitle: Text('Current: ${widget.inheritedName ?? 'none'}'),
                onTap: () => Navigator.pop(
                  context,
                  const AnimationBackgroundSelection(
                    AnimationBackgroundSelectionType.setCharacter,
                  ),
                ),
              ),
            if (widget.allowInherit) const Divider(),
            if (widget.allowInherit)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Inherit character background'),
                subtitle: Text(
                  widget.inheritedName ?? 'No character background',
                ),
                trailing: widget.currentValue == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(
                  context,
                  const AnimationBackgroundSelection(
                    AnimationBackgroundSelectionType.inherit,
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.hide_image_outlined),
              title: const Text('None'),
              subtitle: Text(
                widget.allowInherit
                    ? 'Draw the animation without a background'
                    : 'Do not define a default background for this character',
              ),
              trailing:
                  _isSelected(AthmAnimation.noBackground) ||
                      (!widget.allowInherit && widget.currentValue == null)
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(
                context,
                const AnimationBackgroundSelection(
                  AnimationBackgroundSelectionType.none,
                ),
              ),
            ),
            const Divider(),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Find image',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: candidates.isEmpty
                  ? const Center(child: Text('No matching images'))
                  : ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final entry = candidates[index];
                        return ListTile(
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: Image.file(
                              File(entry.value),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          title: Text(entry.key),
                          subtitle: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _isSelected(entry.key)
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            AnimationBackgroundSelection(
                              AnimationBackgroundSelectionType.custom,
                              entry.key,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(
            context,
            const AnimationBackgroundSelection(
              AnimationBackgroundSelectionType.import,
            ),
          ),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Import image…'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
