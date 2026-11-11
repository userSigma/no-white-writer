import 'dart:io';

import 'package:crypto/crypto.dart';

/// Streams the installer in Dart without depending on host shell modules.
Future<String> installerSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
