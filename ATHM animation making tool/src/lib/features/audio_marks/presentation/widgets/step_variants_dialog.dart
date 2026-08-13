import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StepVariantsResult {
  const StepVariantsResult({
    required this.frames,
    required this.durationsMs,
    required this.selectedFrameIndex,
    required this.selectedDurationIndex,
  });

  final List<String> frames;
  final List<double> durationsMs;
  final int selectedFrameIndex;
  final int selectedDurationIndex;
}

class StepVariantsDialog extends StatefulWidget {
  const StepVariantsDialog({
    super.key,
    required this.frames,
    required this.durationsMs,
    required this.selectedFrameIndex,
    required this.selectedDurationIndex,
  });

  final List<String> frames;
  final List<double> durationsMs;
  final int selectedFrameIndex;
  final int selectedDurationIndex;

  @override
  State<StepVariantsDialog> createState() => _StepVariantsDialogState();
}

class _StepVariantsDialogState extends State<StepVariantsDialog> {
  late final List<TextEditingController> _frames;
  late final List<TextEditingController> _durations;
  late int _selectedFrame;
  late int _selectedDuration;
  String? _error;

  @override
  void initState() {
    super.initState();
    _frames = widget.frames
        .map((value) => TextEditingController(text: value))
        .toList();
    _durations = widget.durationsMs
        .map((value) => TextEditingController(text: _formatNumber(value)))
        .toList();
    if (_frames.isEmpty) _frames.add(TextEditingController(text: 'FRAME'));
    if (_durations.isEmpty) {
      _durations.add(TextEditingController(text: '100'));
    }
    _selectedFrame = widget.selectedFrameIndex.clamp(0, _frames.length - 1);
    _selectedDuration = widget.selectedDurationIndex.clamp(
      0,
      _durations.length - 1,
    );
  }

  @override
  void dispose() {
    for (final controller in [..._frames, ..._durations]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Step variants'),
      content: SizedBox(
        width: 720,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the variant used by the editor preview. All variants remain random in LANGUAGE_ANIM.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _VariantColumn(
                      title: 'Frame variants',
                      children: [
                        for (var index = 0; index < _frames.length; index++)
                          _variantRow(
                            selected: index == _selectedFrame,
                            onSelected: () =>
                                setState(() => _selectedFrame = index),
                            controller: _frames[index],
                            hint: 'FRAME',
                            onDelete: _frames.length == 1
                                ? null
                                : () => _removeFrame(index),
                          ),
                      ],
                      onAdd: () => setState(() {
                        _frames.add(TextEditingController(text: 'FRAME'));
                        _selectedFrame = _frames.length - 1;
                      }),
                    ),
                  ),
                  const VerticalDivider(width: 24),
                  Expanded(
                    child: _VariantColumn(
                      title: 'Duration variants',
                      children: [
                        for (var index = 0; index < _durations.length; index++)
                          _variantRow(
                            selected: index == _selectedDuration,
                            onSelected: () =>
                                setState(() => _selectedDuration = index),
                            controller: _durations[index],
                            hint: '100',
                            suffix: 'ms',
                            numeric: true,
                            onDelete: _durations.length == 1
                                ? null
                                : () => _removeDuration(index),
                          ),
                      ],
                      onAdd: () => setState(() {
                        _durations.add(TextEditingController(text: '100'));
                        _selectedDuration = _durations.length - 1;
                      }),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }

  Widget _variantRow({
    required bool selected,
    required VoidCallback onSelected,
    required TextEditingController controller,
    required String hint,
    String? suffix,
    bool numeric = false,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Use in editor preview',
            onPressed: onSelected,
            icon: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              inputFormatters: numeric
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                  : null,
              decoration: InputDecoration(
                hintText: hint,
                suffixText: suffix,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete variant',
            onPressed: onDelete,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }

  void _removeFrame(int index) {
    setState(() {
      _frames.removeAt(index).dispose();
      if (index < _selectedFrame) {
        _selectedFrame--;
      } else if (_selectedFrame >= _frames.length) {
        _selectedFrame = _frames.length - 1;
      }
    });
  }

  void _removeDuration(int index) {
    setState(() {
      _durations.removeAt(index).dispose();
      if (index < _selectedDuration) {
        _selectedDuration--;
      } else if (_selectedDuration >= _durations.length) {
        _selectedDuration = _durations.length - 1;
      }
    });
  }

  void _apply() {
    final frames = _frames.map((value) => value.text.trim()).toList();
    if (frames.any((value) => value.isEmpty)) {
      setState(() => _error = 'Frame names cannot be empty.');
      return;
    }
    final durations = _durations
        .map((value) => double.tryParse(value.text.trim()))
        .toList();
    if (durations.any(
      (value) =>
          value == null || !value.isFinite || value <= 0 || value > 60000,
    )) {
      setState(() => _error = 'Durations must be between 0 and 60000 ms.');
      return;
    }
    Navigator.pop(
      context,
      StepVariantsResult(
        frames: frames,
        durationsMs: durations.cast<double>(),
        selectedFrameIndex: _selectedFrame,
        selectedDurationIndex: _selectedDuration,
      ),
    );
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _VariantColumn extends StatelessWidget {
  const _VariantColumn({
    required this.title,
    required this.children,
    required this.onAdd,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(child: ListView(children: children)),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add variant'),
        ),
      ],
    );
  }
}
