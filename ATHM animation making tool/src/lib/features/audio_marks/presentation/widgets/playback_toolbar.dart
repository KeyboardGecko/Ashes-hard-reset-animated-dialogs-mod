import 'package:flutter/material.dart';

class PlaybackToolbar extends StatelessWidget {
  final bool enabled;
  final bool isPlaying;
  final double rate;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onAddMarkAtPlayhead;

  const PlaybackToolbar({
    super.key,
    required this.enabled,
    required this.isPlaying,
    required this.rate,
    required this.onTogglePlay,
    required this.onRateChanged,
    required this.onAddMarkAtPlayhead,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: onTogglePlay,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            label: Text(isPlaying ? 'Pause' : 'Play'),
          ),
          DropdownButton<double>(
            value: rate,
            items: const [
              DropdownMenuItem(value: 0.5, child: Text('0.5x')),
              DropdownMenuItem(value: 0.75, child: Text('0.75x')),
              DropdownMenuItem(value: 1.0, child: Text('1.0x')),
              DropdownMenuItem(value: 1.25, child: Text('1.25x')),
              DropdownMenuItem(value: 1.5, child: Text('1.5x')),
              DropdownMenuItem(value: 2.0, child: Text('2.0x')),
            ],
            onChanged: (v) {
              if (v != null) onRateChanged(v);
            },
          ),
          FilledButton.tonalIcon(
            onPressed: onAddMarkAtPlayhead,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('+ Clipmark'),
          ),
        ],
      ),
    );
  }
}
