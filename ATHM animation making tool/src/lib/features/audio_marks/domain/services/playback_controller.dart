import 'package:media_kit/media_kit.dart';
import 'dart:async';

class PlaybackController {
  final Player _player = Player();
  double _rate = 1.0;

  // Expose state
  Player get raw => _player; // если нужно прямое API
  Duration get duration => _player.state.duration;
  Duration get position => _player.state.position;
  bool get playing => _player.state.playing;
  double get rate => _rate;

  // Streams
  Stream<Duration> get durationStream => _player.stream.duration;
  Stream<Duration> get positionStream => _player.stream.position;
  Stream<bool> get playingStream => _player.stream.playing;

  Future<void> openPath(String pathOrName) async {
    await _player.stop();
    await _player.open(Media(pathOrName), play: false);
  }

  Future<Duration> waitForDuration({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = _player.state.duration;
      if (current > Duration.zero) return current;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return _player.state.duration;
  }

  Future<void> playOrPause() => _player.playOrPause();
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seekMs(double ms) =>
      _player.seek(Duration(milliseconds: ms.round()));
  Future<void> stepMs(int delta) async {
    final pos = _player.state.position.inMilliseconds;
    final dur = _player.state.duration.inMilliseconds;
    final next = (pos + delta).clamp(0, dur);
    await _player.seek(Duration(milliseconds: next));
  }

  Future<void> setRate(double v) async {
    _rate = v.clamp(0.25, 2.0);
    await _player.setRate(_rate);
  }

  Future<void> setLooping(bool enabled) => _player.setPlaylistMode(
    enabled ? PlaylistMode.single : PlaylistMode.none,
  );

  Future<void> dispose() async {
    await _player.dispose();
  }
}
