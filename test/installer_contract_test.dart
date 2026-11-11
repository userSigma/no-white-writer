import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String installerSource() {
  final file = File('installer/no_white_writer.iss');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'The Inno Setup script must exist.',
  );
  return file.readAsStringSync();
}

void main() {
  test(
    'installer has a stable AppId and an unelevated per-user destination',
    () {
      final source = installerSource();
      expect(source, contains('ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b'));
      expect(source, contains('PrivilegesRequired=lowest'));
      expect(source, contains(r'DefaultDirName={localappdata}\Programs\不白写作'));
      expect(source, contains('UsePreviousAppDir=yes'));
      expect(source, contains('ArchitecturesAllowed=x64compatible'));
      expect(source, isNot(contains('PrivilegesRequiredOverridesAllowed')));
    },
  );

  test(
    'installer includes complete staged files and optional desktop shortcut',
    () {
      final source = installerSource();
      expect(source, contains('recursesubdirs createallsubdirs'));
      expect(source, contains('SetupIconFile='));
      expect(source, contains('app_icon.ico'));
      expect(source, contains('desktopicon'));
      expect(source, contains('Flags: unchecked'));
      expect(source, contains('skipifsilent'));
      expect(source, contains('VersionInfoVersion={#WindowsVersion}'));
      expect(source, contains('GetVersionNumbersString'));
    },
  );

  test('setup never closes writing processes or purges author data', () {
    final source = installerSource();
    expect(source, contains('CloseApplications=no'));
    expect(source, contains('RestartApplications=no'));
    expect(source, contains('function PrepareToInstall('));
    expect(source, contains('function InitializeUninstall(): Boolean;'));
    expect(source, contains('fmOpenReadWrite or fmShareExclusive'));
    for (final forbidden in [
      '[UninstallDelete]',
      '[InstallDelete]',
      'DelTree(',
      'DeleteFile(',
      'TerminateProcess',
      'taskkill',
      'instance.lock',
      '{userappdata}',
      'NWW_DATA_ROOT',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('Windows CI compiles setup alongside the Release runtime artifact', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(
      ci,
      contains('dart run tool/build_windows_installer.dart --skip-build'),
    );
    expect(ci, contains('build/windows/x64/runner/Release/'));
    expect(ci, contains('build/packages/*-setup.exe'));
    expect(ci, contains('build/packages/*-setup.exe.sha256'));
    expect(ci, contains('innosetup'));
  });

  test('tagged release keeps ZIP and adds setup plus SHA-256', () {
    final release = File('.github/workflows/release.yml').readAsStringSync();
    expect(
      release,
      contains('dart run tool/build_windows_installer.dart --skip-build'),
    );
    expect(release, contains('build/packages/*.zip'));
    expect(release, contains('build/packages/*-setup.exe'));
    expect(release, contains('build/packages/*.sha256'));
    expect(release, contains('contents: write'));
    expect(release, contains('softprops/action-gh-release@v2'));
    expect(release, contains('innosetup'));
  });
}
