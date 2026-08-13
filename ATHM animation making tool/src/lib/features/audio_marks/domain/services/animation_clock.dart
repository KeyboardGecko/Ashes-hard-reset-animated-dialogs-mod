import 'dart:async';

import 'package:flutter/scheduler.dart';

class AnimationClock {
  AnimationClock({required TickerProvider vsync, double durationMs = 1000})
    : _durationMs = durationMs.clamp(1, double.infinity).toDouble() {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _cycleController = StreamController<int>.broadcast();

  double _durationMs;
  double _positionMs = 0;
  double _rate = 1;
  bool _playing = false;
  bool _loop = false;
  Duration _lastElapsed = Duration.zero;
  int _cycle = 0;

  Duration get duration => Duration(milliseconds: _durationMs.round());
  Duration get position => Duration(milliseconds: _positionMs.round());
  bool get playing => _playing;
  double get rate => _rate;
  bool get loop => _loop;
  int get cycle => _cycle;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<int> get cycleStream => _cycleController.stream;

  void setDurationMs(double value) {
    _durationMs = value.clamp(1, double.infinity).toDouble();
    if (_positionMs > _durationMs) {
      _positionMs = _durationMs;
      _emitPosition();
    }
    _durationController.add(duration);
  }

  void setLooping(bool value) => _loop = value;

  void setRate(double value) => _rate = value.clamp(0.25, 2.0).toDouble();

  void seekMs(double value) {
    _positionMs = value.clamp(0, _durationMs).toDouble();
    _emitPosition();
  }

  void stepMs(int delta) => seekMs(_positionMs + delta);

  void playOrPause() => _playing ? pause() : play();

  void play() {
    if (_playing) return;
    if (_positionMs >= _durationMs) {
      _positionMs = 0;
      _nextCycle();
      _emitPosition();
    }
    _playing = true;
    _lastElapsed = Duration.zero;
    _ticker.start();
    _playingController.add(true);
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _ticker.stop();
    _lastElapsed = Duration.zero;
    _playingController.add(false);
  }

  void _tick(Duration elapsed) {
    final deltaUs = elapsed.inMicroseconds - _lastElapsed.inMicroseconds;
    _lastElapsed = elapsed;
    if (deltaUs <= 0) return;
    _positionMs += deltaUs / 1000 * _rate;

    if (_positionMs >= _durationMs) {
      if (_loop) {
        _positionMs %= _durationMs;
        _nextCycle();
      } else {
        _positionMs = _durationMs;
        pause();
      }
    }
    _emitPosition();
  }

  void _nextCycle() {
    _cycle++;
    _cycleController.add(_cycle);
  }

  void _emitPosition() => _positionController.add(position);

  Future<void> dispose() async {
    _ticker.dispose();
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _cycleController.close();
  }
}
