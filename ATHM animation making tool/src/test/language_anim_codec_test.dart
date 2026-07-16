import 'package:animaker/features/language_anim/data/language_anim_codec.dart';
import 'package:animaker/features/language_anim/domain/language_anim_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = LanguageAnimCodec();

  test('v3 track supports random choices and locked sequences', () {
    final track = codec.decodeTrack(
      'JMDEF@292;[JMEEE@169;JMS@161];(JMEE|JME)@(82|100)',
    );

    expect(track, hasLength(3));
    expect(track[1], isA<AthmLockedSequence>());
    final random = (track[2] as AthmSegmentEntry).segment;
    expect(random.frameChoices, ['JMEE', 'JME']);
    expect(random.durationChoicesMs, [82, 100]);
    expect(
      codec.encodeTrack(track),
      'JMDEF@292;[JMEEE@169;JMS@161];(JMEE|JME)@(82|100)',
    );
  });

  test('v3 document round-trips', () {
    const source = '''
[default]
ATHM_FORMAT = "3";
ATHM_CHARACTERS = "JM";
ATHM_JM_ANIMATIONS = "IDLE,JM001";
ATHM_JM_VOICE_MATCH = "JM*";
ATHM_JM_BACKGROUND = "JM_BG";
ATHM_JM_IDLE_TRACK = "(JMDEF|JMBLNK)@(1000|2000)";
ATHM_JM_IDLE_LOOP = "true";
ATHM_JM_IDLE_DURATION_MS = "500";
ATHM_JM_JM001_TRACK = "JMDEF@292;[JMEEE@169;JMS@161]";
ATHM_JM_JM001_LOOP = "false";
ATHM_JM_JM001_DURATION_MS = "900";
ATHM_JM_JM001_SOUND = "voices/JM001";
ATHM_JM_JM001_SOUND_OFFSET_MS = "125";
''';

    final first = codec.decode(source);
    final second = codec.decode(codec.encode(first));

    expect(second.formatVersion, 3);
    expect(second.characters.single.id, 'JM');
    expect(second.characters.single.animations, hasLength(2));
    expect(second.characters.single.animations.first.durationMs, 500);
    expect(second.characters.single.voiceMatches, ['JM*']);
    expect(second.characters.single.animations.last.sound, 'voices/JM001');
    expect(second.characters.single.animations.last.durationMs, 900);
    expect(second.characters.single.animations.last.soundOffsetMs, 125);
    expect(
      second.characters.single.animations.last.track[1],
      isA<AthmLockedSequence>(),
    );
  });

  test('legacy document is migrated to v3 model', () {
    const source = '''
[default]
ANIMS_JM_LIST = "IDLE,JM001";
ANIMS_MAP_LIST = "JM";
ANIMS_MAP_JM = "JM";
ANIMS_JM_IDLE_FRAMES = "JMDEF,(JMSML,JMBLNK)";
ANIMS_JM_IDLE_DURS = "(1000,2000),125";
ANIMS_JM_IDLE_LOOP = "true";
ANIMS_JM_JM001_FRAMES = "JMDEF,JMEEE,JMS";
ANIMS_JM_JM001_DURS = "292,169,161";
ANIMS_JM_JM001_LOOP = "false";
''';

    final document = codec.decode(source);

    expect(document.wasMigratedFromLegacy, isTrue);
    final character = document.characters.single;
    expect(character.id, 'JM');
    expect(character.voiceMatches, ['JM*']);
    expect(character.animations, hasLength(2));
    expect(character.animations.first.loop, isTrue);
    expect(character.animations.first.segments.last.frameChoices, [
      'JMSML',
      'JMBLNK',
    ]);
    expect(character.animations.last.previewDurationMs, 622);
  });

  test('rejects unsupported explicit format versions', () {
    expect(
      () => codec.decode('ATHM_FORMAT = "2";'),
      throwsA(isA<LanguageAnimFormatException>()),
    );
  });

  test('rejects ambiguous sound ownership', () {
    const source = '''
ATHM_FORMAT = "3";
ATHM_CHARACTERS = "A,B";
ATHM_A_ANIMATIONS = "IDLE,A01";
ATHM_A_IDLE_TRACK = "ADEF@1000";
ATHM_A_A01_TRACK = "ADEF@100";
ATHM_A_A01_SOUND = "shared";
ATHM_B_ANIMATIONS = "IDLE,B01";
ATHM_B_IDLE_TRACK = "BDEF@1000";
ATHM_B_B01_TRACK = "BDEF@100";
ATHM_B_B01_SOUND = "shared";
''';
    expect(
      () => codec.decode(source),
      throwsA(isA<LanguageAnimFormatException>()),
    );
  });

  test('rejects excessive segment duration', () {
    expect(
      () => codec.decodeTrack('JMDEF@60001'),
      throwsA(isA<LanguageAnimFormatException>()),
    );
  });
}
