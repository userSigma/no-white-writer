import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/installer_config.dart';

void main() {
  group('installer command line', () {
    test('defaults to a fresh Release build', () {
      final options = InstallerOptions.parse([]);
      expect(options.skipBuild, isFalse);
      expect(options.help, isFalse);
      expect(options.iscc, isNull);
    });

    test('preserves explicit paths with spaces and opt-in skip-build', () {
      final options = InstallerOptions.parse([
        '--skip-build',
        '--iscc',
        'C:/Program Files/Inno Setup 6/ISCC.exe',
        '--runtime-dir',
        'C:/VC/Redist/x64/Microsoft.VC145.CRT',
        '--source-dir',
        'D:/Release bundle',
        '--output-dir',
        'D:/setup output',
      ]);
      expect(options.skipBuild, isTrue);
      expect(options.iscc, 'C:/Program Files/Inno Setup 6/ISCC.exe');
      expect(options.runtimeDir, contains('Microsoft.VC145.CRT'));
      expect(options.sourceDir, 'D:/Release bundle');
      expect(options.outputDir, 'D:/setup output');
      expect(InstallerOptions.parse(['--help']).help, isTrue);
    });

    for (final args in [
      ['--unknown'],
      ['--iscc'],
      ['--output-dir', '--skip-build'],
      ['--source-dir', ''],
      ['--iscc', 'one', '--iscc', 'two'],
    ]) {
      test('rejects ambiguous or missing arguments: $args', () {
        expect(() => InstallerOptions.parse(args), throwsFormatException);
      });
    }
  });

  test('runtime discovery selects newest x64 CRT, never x86 or OneCore', () {
    final installation = Directory.systemTemp.createTempSync('nww-vs-');
    addTearDown(() => installation.deleteSync(recursive: true));
    for (final relative in [
      '14.9.1/x64/Microsoft.VC143.CRT',
      '14.51.2/x64/Microsoft.VC145.CRT',
      '14.51.2/x86/Microsoft.VC145.CRT',
      '14.51.2/onecore/x64/Microsoft.VC145.CRT',
    ]) {
      Directory('${installation.path}/VC/Redist/MSVC/$relative')
          .createSync(recursive: true);
    }
    final candidates = runtimeCandidates(installation);
    expect(candidates, hasLength(2));
    expect(
      candidates.first.path.replaceAll('\\', '/'),
      contains('14.51.2/x64'),
    );
    expect(candidates.last.path.replaceAll('\\', '/'), contains('14.9.1/x64'));
  });

  group('installer version', () {
    test('uses the pubspec version without changing the build number', () {
      final version = parseInstallerVersion(
        'name: no_white_writer\nversion: 0.4.1+5\n',
      );
      expect(version.full, '0.4.1+5');
      expect(version.base, '0.4.1');
      expect(version.windows, '0.4.1.5');
      expect(version.filename, 'no-white-writer-0.4.1-windows-x64-setup.exe');
    });

    test('preserves prerelease identity but uses numeric Windows metadata', () {
      final version = parseInstallerVersion('version: 1.2.3-beta.2+16');
      expect(version.full, '1.2.3-beta.2+16');
      expect(version.base, '1.2.3-beta.2');
      expect(version.windows, '1.2.3.16');
      expect(version.filename, contains('1.2.3-beta.2'));
    });

    test('uses zero when there is no explicit build number', () {
      expect(parseInstallerVersion('version: 1.2.3').windows, '1.2.3.0');
    });

    test('accepts a quoted pubspec version with an inline comment', () {
      expect(
        parseInstallerVersion('version: "0.4.1+5" # release').full,
        '0.4.1+5',
      );
    });

    for (final source in [
      'name: no_white_writer',
      'version: latest',
      'version: 1.2',
      'version: 01.2.3+4',
      'version: 1.2.3+foo',
      'version: 1.2.3+4.5',
      'version: 65536.2.3+4',
      'version: 1.2.3+65536',
      'version: 1.2.3\nversion: 2.3.4',
      'version: 1.2.3-beta..2+4',
    ]) {
      test('rejects invalid or ambiguous version: $source', () {
        expect(() => parseInstallerVersion(source), throwsFormatException);
      });
    }
  });

  test(
    'compiler discovery honors override then per-user and machine paths',
    () {
      final candidates = compilerCandidates({
        'INNO_SETUP_COMPILER': 'D:/custom/ISCC.exe',
        'LOCALAPPDATA': 'C:/Users/test/AppData/Local',
        'ProgramFiles(x86)': 'C:/Program Files (x86)',
        'ProgramFiles': 'C:/Program Files',
        'PATH': 'C:/tools;D:/another',
      });
      expect(candidates.first, 'D:/custom/ISCC.exe');
      expect(
        candidates,
        contains('C:/Users/test/AppData/Local/Programs/Inno Setup 6/ISCC.exe'),
      );
      expect(
        candidates,
        contains('C:/Program Files (x86)/Inno Setup 6/ISCC.exe'),
      );
      expect(candidates, contains('C:/tools/ISCC.exe'));
      expect(candidates.toSet().length, candidates.length);
    },
  );

  group('installer payload', () {
    late Directory temp;
    late Directory release;
    late Directory runtime;

    void writePe(String path, {int machine = 0x8664}) {
      final bytes = Uint8List(160);
      bytes[0] = 0x4d;
      bytes[1] = 0x5a;
      final data = ByteData.sublistView(bytes);
      data.setUint32(0x3c, 0x80, Endian.little);
      bytes.setRange(0x80, 0x84, [0x50, 0x45, 0, 0]);
      data.setUint16(0x84, machine, Endian.little);
      File(path).parent.createSync(recursive: true);
      File(path).writeAsBytesSync(bytes);
    }

    setUp(() {
      temp = Directory.systemTemp.createTempSync('nww-installer-config-');
      release = Directory('${temp.path}/release')..createSync();
      runtime = Directory('${temp.path}/Microsoft.VC143.CRT')..createSync();
      for (final path in ['no_white_writer.exe', 'flutter_windows.dll']) {
        writePe('${release.path}/$path');
      }
      // Dart's Windows AOT snapshot is ELF64, not a Windows PE DLL.
      final aot = Uint8List(64);
      aot.setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
      ByteData.sublistView(aot).setUint16(18, 0x3e, Endian.little);
      Directory('${release.path}/data').createSync();
      File('${release.path}/data/app.so').writeAsBytesSync(aot);
      for (final path in [
        'data/icudtl.dat',
        'data/flutter_assets/AssetManifest.bin',
      ]) {
        final file = File('${release.path}/$path');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('payload');
      }
      for (final dll in [
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
      ]) {
        writePe('${runtime.path}/$dll');
      }
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('accepts a complete x64 AOT Release bundle', () {
      expect(() => validateReleaseBundle(release), returnsNormally);
    });

    for (final path in [
      'no_white_writer.exe',
      'flutter_windows.dll',
      'data/app.so',
      'data/icudtl.dat',
      'data/flutter_assets/AssetManifest.bin',
    ]) {
      test('rejects a Release bundle missing $path', () {
        File('${release.path}/$path').deleteSync();
        expect(() => validateReleaseBundle(release), throwsStateError);
      });
    }

    test('rejects a non-x64 executable rather than mislabeling it', () {
      writePe('${release.path}/no_white_writer.exe', machine: 0xaa64);
      expect(() => validateReleaseBundle(release), throwsStateError);
    });

    test('rejects a PE pretending to be a Dart AOT snapshot', () {
      writePe('${release.path}/data/app.so');
      expect(() => validateReleaseBundle(release), throwsStateError);
    });

    test('rejects a non-x64 ELF AOT snapshot', () {
      final file = File('${release.path}/data/app.so');
      final bytes = file.readAsBytesSync();
      ByteData.sublistView(bytes).setUint16(18, 0xb7, Endian.little);
      file.writeAsBytesSync(bytes);
      expect(() => validateReleaseBundle(release), throwsStateError);
    });

    test('rejects a truncated PE file', () {
      File('${release.path}/no_white_writer.exe').writeAsStringSync('MZ');
      expect(() => validateReleaseBundle(release), throwsStateError);
    });

    test('requires the complete minimum app-local VC++ runtime', () {
      expect(() => validateVcRuntime(runtime), returnsNormally);
      File('${runtime.path}/vcruntime140_1.dll').deleteSync();
      expect(() => validateVcRuntime(runtime), throwsStateError);
    });

    test('rejects x86 runtime DLLs', () {
      writePe('${runtime.path}/msvcp140.dll', machine: 0x14c);
      expect(() => validateVcRuntime(runtime), throwsStateError);
    });

    test('stages assets and CRT without changing the Release source', () {
      final pdb = File('${release.path}/flutter_windows.pdb')
        ..writeAsStringSync('debug symbols');
      final license = File('${release.path}/data/flutter_assets/LICENSE.txt')
        ..writeAsStringSync('license');
      final stage = Directory('${temp.path}/staged');
      stageInstallerBundle(release, runtime, stage);
      expect(File('${stage.path}/no_white_writer.exe').existsSync(), isTrue);
      expect(File('${stage.path}/data/app.so').existsSync(), isTrue);
      expect(File('${stage.path}/msvcp140.dll').existsSync(), isTrue);
      expect(
        File('${stage.path}/data/flutter_assets/LICENSE.txt')
            .readAsStringSync(),
        'license',
      );
      expect(File('${stage.path}/flutter_windows.pdb').existsSync(), isFalse);
      expect(pdb.existsSync(), isTrue);
      expect(license.readAsStringSync(), 'license');
      expect(File('${release.path}/msvcp140.dll').existsSync(), isFalse);
    });

    test('never reuses a nonempty stage or overwrites an existing package', () {
      final stage = Directory('${temp.path}/staged')..createSync();
      File('${stage.path}/keep.txt').writeAsStringSync('keep');
      expect(
        () => stageInstallerBundle(release, runtime, stage),
        throwsStateError,
      );
      expect(File('${stage.path}/keep.txt').readAsStringSync(), 'keep');
      final version = parseInstallerVersion('version: 0.4.1+5');
      final output = Directory('${temp.path}/packages')..createSync();
      expect(() => ensureOutputAvailable(output, version), returnsNormally);
      final existing = File('${output.path}/${version.filename}.sha256')
        ..writeAsStringSync('previous hash');
      expect(() => ensureOutputAvailable(output, version), throwsStateError);
      expect(existing.readAsStringSync(), 'previous hash');
    });
  });
}
