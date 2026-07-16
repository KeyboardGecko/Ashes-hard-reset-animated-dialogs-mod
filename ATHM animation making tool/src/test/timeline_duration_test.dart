import 'package:animaker/features/audio_marks/application/timeline_duration.dart';
import 'package:animaker/features/audio_marks/domain/entities/clip_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resize minimum follows selected choices, not longest alternatives', () {
    final marks = [
      ClipMark(
        startMs: 0,
        durationMs: 2500,
        durationChoicesMs: [2500, 4000, 5400, 6000],
      ),
      ClipMark(startMs: 2500, durationMs: 125),
    ];

    expect(selectedTrackEndMs(marks), 2625);
  });

  test('explicit duration is a minimum and never truncates a longer pass', () {
    expect(
      effectiveTimelineDurationMs(
        selectedTrackEndMs: 6125,
        explicitMinimumMs: 3000,
      ),
      6125,
    );
    expect(
      effectiveTimelineDurationMs(
        selectedTrackEndMs: 2625,
        explicitMinimumMs: 3000,
      ),
      3000,
    );
  });

  test('audio end is also part of the effective timeline', () {
    expect(
      effectiveTimelineDurationMs(
        selectedTrackEndMs: 1000,
        explicitMinimumMs: 1200,
        audioEndMs: 1800,
      ),
      1800,
    );
  });
}
