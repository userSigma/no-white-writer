import 'dart:io';

import 'installer_config.dart';

const _usage = '''
Build the per-user No White Writer Windows x64 installer.

  dart run tool/build_windows_installer.dart [options]

  --skip-build          Reuse an explicitly prebuilt Release bundle.
  --iscc PATH           Inno Setup 6 compiler (or INNO_SETUP_COMPILER).
  --runtime-dir PATH    Visual Studio x64 Microsoft.VC*.CRT directory.
  --source-dir PATH     Release bundle; defaults to build/windows/x64/runner/Release.
  --output-dir PATH     Output folder; defaults to build/packages.
  --help                Show this help without building or changing files.

Without --skip-build, flutter build windows --release runs first.
Existing setup/hash files are never overwritten. No elevation is requested.
''';

Future<void> main(List<String> arguments) async {
  try {
    final options = InstallerOptions.parse(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    if (!Platform.isWindows) {
      throw StateError(
        'Windows, Flutter Windows tooling and Inno Setup 6 are required.',
      );
    }
    final root = File.fromUri(Platform.script).parent.parent.absolute;
    final version = parseInstallerVersion(
      File('${root.path}/pubspec.yaml').readAsStringSync(),
    );
    final output = Directory(options.outputDir ?? '${root.path}/build/packages')
        .absolute;
    ensureOutputAvailable(output, version);
    final compiler = _findCompiler(options.iscc);
    final runtime = await _findRuntime(options.runtimeDir);
    final source = Directory(
      options.sourceDir ?? '${root.path}/build/windows/x64/runner/Release',
    ).absolute;
    stdout.writeln('Product: ${version.full} (Windows ${version.windows})');
    stdout.writeln('Compiler: ${compiler.path}');
    stdout.writeln('VC++ runtime: ${runtime.path}');
    if (!options.skipBuild) {
      if (options.sourceDir != null) {
        throw const FormatException(
          '--source-dir requires --skip-build; fresh builds use the project Release output.',
        );
      }
      await _run(
        'flutter',
        ['build', 'windows', '--release'],
        root,
        shell: true,
      );
    }
    validateReleaseBundle(source);
    final stageRoot = Directory('${root.path}/build/installer-staging')
      ..createSync(recursive: true);
    final stage = stageRoot.createTempSync('x64-${version.full}-');
    stageInstallerBundle(source, runtime, stage);
    stdout.writeln('Staged bundle: ${stage.path}');
    output.createSync(recursive: true);
    ensureOutputAvailable(output, version);
    await _run(compiler.path, [
      '/DAppVersion=${version.full}',
      '/DWindowsVersion=${version.windows}',
      '/DInstallerAppId=$installerAppId',
      '/DSourceDir=${stage.path}',
      '/DOutputDir=${output.path}',
      '/DOutputBaseName=${version.filename.substring(0, version.filename.length - 4)}',
      '${root.path}/installer/no_white_writer.iss',
    ], root);
    final setup = File('${output.path}/${version.filename}');
    if (!setup.existsSync() || setup.lengthSync() == 0) {
      throw StateError(
        'ISCC did not produce the expected installer: ${setup.path}',
      );
    }
    final hash = await _sha256(setup);
    File('${setup.path}.sha256')
        .writeAsStringSync('$hash  ${version.filename}\n');
    stdout.writeln('Installer: ${setup.path} (${setup.lengthSync()} bytes)');
    stdout.writeln('SHA-256: $hash');
  } catch (error) {
    stderr.writeln('Installer build failed: $error');
    exitCode = error is ProcessException && error.errorCode > 0
        ? error.errorCode
        : 1;
  }
}

File _findCompiler(String? override) {
  final explicit = override ?? Platform.environment['INNO_SETUP_COMPILER'];
  if (explicit != null) {
    final compiler = File(explicit).absolute;
    if (!compiler.existsSync()) {
      throw StateError('ISCC override does not exist: ${compiler.path}');
    }
    return compiler;
  }
  for (final path in compilerCandidates(Platform.environment)) {
    if (File(path).existsSync()) return File(path).absolute;
  }
  throw StateError(
    'ISCC.exe not found. Install Inno Setup 6 or pass --iscc PATH.',
  );
}

Future<Directory> _findRuntime(String? override) async {
  if (override != null) {
    final directory = Directory(override).absolute;
    validateVcRuntime(directory);
    return directory;
  }
  final installations = <String>{};
  final programRoots = <String>{
    if (Platform.environment['ProgramFiles(x86)'] case final String path) path,
    if (Platform.environment['ProgramFiles'] case final String path) path,
  };
  for (final programRoot in programRoots) {
    final vswhere = File(
      '$programRoot/Microsoft Visual Studio/Installer/vswhere.exe',
    );
    if (vswhere.existsSync()) {
      final result = await Process.run(vswhere.path, [
        '-products',
        '*',
        '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property',
        'installationPath',
      ]);
      if (result.exitCode != 0) {
        throw StateError('vswhere failed: ${result.stderr}');
      }
      installations.addAll(
        (result.stdout as String)
            .split(RegExp(r'[\r\n]+'))
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty),
      );
    }
    for (final version in ['18', '2026', '2022']) {
      final directory = Directory(
        '$programRoot/Microsoft Visual Studio/$version',
      );
      if (directory.existsSync()) {
        installations.addAll(
          directory
              .listSync(followLinks: false)
              .whereType<Directory>()
              .map((edition) => edition.path),
        );
      }
    }
  }
  for (final installation in installations) {
    for (final directory in runtimeCandidates(Directory(installation))) {
      try {
        validateVcRuntime(directory);
        return directory;
      } on StateError {
        // This installation may have only a partial/older redistributable set.
      }
    }
  }
  throw StateError(
    'Visual Studio x64 VC++ redistributable DLLs not found. Install the C++ tooling or pass --runtime-dir to its Microsoft.VC*.CRT directory. Do not use System32.',
  );
}

Future<void> _run(
  String executable,
  List<String> arguments,
  Directory root, {
  bool shell = false,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: root.path,
    runInShell: shell && Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Process returned $code.',
      code,
    );
  }
}

Future<String> _sha256(File file) async {
  // A native command, not an unsigned .ps1 file or an execution-policy override.
  final literal = file.path.replaceAll("'", "''");
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "(Get-FileHash -LiteralPath '$literal' -Algorithm SHA256).Hash",
  ]);
  final hash = (result.stdout as String).trim().toLowerCase();
  if (result.exitCode != 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
    throw StateError('Unable to hash installer: ${result.stderr}');
  }
  return hash;
}
