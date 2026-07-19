import '../domain/entities/clip_mark.dart';

class OptionalAudioFitResult {
  const OptionalAudioFitResult({
    required this.marks,
    required this.extensionMs,
  });

  final List<ClipMark> marks;
  final double extensionMs;
}

OptionalAudioFitResult fitOptionalAudioGroup({
  required List<ClipMark> marks,
  required String groupId,
  required double audioDurationMs,
}) {
  if (marks.isEmpty || audioDurationMs <= 0) {
    return OptionalAudioFitResult(
      marks: List<ClipMark>.from(marks),
      extensionMs: 0,
    );
  }

  final indices = <int>[
    for (var i = 0; i < marks.length; i++)
      if (marks[i].lockedSequenceId == groupId) i,
  ];
  if (indices.isEmpty) {
    return OptionalAudioFitResult(
      marks: List<ClipMark>.from(marks),
      extensionMs: 0,
    );
  }

  var minimumBlockDurationMs = 0.0;
  for (final index in indices) {
    final mark = marks[index];
    final choices = mark.durationChoicesMs;
    if (choices != null && choices.isNotEmpty) {
      minimumBlockDurationMs += choices.reduce(
        (minimum, value) => value < minimum ? value : minimum,
      );
    } else {
      minimumBlockDurationMs += mark.durationMs ?? 100.0;
    }
  }

  final first = marks[indices.first];
  final requiredDurationMs = first.optionalSoundOffsetMs + audioDurationMs;
  final extensionMs = requiredDurationMs - minimumBlockDurationMs;
  if (extensionMs <= 0.001) {
    return OptionalAudioFitResult(
      marks: List<ClipMark>.from(marks),
      extensionMs: 0,
    );
  }

  final result = List<ClipMark>.from(marks);
  final lastIndex = indices.last;
  final last = result[lastIndex];
  final originalChoices =
      last.durationChoicesMs ?? <double>[last.durationMs ?? 100.0];
  final extendedChoices = originalChoices
      .map((duration) => duration + extensionMs)
      .toList();
  final selectedIndex = last.selectedDurationChoiceIndex.clamp(
    0,
    extendedChoices.length - 1,
  );
  result[lastIndex] = last.copyWith(
    durationMs: extendedChoices[selectedIndex],
    durationChoicesMs: extendedChoices,
  );

  for (var i = lastIndex + 1; i < result.length; i++) {
    result[i] = result[i].copyWith(startMs: result[i].startMs + extensionMs);
  }

  return OptionalAudioFitResult(marks: result, extensionMs: extensionMs);
}
