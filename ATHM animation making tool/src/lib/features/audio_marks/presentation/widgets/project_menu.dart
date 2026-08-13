import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class ProjectMenu extends StatelessWidget {
  const ProjectMenu({
    super.key,
    required this.currentLanguagePath,
    required this.currentAnimationName,
    required this.hasUnsavedAnimation,
    required this.onNew,
    required this.onOpen,
    required this.onSaveAnimation,
    required this.onSaveAs,
    required this.onAddCharacter,
    required this.onAddAnimation,
    required this.onOpenSettings,
  });

  final String? currentLanguagePath;
  final String? currentAnimationName;
  final bool hasUnsavedAnimation;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback? onSaveAnimation;
  final VoidCallback? onSaveAs;
  final VoidCallback? onAddCharacter;
  final VoidCallback? onAddAnimation;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Project',
      onSelected: (value) {
        switch (value) {
          case 'new':
            onNew();
            return;
          case 'open':
            onOpen();
            return;
          case 'save_animation':
            onSaveAnimation?.call();
            return;
          case 'save_as':
            onSaveAs?.call();
            return;
          case 'add_character':
            onAddCharacter?.call();
            return;
          case 'add_animation':
            onAddAnimation?.call();
            return;
          case 'settings':
            onOpenSettings();
            return;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'new',
          child: ListTile(
            leading: Icon(Icons.note_add_outlined),
            title: Text('New LANGUAGE_ANIM'),
          ),
        ),
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Open LANGUAGE_ANIM'),
          ),
        ),
        if (currentLanguagePath != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(p.basename(currentLanguagePath!)),
              subtitle: Text(p.dirname(currentLanguagePath!)),
            ),
          ),
          PopupMenuItem(
            value: 'save_animation',
            enabled: onSaveAnimation != null,
            child: ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(
                currentAnimationName == null
                    ? 'Save animation'
                    : 'Save $currentAnimationName${hasUnsavedAnimation ? ' *' : ''}',
              ),
            ),
          ),
          PopupMenuItem(
            value: 'save_as',
            enabled: onSaveAs != null,
            child: const ListTile(
              leading: Icon(Icons.save_as_outlined),
              title: Text('Save LANGUAGE_ANIM as...'),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'add_character',
            enabled: onAddCharacter != null,
            child: const ListTile(
              leading: Icon(Icons.person_add_alt_1_outlined),
              title: Text('Add character'),
            ),
          ),
          PopupMenuItem(
            value: 'add_animation',
            enabled: onAddAnimation != null,
            child: const ListTile(
              leading: Icon(Icons.add_to_queue_outlined),
              title: Text('Add animation'),
            ),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
          ),
        ),
      ],
      icon: const Icon(Icons.menu),
    );
  }
}
