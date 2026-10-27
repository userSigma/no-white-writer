import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, PlatformDispatcher, Rect, Size;

import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'path_utils.dart';
import 'platform_services.dart';

/// 桌面与移动端实现（PLAN.md §5.5）。窗口 API 只在 `_isDesktop` 分支调用，
/// 移动端构建时不会执行任何 window_manager 逻辑。
class IoPlatformServices implements PlatformServices {
  static const String appFolderName = '不白写作';
  static const Size minWindowSize = Size(900, 600);
  static const Size defaultWindowSize = Size(1280, 820);

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  String get platformLabel => Platform.operatingSystem;

  @override
  Future<void> initialize({
    WindowGeometry? geometry,
    bool maximized = false,
  }) async {
    if (!_isDesktop) return;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(minWindowSize);
    final ({Size work, Offset origin}) area = await _workArea();
    final Size target = _initialSize(geometry, area.work);
    await windowManager.setSize(target);
    final ({double x, double y}) position = _initialPosition(
      geometry,
      area,
      target,
    );
    await windowManager.setPosition(Offset(position.x, position.y));
    if (maximized || (geometry?.maximized ?? false)) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// 主显示器工作区（逻辑像素，已排除任务栏）与原点。R18 的收敛基准。
  Future<({Size work, Offset origin})> _workArea() async {
    try {
      final Display display = await screenRetriever.getPrimaryDisplay();
      final Size work = display.visibleSize ?? display.size;
      final Offset origin = display.visiblePosition ?? Offset.zero;
      if (work.width > 0 && work.height > 0) {
        return (work: work, origin: origin);
      }
    } catch (_) {
      // 平台插件不可用（如 Linux 某些会话）时退回窗口尺寸推算。
    }
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final double dpr = view.devicePixelRatio;
        if (dpr > 0) {
          return (
            work: Size(
              view.physicalSize.width / dpr,
              view.physicalSize.height / dpr,
            ),
            origin: Offset.zero,
          );
        }
      }
    } catch (_) {
      // 拿不到就用兜底值。
    }
    return (work: const Size(1920, 1080), origin: Offset.zero);
  }

  /// R18：默认尺寸按工作区 ×0.9 收敛，且不低于 900×600。
  Size _initialSize(WindowGeometry? saved, Size screen) {
    final double maxW = math.max(minWindowSize.width, screen.width * 0.9);
    final double maxH = math.max(minWindowSize.height, screen.height * 0.9);
    if (saved != null &&
        saved.width >= minWindowSize.width &&
        saved.height >= minWindowSize.height &&
        saved.width <= screen.width &&
        saved.height <= screen.height) {
      return Size(saved.width, saved.height);
    }
    return Size(
      math.min(defaultWindowSize.width, maxW),
      math.min(defaultWindowSize.height, maxH),
    );
  }

  ({double x, double y}) _initialPosition(
    WindowGeometry? saved,
    ({Size work, Offset origin}) area,
    Size target,
  ) {
    if (saved != null) {
      final bool onScreen =
          saved.x <= area.origin.dx + area.work.width - 200 &&
          saved.y <= area.origin.dy + area.work.height - 200 &&
          saved.x + saved.width >= area.origin.dx + 200 &&
          saved.y >= area.origin.dy - 40;
      if (onScreen) return (x: saved.x, y: saved.y);
    }
    return (
      x: math.max(
        area.origin.dx,
        area.origin.dx + (area.work.width - target.width) / 2,
      ),
      y: math.max(
        area.origin.dy,
        area.origin.dy + (area.work.height - target.height) / 2,
      ),
    );
  }

  @override
  Future<Directory> dataRoot() async {
    // 便携/调试覆盖：NWW_DATA_ROOT 指定数据根（正式使用不设置，走系统目录）。
    final String? override = Platform.environment['NWW_DATA_ROOT'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override.trim());
    }
    if (Platform.isWindows) {
      final String? appData = Platform.environment['APPDATA'];
      final String base = (appData != null && appData.isNotEmpty)
          ? appData
          : pathJoin(
              pathJoin(
                Platform.environment['USERPROFILE'] ?? Directory.current.path,
                'AppData',
              ),
              'Roaming',
            );
      return Directory(pathJoin(base, appFolderName));
    }
    if (Platform.isMacOS) {
      final String home =
          Platform.environment['HOME'] ?? Directory.current.path;
      return Directory(
        pathJoin(
          pathJoin(home, 'Library'),
          'Application Support/$appFolderName',
        ),
      );
    }
    if (Platform.isLinux) {
      final String? xdg = Platform.environment['XDG_DATA_HOME'];
      final String home =
          Platform.environment['HOME'] ?? Directory.current.path;
      final String base = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : pathJoin(home, '.local/share');
      return Directory(pathJoin(base, appFolderName));
    }
    // Android / iOS：app 沙箱私有目录（系统负责路径）。
    return getApplicationSupportDirectory();
  }

  @override
  Future<Directory> documentsRoot() async {
    if (Platform.isWindows) {
      final String? home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        return Directory(pathJoin(home, 'Documents'));
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final String? home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(pathJoin(home, 'Documents'));
      }
    }
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<void> setWindowTitle(String title) async {
    if (!_isDesktop) return;
    await windowManager.setTitle(title);
  }

  @override
  Future<void> setMinimumWindowSize(Size size) async {
    if (!_isDesktop) return;
    await windowManager.setMinimumSize(size);
  }

  @override
  Future<WindowGeometry> currentGeometry() async {
    if (!_isDesktop) {
      return const WindowGeometry(x: 0, y: 0, width: 1280, height: 820);
    }
    final Rect bounds = await windowManager.getBounds();
    final bool maximized = await windowManager.isMaximized();
    return WindowGeometry(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
      maximized: maximized,
    );
  }

  @override
  Future<void> setFullScreen(bool on) async {
    if (!_isDesktop) return;
    await windowManager.setFullScreen(on);
  }

  @override
  bool get supportsExitIntercept => _isDesktop;

  @override
  Future<bool> revealInFileManager(String path) async {
    if (!_isDesktop) return false;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', <String>[path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[path]);
      } else {
        await Process.run('xdg-open', <String>[path]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> quit() async {
    if (_isDesktop) {
      await windowManager.destroy();
    } else {
      exit(0);
    }
  }
}

PlatformServices createPlatformServices() => IoPlatformServices();
