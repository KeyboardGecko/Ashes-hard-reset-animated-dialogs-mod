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

  test('shrinking past the last frame end trims that frame', () {
    final result = resizeTimelineEnd(
      source: [
        ClipMark(startMs: 0, durationMs: 100),
        ClipMark(startMs: 100, durationMs: 400),
      ],
      requestedDurationMs: 250,
      audioEndMs: 200,
    );

    expect(result.durationMs, 250);
    expect(result.marks.last.durationMs, 150);
    expect(selectedTrackEndMs(result.marks), 250);
  });

  test('extending after a trim creates an empty tail', () {
    final trimmed = [
      ClipMark(startMs: 0, durationMs: 100),
      ClipMark(startMs: 100, durationMs: 150),
    ];
    final result = resizeTimelineEnd(
      source: trimmed,
      requestedDurationMs: 700,
      audioEndMs: 200,
    );

    expect(result.durationMs, 700);
    expect(result.marks.last.durationMs, 150);
    expect(selectedTrackEndMs(result.marks), 250);
  });

  test('trimming updates only the selected duration variant', () {
    final result = resizeTimelineEnd(
      source: [
        ClipMark(
          startMs: 100,
          durationMs: 400,
          durationChoicesMs: [200, 400, 800],
          selectedDurationChoiceIndex: 1,
        ),
      ],
      requestedDurationMs: 300,
    );

    expect(result.marks.single.durationMs, 200);
    expect(result.marks.single.durationChoicesMs, [200, 200, 800]);
  });
}
