import 'dart:io';

import 'package:animaker/features/language_anim/data/language_anim_codec.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/migrate_language_anim.dart <source> [output]',
    );
    exitCode = 64;
    return;
  }

  final sourceFile = File(arguments.first);
  if (!await sourceFile.exists()) {
    stderr.writeln('File not found: ${sourceFile.path}');
    exitCode = 66;
    return;
  }

  const codec = LanguageAnimCodec();
  final source = await sourceFile.readAsString();
  final document = codec.decode(source);
  final outputFile = File(arguments.length == 2 ? arguments[1] : arguments[0]);
  if (outputFile.path == sourceFile.path) {
    await sourceFile.copy('${sourceFile.path}.legacy.bak');
  }
  await outputFile.writeAsString(codec.encode(document));
  stdout.writeln(
    'Migrated ${document.characters.length} characters to ATHM v4: ${outputFile.path}',
  );
}
