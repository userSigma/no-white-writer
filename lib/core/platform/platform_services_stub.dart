import 'dart:io';
import 'dart:ui' show Size;

import 'platform_services.dart';

/// 无 `dart:io` 平台（web）的占位实现；本项目 v1 不构建 web，仅保证条件导入可编译。
class StubPlatformServices implements PlatformServices {
  @override
  String get platformLabel => 'unsupported';

  @override
  Future<void> initialize({
    WindowGeometry? geometry,
    bool maximized = false,
  }) async {}

  @override
  Future<Directory> dataRoot() async => Directory.current;

  @override
  Future<Directory> documentsRoot() async => Directory.current;

  @override
  Future<void> setWindowTitle(String title) async {}

  @override
  Future<void> setMinimumWindowSize(Size size) async {}

  @override
  Future<WindowGeometry> currentGeometry() async =>
      const WindowGeometry(x: 0, y: 0, width: 1280, height: 820);

  @override
  Future<void> setFullScreen(bool on) async {}

  @override
  bool get supportsExitIntercept => false;

  @override
  Future<bool> revealInFileManager(String path) async => false;

  @override
  Future<void> quit() async {}
}

PlatformServices createPlatformServices() => StubPlatformServices();
