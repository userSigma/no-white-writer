import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

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
  bool supportsCustomTitleBar = true;
  @override
  final ValueNotifier<DesktopWindowState> windowState = ValueNotifier(
    const DesktopWindowState(),
  );
  int minimizeCalls = 0, maximizeCalls = 0, dragCalls = 0, closeCalls = 0;
  Future<void> Function()? onRequestClose;

  @override
  Future<void> minimizeWindow() async {
    minimizeCalls++;
  }

  @override
  Future<void> toggleWindowMaximized() async {
    maximizeCalls++;
    windowState.value = DesktopWindowState(
      maximized: !windowState.value.maximized,
    );
  }

  @override
  Future<void> startWindowDrag() async {
    dragCalls++;
  }

  @override
  Future<void> requestWindowClose() async {
    closeCalls++;
    await onRequestClose?.call();
  }

  String? directoryToSelect;
  Object? directoryError;
  String? directoryInitialPath;
  Completer<String?>? directorySelection;

  @override
  Future<String?> selectDirectory({String? initialDirectory}) async {
    directoryInitialPath = initialDirectory;
    if (directoryError != null) throw directoryError!;
    return directorySelection == null
        ? directoryToSelect
        : await directorySelection!.future;
  }

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
