import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/storage/library_store.dart';

/// settings.json 的内存状态与 400ms 防抖落盘（PLAN.md §4.1）。
class SettingsController extends ChangeNotifier {
  SettingsController({required this.store, required AppSettings initial})
    : settings = initial;

  final SettingsStore store;
  AppSettings settings;
  Timer? _timer;
  String? saveError;
  Future<void> _tail = Future<void>.value();
  Future<void>? _queuedFuture;
  String? _queuedJson;
  String? _savedJson;
  int _pending = 0;
  bool _disposed = false;

  String get themeMode => settings.themeMode;

  /// 界面语言选择（i18n 语言包 code）；只负责持久化，
  /// code 是否已注册由 I18nController 在应用时裁决。
  void setLanguage(String code) {
    if (settings.language == code) return;
    settings.language = code;
    _changed();
  }

  void setThemeMode(String mode) {
    if (settings.themeMode == mode) return;
    settings.themeMode = mode;
    _changed();
  }

  /// 自定义主题上限。
  static const int customThemeLimit = 4;

  /// 「自定义主题N」自动编号的占用解析。
  static final RegExp _autoName = RegExp(r'^自定义主题(\d+)$');

  /// 最小未占用的自动编号正整数（按现有主题名解析）。
  int _nextAutoNumber() {
    final Set<int> used = <int>{
      for (final CustomTheme t in settings.customThemes)
        if (_autoName.hasMatch(t.name))
          int.parse(_autoName.firstMatch(t.name)!.group(1)!),
    };
    int n = 1;
    while (used.contains(n)) {
      n++;
    }
    return n;
  }

  /// 新建自定义主题；已达上限返回 null。
  ///
  /// [name] 为空时按「自定义主题N」自动编号（最小未占用正整数）。
  CustomTheme? addCustomTheme({
    required int background,
    required int accent,
    String? name,
  }) {
    if (settings.customThemes.length >= customThemeLimit) return null;
    final String trimmed = (name ?? '').trim();
    final CustomTheme theme = CustomTheme(
      // 时间戳基 36 进制 id：单机单实例下稳定且无碰撞。
      id: 't${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: trimmed.isEmpty ? '自定义主题${_nextAutoNumber()}' : trimmed,
      background: background,
      accent: accent,
    );
    settings.customThemes.add(theme);
    _changed();
    return theme;
  }

  /// 重命名自定义主题；id 不存在或新名为空时返回 false。
  bool renameCustomTheme(String id, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    for (int i = 0; i < settings.customThemes.length; i++) {
      if (settings.customThemes[i].id == id) {
        if (settings.customThemes[i].name == trimmed) return true;
        settings.customThemes[i] = CustomTheme(
          id: id,
          name: trimmed,
          background: settings.customThemes[i].background,
          accent: settings.customThemes[i].accent,
        );
        _changed();
        return true;
      }
    }
    return false;
  }

  /// 删除自定义主题；若当前正使用它则回退「跟随系统」。
  bool deleteCustomTheme(String id) {
    final int before = settings.customThemes.length;
    settings.customThemes.removeWhere((CustomTheme t) => t.id == id);
    if (settings.customThemes.length == before) return false;
    if (settings.themeMode == 'custom:$id') {
      settings.themeMode = 'system';
    }
    _changed();
    return true;
  }

  void setFontSize(double size) {
    final double clamped = size.clamp(14, 28).toDouble();
    if (settings.fontSize == clamped) return;
    settings.fontSize = clamped;
    _changed();
  }

  void setLineHeight(double height) {
    final double clamped = height.clamp(1.4, 2.4).toDouble();
    if (settings.lineHeight == clamped) return;
    settings.lineHeight = clamped;
    _changed();
  }

  void setAutoIndent(bool value) {
    settings.autoIndent = value;
    _changed();
  }

  void setBlankLineBetween(bool value) {
    settings.blankLineBetween = value;
    _changed();
  }

  void rememberGeometry(
    double x,
    double y,
    double width,
    double height, {
    required bool maximized,
  }) {
    settings
      ..windowX = x
      ..windowY = y
      ..windowWidth = width
      ..windowHeight = height
      ..windowMaximized = maximized;
    _changed();
  }

  void setExportDirectory(String? path) {
    settings.exportDirectory = path;
    _changed();
  }

  void setSidebarCollapsed(bool value) {
    settings.sidebarCollapsed = value;
    _changed();
  }

  void rememberExpanded(String bookId, List<String> volumeIds) {
    settings.expandedVolumes[bookId] = volumeIds;
    _changed();
  }

  List<String> expandedOf(String bookId) =>
      settings.expandedVolumes[bookId] ?? const <String>[];

  void setLastOpenedBook(String? bookId) {
    settings.lastOpenedBookId = bookId;
    _changed();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    _notify();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () {
      unawaited(flush().catchError((Object _) {}));
    });
  }

  /// Capture at request time, serialize writes, and only share the latest request.
  /// Sharing an older A after A→B→A would incorrectly leave B on disk.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return Future<void>.error(StateError('设置控制器已关闭'));
    final raw = jsonEncode(settings.toJson());
    if (_queuedJson == raw && _queuedFuture != null) return _queuedFuture!;
    if (_pending == 0 && _savedJson == raw && saveError == null) {
      return Future<void>.value();
    }
    final snapshot = AppSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final done = Completer<void>();
    final future = done.future;
    _pending++;
    _queuedJson = raw;
    _queuedFuture = future;
    _tail = _tail.then<void>((_) async {
      try {
        await store.save(snapshot);
        _savedJson = raw;
        saveError = null;
        _notify();
        done.complete();
      } catch (error, stack) {
        saveError = '$error';
        _notify();
        done.completeError(error, stack);
      } finally {
        _pending--;
        if (identical(_queuedFuture, future)) {
          _queuedFuture = null;
          _queuedJson = null;
        }
      }
    });
    return future;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
