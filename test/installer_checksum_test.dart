import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/installer_checksum.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('nww-checksum-');
    file = File("${directory.path}/不白 O'Brien setup.exe");
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('SHA-256 of an empty file matches the standard vector', () async {
    file.writeAsBytesSync([]);
    expect(
      await installerSha256(file),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('SHA-256 supports Unicode and quoted paths', () async {
    file.writeAsBytesSync(utf8.encode('abc'));
    expect(
      await installerSha256(file),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('SHA-256 streams a file spanning many input chunks', () async {
    file.writeAsBytesSync(List<int>.filled(1000000, 0x61));
    expect(
      await installerSha256(file),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('missing checksum input propagates its file error', () async {
    await expectLater(
      installerSha256(file),
      throwsA(isA<FileSystemException>()),
    );
  });
}
