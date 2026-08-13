import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../application/forced_alignment.dart';

class MfaLipSyncDialog extends StatefulWidget {
  const MfaLipSyncDialog({
    super.key,
    required this.audioPath,
    required this.initialPrefix,
    this.service = const MfaForcedAlignmentService(),
  });

  final String audioPath;
  final String initialPrefix;
  final MfaForcedAlignmentService service;

  @override
  State<MfaLipSyncDialog> createState() => _MfaLipSyncDialogState();
}

class _MfaLipSyncDialogState extends State<MfaLipSyncDialog> {
  late final TextEditingController _prefixController;
  final TextEditingController _transcriptController = TextEditingController();
  MfaLanguage _language = MfaLanguage.english;
  double _minimumPoseDurationMs = 50;
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _prefixController = TextEditingController(text: widget.initialPrefix);
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Preparing portable MFA...';
    });
    try {
      final result = await widget.service.align(
        audioPath: widget.audioPath,
        transcript: _transcriptController.text,
        prefix: _prefixController.text,
        language: _language,
        minimumPoseDurationMs: _minimumPoseDurationMs,
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_fix_high_outlined),
          SizedBox(width: 10),
          Text('Generate lipsync with MFA'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                p.basename(widget.audioPath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _transcriptController,
                minLines: 4,
                maxLines: 9,
                autofocus: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Exact spoken transcript',
                  alignLabelWithHint: true,
                  helperText:
                      'Write numbers and substitutions as they are actually spoken.',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prefixController,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Character prefix',
                        hintText: 'VNC',
                        helperText: 'Produces VNCDEF, VNCM, VNCS…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<MfaLanguage>(
                      initialValue: _language,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Language',
                      ),
                      items: MfaLanguage.values
                          .map(
                            (language) => DropdownMenuItem(
                              value: language,
                              child: Text(language.label),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _language = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Minimum pose duration: '
                '${_minimumPoseDurationMs.toStringAsFixed(0)} ms',
              ),
              Slider(
                value: _minimumPoseDurationMs,
                min: 20,
                max: 100,
                divisions: 16,
                label: '${_minimumPoseDurationMs.toStringAsFixed(0)} ms',
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _minimumPoseDurationMs = value),
              ),
              const SizedBox(height: 8),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.download_for_offline_outlined),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ATHM uses its bundled Micromamba. On first use it '
                          'downloads the MFA runtime and the selected language '
                          'model; later runs reuse the local installation.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _status ?? 'Working...',
                  key: const ValueKey('mfa-progress-status'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Generate and replace track'),
        ),
      ],
    );
  }
}
