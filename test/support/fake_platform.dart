import 'dart:io';
import 'dart:ui' show Size;

import 'package:no_white_writer/core/platform/platform_services.dart';

/// 测试用平台替身：不碰 window_manager，只记录调用。
class FakePlatformServices implements PlatformServices {
  FakePlatformServices({required this.root, required this.documents});

  final Directory root;
  final Directory documents;

  WindowGeometry? lastGeometry;
  String? lastTitle;
  Size? lastMinSize;
  bool fullScreen = false;
  bool revealed = false;
  bool revealResult = true;
  bool quitCalled = false;

  @override
  String get platformLabel => 'test';

  @override
  Future<void> initialize({
    WindowGeometry? geometry,
    bool maximized = false,
  }) async {
    lastGeometry = geometry;
  }

  @override
  Future<Directory> dataRoot() async => root;

  @override
  Future<Directory> documentsRoot() async => documents;

  @override
  Future<void> setWindowTitle(String title) async {
    lastTitle = title;
  }

  @override
  Future<void> setMinimumWindowSize(Size size) async {
    lastMinSize = size;
  }

  @override
  Future<WindowGeometry> currentGeometry() async =>
      lastGeometry ??
      const WindowGeometry(x: 0, y: 0, width: 1280, height: 820);

  @override
  Future<void> setFullScreen(bool on) async {
    fullScreen = on;
  }

  @override
  bool get supportsExitIntercept => false;

  @override
  Future<bool> revealInFileManager(String path) async {
    revealed = true;
    return revealResult;
  }

  @override
  Future<void> quit() async {
    quitCalled = true;
  }
}
