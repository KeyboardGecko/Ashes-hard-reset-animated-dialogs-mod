import 'package:animaker/features/audio_marks/application/forced_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextGridPhoneParser', () {
    test('reads the phones tier from a long TextGrid', () {
      const source = '''
File type = "ooTextFile"
Object class = "TextGrid"

item [1]:
    class = "IntervalTier"
    name = "words"
    intervals: size = 1
    intervals [1]:
        xmin = 0
        xmax = 0.2
        text = "me"
item [2]:
    class = "IntervalTier"
    name = "phones"
    intervals: size = 2
    intervals [1]:
        xmin = 0
        xmax = 0.08
        text = "m"
    intervals [2]:
        xmin = 0.08
        xmax = 0.2
        text = "i"
''';

      final phones = const TextGridPhoneParser().parse(source);

      expect(phones, hasLength(2));
      expect(phones.first.phone, 'm');
      expect(phones.first.startMs, 0);
      expect(phones.first.endMs, 80);
      expect(phones.last.phone, 'i');
      expect(phones.last.endMs, 200);
    });
  });

  group('AthmVisemeTrackBuilder', () {
    test('maps, merges and smooths phones into editable ATHM marks', () {
      final result = const AthmVisemeTrackBuilder().build(
        prefix: 'VNC',
        phones: const [
          AlignedPhone(startMs: 0, endMs: 100, phone: 'sil'),
          AlignedPhone(startMs: 100, endMs: 160, phone: 'p'),
          AlignedPhone(startMs: 160, endMs: 190, phone: 'b'),
          AlignedPhone(startMs: 190, endMs: 210, phone: 's'),
          AlignedPhone(startMs: 210, endMs: 400, phone: 'oʊ'),
        ],
      );

      expect(result.marks.map((mark) => mark.label), [
        'VNCDEF',
        'VNCM',
        'VNCO',
      ]);
      expect(result.marks.map((mark) => mark.startMs), [0, 60, 210]);
      expect(result.durationMs, 400);
    });

    test('normalizes Russian palatalization and reports unknown phones', () {
      final result =
          const AthmVisemeTrackBuilder(
            minimumPoseDurationMs: 0,
            closedMouthLeadMs: 0,
          ).build(
            prefix: 'RU',
            phones: const [
              AlignedPhone(startMs: 0, endMs: 100, phone: 'mʲ'),
              AlignedPhone(startMs: 100, endMs: 200, phone: 'ɕː'),
              AlignedPhone(startMs: 200, endMs: 300, phone: 'q'),
            ],
          );

      expect(result.marks.map((mark) => mark.label), ['RUM', 'RUS', 'RUN']);
      expect(result.unmappedPhones, ['q']);
    });

    test('rejects generated names beyond the ATHM frame limit', () {
      expect(
        () => const AthmVisemeTrackBuilder().build(
          prefix: 'LONG',
          phones: const [AlignedPhone(startMs: 0, endMs: 100, phone: 'sil')],
        ),
        throwsFormatException,
      );
    });
  });
}
