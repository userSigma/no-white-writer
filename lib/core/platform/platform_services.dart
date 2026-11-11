import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'platform_services_stub.dart'
    if (dart.library.io) 'platform_services_io.dart'
    as impl;

/// 窗口几何（逻辑像素，PLAN.md §5.3）。
class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.maximized = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool maximized;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'maximized': maximized,
  };
}

/// 原生窗口事件的只读快照；UI 不推测系统快捷键引起的状态变化。
class DesktopWindowState {
  const DesktopWindowState({this.maximized = false, this.fullScreen = false});
  final bool maximized;
  final bool fullScreen;
}

/// 平台能力抽象：唯一允许 import `window_manager` / 调 `Process.run` 的边界（PLAN.md §5.1）。
///
/// 与 PLAN §5.3 的差异（实现期修正）：`restoreGeometry()` / `saveGeometry()`
/// 合并为 `initialize(geometry)` + `currentGeometry()`，让 settings 的读写留在 state 层，
/// 平台层不碰 JSON。
abstract interface class PlatformServices {
  String get platformLabel;

  /// 桌面：初始化窗口管理器并应用几何；移动端：no-op。
  Future<void> initialize({WindowGeometry? geometry, bool maximized = false});

  /// 数据根：Windows `%APPDATA%\不白写作`，macOS `~/Library/Application Support/不白写作`，
  /// Linux `${XDG_DATA_HOME:-~/.local/share}/不白写作`，移动端 app 私有目录。
  Future<Directory> dataRoot();

  /// 文档根：桌面 `~/Documents`，移动端 app 文档目录。
  Future<Directory> documentsRoot();

  Future<void> setWindowTitle(String title);

  bool get supportsCustomTitleBar;
  ValueListenable<DesktopWindowState> get windowState;
  Future<void> minimizeWindow();
  Future<void> toggleWindowMaximized();
  Future<void> startWindowDrag();

  /// 可取消的原生关闭请求，必须经过应用退出守卫；不是 quit/destroy。
  Future<void> requestWindowClose();

  Future<void> setMinimumWindowSize(Size size);

  Future<WindowGeometry> currentGeometry();

  Future<void> setFullScreen(bool on);

  bool get supportsExitIntercept;

  /// 打开原生目录选择器；用户取消时返回 null。
  Future<String?> selectDirectory({String? initialDirectory});

  Future<bool> revealInFileManager(String path);

  Future<void> quit();
}

PlatformServices createPlatformServices() => impl.createPlatformServices();
