import 'dart:io';
import 'dart:typed_data';

const installerAppId = 'ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b';
const appExecutable = 'no_white_writer.exe';

class InstallerOptions {
  const InstallerOptions({
    this.skipBuild = false,
    this.help = false,
    this.iscc,
    this.runtimeDir,
    this.sourceDir,
    this.outputDir,
  });

  final bool skipBuild;
  final bool help;
  final String? iscc;
  final String? runtimeDir;
  final String? sourceDir;
  final String? outputDir;

  static InstallerOptions parse(List<String> arguments) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var i = 0; i < arguments.length; i++) {
      final name = arguments[i];
      if (name == '--skip-build' || name == '--help') {
        if (!flags.add(name)) throw FormatException('Repeated option: $name');
      } else if (const [
        '--iscc',
        '--runtime-dir',
        '--source-dir',
        '--output-dir',
      ].contains(name)) {
        if (values.containsKey(name) ||
            i + 1 >= arguments.length ||
            arguments[i + 1].trim().isEmpty ||
            arguments[i + 1].startsWith('--')) {
          throw FormatException('Missing or repeated value for $name');
        }
        values[name] = arguments[++i];
      } else {
        throw FormatException('Unknown installer argument: $name');
      }
    }
    return InstallerOptions(
      skipBuild: flags.contains('--skip-build'),
      help: flags.contains('--help'),
      iscc: values['--iscc'],
      runtimeDir: values['--runtime-dir'],
      sourceDir: values['--source-dir'],
      outputDir: values['--output-dir'],
    );
  }
}

List<Directory> runtimeCandidates(Directory installation) {
  final root = Directory('${installation.path}/VC/Redist/MSVC');
  if (!root.existsSync()) return [];
  final versions = root
      .listSync(followLinks: false)
      .whereType<Directory>()
      .toList();
  List<int> numbers(Directory directory) => directory.uri.pathSegments
      .where((part) => part.isNotEmpty)
      .last
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  versions.sort((a, b) {
    final left = numbers(a);
    final right = numbers(b);
    for (var i = 0; i < left.length && i < right.length; i++) {
      final order = right[i].compareTo(left[i]);
      if (order != 0) return order;
    }
    return right.length.compareTo(left.length);
  });
  return [
    for (final version in versions)
      if (Directory('${version.path}/x64').existsSync())
        ...Directory('${version.path}/x64')
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((directory) => directory.path.endsWith('.CRT')),
  ];
}

class InstallerVersion {
  const InstallerVersion(this.full, this.base, this.windows);

  final String full;
  final String base;
  final String windows;

  String get filename => 'no-white-writer-$base-windows-x64-setup.exe';
}

InstallerVersion parseInstallerVersion(String source) {
  final entries = RegExp(
    r'^version:[ \t]*([^\r\n#]+)',
    multiLine: true,
  ).allMatches(source).toList();
  if (entries.length != 1) {
    throw const FormatException('pubspec must contain exactly one version.');
  }
  var full = entries.single.group(1)!.trim();
  if ((full.startsWith('"') && full.endsWith('"')) ||
      (full.startsWith("'") && full.endsWith("'"))) {
    full = full.substring(1, full.length - 1);
  }
  final match = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+(0|[1-9][0-9]*))?$',
  ).firstMatch(full);
  if (match == null) {
    throw FormatException('Invalid version or nonnumeric build number: $full');
  }
  final numbers = [
    for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
    int.parse(match.group(5) ?? '0'),
  ];
  if (numbers.any((number) => number > 65535)) {
    throw FormatException('Windows version components must be <= 65535: $full');
  }
  return InstallerVersion(full, full.split('+').first, numbers.join('.'));
}

List<String> compilerCandidates(Map<String, String> environment) {
  final paths = <String>[
    if (environment['INNO_SETUP_COMPILER'] case final String path) path,
    if (environment['LOCALAPPDATA'] case final String root)
      '$root/Programs/Inno Setup 6/ISCC.exe',
    for (final key in ['ProgramFiles(x86)', 'ProgramFiles'])
      if (environment[key] case final String root)
        '$root/Inno Setup 6/ISCC.exe',
    for (final directory in (environment['PATH'] ?? '').split(';'))
      if (directory.trim().isNotEmpty) '${directory.trim()}/ISCC.exe',
  ];
  return paths.map((path) => path.replaceAll('\\', '/')).toSet().toList();
}

