import 'dart:io';

import 'package:animaker/features/audio_marks/application/mfa_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolves the Micromamba executable from the Windows bundle', () {
    final resolved = resolveMicromambaExecutable(
      executablePath: p.join('C:', 'ATHM', 'animaker.exe'),
      isWindows: true,
      fileExists: (path) =>
          path == p.join('C:', 'ATHM', 'data', 'tools', 'micromamba.exe'),
    );

    expect(resolved, p.join('C:', 'ATHM', 'data', 'tools', 'micromamba.exe'));
  });

  test('uses a stable per-user runtime directory', () {
    expect(
      defaultMfaRootDirectory(
        environment: {'LOCALAPPDATA': p.join('C:', 'Users', 'tester', 'Local')},
      ),
      p.join('C:', 'Users', 'tester', 'Local', 'ATHM', 'mfa'),
    );
  });

  test('installs runtime and language models only once', () async {
    final temp = await Directory.systemTemp.createTemp(
      'athm_mfa_runtime_test_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final micromamba = File(p.join(temp.path, 'micromamba.exe'));
    await micromamba.writeAsBytes(const [0]);
    final runner = _FakeMfaProcessRunner();
    final manager = MfaRuntimeManager(
      micromambaExecutable: micromamba.path,
      rootDirectory: p.join(temp.path, 'runtime'),
      processRunner: runner,
    );

    final progress = <String>[];
    await manager.ensureReady(
      'english_mfa',
      languageLabel: 'English',
      onProgress: progress.add,
    );

    expect(runner.commands.first.first, 'create');
    expect(runner.commands.first, contains('kaldi=*=cpu*'));
    final modelCommands = runner.commands
        .where((command) => command.contains('download'))
        .toList();
    expect(modelCommands, hasLength(2));
    expect(modelCommands.first, isNot(contains('--no-capture-output')));
    expect(modelCommands.first.sublist(0, 4), [
      'run',
      '--prefix',
      manager.environmentPrefix,
      'mfa',
    ]);
    expect(runner.commands.last.first, 'clean');
    expect(progress, contains('Downloading the English acoustic model...'));

    final commandCount = runner.commands.length;
    await manager.ensureReady('english_mfa', languageLabel: 'English');
    expect(runner.commands, hasLength(commandCount));
  });
}

class _FakeMfaProcessRunner extends MfaProcessRunner {
  final List<List<String>> commands = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    commands.add(List<String>.from(arguments));
    if (arguments.first == 'create' || arguments.first == 'install') {
      final prefix = arguments[arguments.indexOf('--prefix') + 1];
      final binDirectory = Directory(
        p.join(prefix, Platform.isWindows ? 'Scripts' : 'bin'),
      );
      await binDirectory.create(recursive: true);
      await File(
        p.join(binDirectory.path, Platform.isWindows ? 'mfa.exe' : 'mfa'),
      ).writeAsBytes(const [0]);
    }
    return ProcessResult(1, 0, '', '');
  }
}
