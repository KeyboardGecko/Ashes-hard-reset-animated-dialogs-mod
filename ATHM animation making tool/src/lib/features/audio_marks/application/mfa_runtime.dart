import 'dart:io';

import 'package:path/path.dart' as p;

typedef MfaProgressCallback = void Function(String message);

const mfaRuntimeVersion = '3.3.9';
const micromambaBundledVersion = '2.9.0';

class MfaRuntimeException implements Exception {
  const MfaRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

String resolveMicromambaExecutable({
  String? executablePath,
  String fallback = 'micromamba',
  bool? isWindows,
  bool Function(String path)? fileExists,
  String? workingDirectory,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (!windows) return fallback;

  final applicationPath = executablePath ?? Platform.resolvedExecutable;
  final bundled = p.join(
    p.dirname(applicationPath),
    'data',
    'tools',
    'micromamba.exe',
  );
  final exists = fileExists ?? ((path) => File(path).existsSync());
  if (exists(bundled)) return bundled;

  final sourceRoots = <String>[workingDirectory ?? Directory.current.path];
  var ancestor = p.dirname(applicationPath);
  for (var i = 0; i < 10; i++) {
    sourceRoots.add(ancestor);
    final parent = p.dirname(ancestor);
    if (p.equals(parent, ancestor)) break;
    ancestor = parent;
  }
  for (final root in sourceRoots) {
    final sourceBundle = p.join(
      root,
      'windows',
      'third_party',
      'micromamba',
      'bin',
      'micromamba.exe',
    );
    if (exists(sourceBundle)) return sourceBundle;
  }
  return fallback;
}

String defaultMfaRootDirectory({Map<String, String>? environment}) {
  final variables = environment ?? Platform.environment;
  final localAppData = variables['LOCALAPPDATA'];
  if (localAppData != null && localAppData.trim().isNotEmpty) {
    return p.join(localAppData, 'ATHM', 'mfa');
  }
  final userProfile = variables['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    return p.join(userProfile, 'AppData', 'Local', 'ATHM', 'mfa');
  }
  return p.join(Directory.systemTemp.path, 'ATHM', 'mfa');
}

abstract class MfaProcessRunner {
  const MfaProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  });
}

class SystemMfaProcessRunner extends MfaProcessRunner {
  const SystemMfaProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: false,
    );
  }
}

class MfaRuntimeManager {
  MfaRuntimeManager({
    String? micromambaExecutable,
    String? rootDirectory,
    this.processRunner = const SystemMfaProcessRunner(),
  }) : micromambaExecutable =
           micromambaExecutable ?? resolveMicromambaExecutable(),
       rootDirectory = rootDirectory ?? defaultMfaRootDirectory();

  final String micromambaExecutable;
  final String rootDirectory;
  final MfaProcessRunner processRunner;

  String get environmentPrefix =>
      p.join(rootDirectory, 'envs', 'mfa-$mfaRuntimeVersion');

  String get _mambaRootPrefix => p.join(rootDirectory, 'micromamba');
  String get _mfaDataDirectory => p.join(rootDirectory, 'data');
  String get _stateDirectory => p.join(rootDirectory, 'state');

  Future<void> ensureReady(
    String modelName, {
    required String languageLabel,
    MfaProgressCallback? onProgress,
  }) async {
    final executable = File(micromambaExecutable);
    if (!await executable.exists()) {
      throw MfaRuntimeException(
        'Bundled Micromamba was not found at "$micromambaExecutable". '
        'Rebuild or reinstall ATHM with data/tools/micromamba.exe.',
      );
    }

    await Directory(rootDirectory).create(recursive: true);
    await Directory(_stateDirectory).create(recursive: true);
    if (!await _hasRuntime()) {
      onProgress?.call('Installing the MFA runtime (first run only)...');
      final hasExistingPrefix = await Directory(environmentPrefix).exists();
      await _runChecked([
        hasExistingPrefix ? 'install' : 'create',
        '--yes',
        '--prefix',
        environmentPrefix,
        '--channel',
        'conda-forge',
        'python=3.11',
        'montreal-forced-aligner=$mfaRuntimeVersion',
        'kaldi=*=cpu*',
      ], action: 'install the MFA runtime');
      if (!await _hasRuntime()) {
        throw const MfaRuntimeException(
          'Micromamba completed, but the MFA executable is missing.',
        );
      }
    }

    final marker = File(p.join(_stateDirectory, '$modelName.ready'));
    if (!await marker.exists()) {
      onProgress?.call('Downloading the $languageLabel acoustic model...');
      await runMfaChecked([
        'model',
        'download',
        'acoustic',
        modelName,
      ], action: 'download the $languageLabel acoustic model');
      onProgress?.call('Downloading the $languageLabel dictionary...');
      await runMfaChecked([
        'model',
        'download',
        'dictionary',
        modelName,
      ], action: 'download the $languageLabel dictionary');
      await marker.writeAsString(
        'MFA $mfaRuntimeVersion\n$modelName\n',
        flush: true,
      );
      onProgress?.call('Cleaning the package download cache...');
      try {
        await _run(['clean', '--all', '--yes']);
      } catch (_) {
        // Cache cleanup is optional and must not invalidate a ready runtime.
      }
    }
  }

  Future<ProcessResult> runMfa(List<String> arguments) {
    return _run(['run', '--prefix', environmentPrefix, 'mfa', ...arguments]);
  }

  Future<void> runMfaChecked(
    List<String> arguments, {
    required String action,
  }) async {
    final result = await runMfa(arguments);
    _throwIfFailed(result, action);
  }

  Future<bool> _hasRuntime() {
    final executableName = Platform.isWindows ? 'mfa.exe' : 'mfa';
    return File(
      p.join(
        environmentPrefix,
        Platform.isWindows ? 'Scripts' : 'bin',
        executableName,
      ),
    ).exists();
  }

  Future<ProcessResult> _run(List<String> arguments) async {
    try {
      return await processRunner.run(
        micromambaExecutable,
        arguments,
        environment: {
          ...Platform.environment,
          'MAMBA_ROOT_PREFIX': _mambaRootPrefix,
          'MFA_ROOT_DIR': _mfaDataDirectory,
        },
      );
    } on ProcessException catch (error) {
      throw MfaRuntimeException('Could not start bundled Micromamba.\n$error');
    }
  }

  Future<void> _runChecked(
    List<String> arguments, {
    required String action,
  }) async {
    final result = await _run(arguments);
    _throwIfFailed(result, action);
  }

  void _throwIfFailed(ProcessResult result, String action) {
    if (result.exitCode == 0) return;
    final stderr = '${result.stderr}'.trim();
    final stdout = '${result.stdout}'.trim();
    final details = stderr.isNotEmpty ? stderr : stdout;
    throw MfaRuntimeException(
      'Micromamba could not $action (${result.exitCode}).'
      '${details.isEmpty ? '' : '\n$details'}',
    );
  }
}