void _requireFile(File file) {
  if (!file.existsSync() || file.lengthSync() == 0) {
    throw StateError('Missing or empty installer input: ${file.path}');
  }
}

void _requireX64Pe(File file) {
  _requireFile(file);
  final handle = file.openSync();
  try {
    final header = handle.readSync(64);
    if (header.length != 64 || header[0] != 0x4d || header[1] != 0x5a) {
      throw StateError('Not an x64 PE binary: ${file.path}');
    }
    final offset = ByteData.sublistView(header).getUint32(0x3c, Endian.little);
    if (offset < 64 || offset > handle.lengthSync() - 6) {
      throw StateError('Invalid PE header: ${file.path}');
    }
    handle.setPositionSync(offset);
    final pe = handle.readSync(6);
    if (pe[0] != 0x50 ||
        pe[1] != 0x45 ||
        pe[2] != 0 ||
        pe[3] != 0 ||
        ByteData.sublistView(pe).getUint16(4, Endian.little) != 0x8664) {
      throw StateError('Installer requires x64 PE binaries: ${file.path}');
    }
  } finally {
    handle.closeSync();
  }
}

void _requireX64Aot(File file) {
  _requireFile(file);
  final handle = file.openSync();
  try {
    final header = handle.readSync(64);
    if (header.length != 64 ||
        header[0] != 0x7f ||
        header[1] != 0x45 ||
        header[2] != 0x4c ||
        header[3] != 0x46 ||
        header[4] != 2 ||
        header[5] != 1 ||
        ByteData.sublistView(header).getUint16(18, Endian.little) != 0x3e) {
      throw StateError('Not an x64 ELF Dart AOT snapshot: ${file.path}');
    }
  } finally {
    handle.closeSync();
  }
}

void validateReleaseBundle(Directory source) {
  for (final name in [appExecutable, 'flutter_windows.dll']) {
    _requireX64Pe(File('${source.path}/$name'));
  }
  _requireX64Aot(File('${source.path}/data/app.so'));
  for (final name in [
    'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin',
  ]) {
    _requireFile(File('${source.path}/$name'));
  }
}

void validateVcRuntime(Directory source) {
  for (final name in [
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
  ]) {
    _requireX64Pe(File('${source.path}/$name'));
  }
}

/// Copies only into an empty, caller-owned stage; never mutates the build bundle.
void stageInstallerBundle(
  Directory source,
  Directory runtime,
  Directory target,
) {
  validateReleaseBundle(source);
  validateVcRuntime(runtime);
  if (target.existsSync() && target.listSync().isNotEmpty) {
    throw StateError(
      'Refusing to reuse a nonempty staging directory: ${target.path}',
    );
  }
  target.createSync(recursive: true);
  final sourceRoot = source.absolute.path;
  for (final entity in source.absolute.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Link) {
      throw StateError(
        'Installer inputs must not contain symbolic links: ${entity.path}',
      );
    }
    if (entity is! File) continue;
    final relative = entity.path.substring(sourceRoot.length + 1);
    if (RegExp(r'\.(pdb|lib|exp)$', caseSensitive: false).hasMatch(relative)) {
      continue;
    }
    final destination = File('${target.path}/$relative');
    destination.parent.createSync(recursive: true);
    entity.copySync(destination.path);
  }
  for (final entity in runtime.listSync(followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.dll')) {
      _requireX64Pe(entity);
      final name = entity.uri.pathSegments.last;
      entity.copySync('${target.path}/$name');
    }
  }
}

void ensureOutputAvailable(Directory output, InstallerVersion version) {
  for (final suffix in ['', '.sha256']) {
    final path = '${output.path}/${version.filename}$suffix';
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Refusing to overwrite output: $path');
    }
  }
}
