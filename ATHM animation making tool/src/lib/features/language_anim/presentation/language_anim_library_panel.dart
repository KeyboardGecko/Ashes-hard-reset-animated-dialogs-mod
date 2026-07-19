import 'package:flutter/material.dart';

import '../application/language_anim_workspace.dart';
import '../domain/language_anim_models.dart';

class LanguageAnimLibraryPanel extends StatefulWidget {
  const LanguageAnimLibraryPanel({
    super.key,
    required this.workspace,
    required this.selectedCharacterId,
    required this.selectedAnimationName,
    required this.onSelected,
    required this.onAddCharacter,
    required this.onAddAnimation,
    required this.onSetCharacterBackground,
    required this.onRenameCharacter,
    required this.onDeleteCharacter,
    required this.onRenameAnimation,
    required this.onDeleteAnimation,
    required this.onClose,
  });

  final LanguageAnimWorkspace workspace;
  final String? selectedCharacterId;
  final String? selectedAnimationName;
  final Future<void> Function(AthmCharacter, AthmAnimation) onSelected;
  final Future<void> Function() onAddCharacter;
  final Future<void> Function(AthmCharacter) onAddAnimation;
  final Future<void> Function(AthmCharacter) onSetCharacterBackground;
  final Future<void> Function(AthmCharacter) onRenameCharacter;
  final Future<void> Function(AthmCharacter) onDeleteCharacter;
  final Future<void> Function(AthmCharacter, AthmAnimation) onRenameAnimation;
  final Future<void> Function(AthmCharacter, AthmAnimation) onDeleteAnimation;
  final VoidCallback onClose;

  @override
  State<LanguageAnimLibraryPanel> createState() =>
      _LanguageAnimLibraryPanelState();
}

class _LanguageAnimLibraryPanelState extends State<LanguageAnimLibraryPanel> {
  String _query = '';
  late String _characterId;

  @override
  void initState() {
    super.initState();
    _characterId =
        widget.selectedCharacterId ??
        widget.workspace.document.characters.first.id;
  }

  @override
  void didUpdateWidget(covariant LanguageAnimLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspace.document.characterById(_characterId) == null) {
      _characterId =
          widget.selectedCharacterId ??
          widget.workspace.document.characters.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final characters = widget.workspace.document.characters;
    final character =
        widget.workspace.document.characterById(_characterId) ??
        characters.first;
    final query = _query.trim().toLowerCase();
    final animations = character.animations
        .where((animation) => animation.name.toLowerCase().contains(query))
        .toList();

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Animation library',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close library',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: character.id,
                    decoration: const InputDecoration(
                      labelText: 'Character',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in characters)
                        DropdownMenuItem(value: item.id, child: Text(item.id)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _characterId = value);
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Character actions',
                  onSelected: (value) async {
                    switch (value) {
                      case 'add':
                        await widget.onAddCharacter();
                        return;
                      case 'rename':
                        await widget.onRenameCharacter(character);
                        return;
                      case 'background':
                        await widget.onSetCharacterBackground(character);
                        return;
                      case 'delete':
                        await widget.onDeleteCharacter(character);
                        return;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'add', child: Text('Add character')),
                    PopupMenuItem(
                      value: 'background',
                      child: Text('Set character background'),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename character'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete character'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter animations',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('${animations.length} animations'),
                const Spacer(),
                IconButton(
                  tooltip: 'Add animation to ${character.id}',
                  onPressed: () => widget.onAddAnimation(character),
                  icon: const Icon(Icons.add),
                ),
                if (widget.workspace.document.wasMigratedFromLegacy)
                  const Tooltip(
                    message: 'Legacy file opened in migration mode',
                    child: Badge(label: Text('v1'), child: Icon(Icons.sync)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: animations.isEmpty
                ? const Center(child: Text('No matching animations'))
                : ListView.builder(
                    itemCount: animations.length,
                    itemBuilder: (context, index) {
                      final animation = animations[index];
                      final status = widget.workspace.statusFor(
                        character.id,
                        animation.name,
                      );
                      final selected =
                          widget.selectedCharacterId == character.id &&
                          widget.selectedAnimationName == animation.name;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: _AssetStatusIcon(status: status),
                        title: Text(
                          status.expectsAudio
                              ? animation.name
                              : '${animation.name}  <NOSOUND>',
                        ),
                        subtitle: Text(
                          '${animation.segments.length} frames · '
                          '${animation.previewDurationMs.round()} ms',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (animation.background != null)
                              Tooltip(
                                message: animation.disablesBackground
                                    ? 'Animation background disabled'
                                    : 'Animation background: ${animation.background}',
                                child: Icon(
                                  animation.disablesBackground
                                      ? Icons.hide_image_outlined
                                      : Icons.wallpaper_outlined,
                                  size: 18,
                                ),
                              ),
                            if (animation.track.any(
                              (entry) =>
                                  entry is AthmLockedSequence ||
                                  entry is AthmOptionalLockedSequence,
                            ))
                              Tooltip(
                                message:
                                    animation.track.any(
                                      (entry) =>
                                          entry is AthmOptionalLockedSequence,
                                    )
                                    ? 'Contains random locked sequence'
                                    : 'Contains locked sequence',
                                child: Icon(
                                  animation.track.any(
                                        (entry) =>
                                            entry is AthmOptionalLockedSequence,
                                      )
                                      ? Icons.casino_outlined
                                      : Icons.lock_outline,
                                  size: 18,
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: 'Animation actions',
                              onSelected: (value) async {
                                if (value == 'rename') {
                                  await widget.onRenameAnimation(
                                    character,
                                    animation,
                                  );
                                } else if (value == 'delete') {
                                  await widget.onDeleteAnimation(
                                    character,
                                    animation,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  enabled:
                                      animation.name.toUpperCase() != 'IDLE',
                                  child: const Text('Rename animation'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled:
                                      animation.name.toUpperCase() != 'IDLE',
                                  child: const Text('Delete animation'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => widget.onSelected(character, animation),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssetStatusIcon extends StatelessWidget {
  const _AssetStatusIcon({required this.status});

  final AnimationAssetStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.expectsAudio &&
        status.missingFrames.isEmpty &&
        status.missingBackground == null &&
        status.missingOptionalSounds.isEmpty) {
      return Tooltip(
        message: 'Animation intentionally has no sound',
        child: Icon(
          Icons.volume_off_outlined,
          color: Theme.of(context).colorScheme.secondary,
        ),
      );
    }
    if (status.isComplete) {
      return Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    final details = <String>[
      if (status.expectsAudio && !status.hasAudio) 'sound missing',
      if (status.missingFrames.isNotEmpty)
        '${status.missingFrames.length} images missing',
      if (status.missingBackground != null)
        'background ${status.missingBackground} missing',
      if (status.missingOptionalSounds.isNotEmpty)
        '${status.missingOptionalSounds.length} block sounds missing',
    ].join(', ');
    return Tooltip(
      message: details,
      child: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
