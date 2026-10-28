import 'dart:io';

import '../platform/path_utils.dart';

enum LogLevel { info, warn, error }

/// 滚动日志（PLAN.md §7.7）：单文件 512 KB，保留 `app.log` + `app.log.1..4`。
/// 同步写：量小、退出路径也要可靠，宁可简单。
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int maxBytes = 512 * 1024;
  static const int maxFiles = 5;

  Directory? _dir;

  String get directoryPath => _dir?.path ?? '';

  Future<void> init(Directory logDir) async {
    _dir = logDir;
    await logDir.create(recursive: true);
  }

  void info(String event, [Object? details]) =>
      _write(LogLevel.info, event, details);
  void warn(String event, [Object? details]) =>
      _write(LogLevel.warn, event, details);
  void error(String event, [Object? details]) =>
      _write(LogLevel.error, event, details);

  void _write(LogLevel level, String event, Object? details) {
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final File file = File(pathJoin(dir.path, 'app.log'));
      _rotateIfNeeded(file);
      final String raw = details is String
          ? details
          : (details?.toString() ?? '');
      final String detail = raw.replaceAll(RegExp(r'[\r\n]+'), ' / ');
      final String line =
          '${_timestamp(DateTime.now())} | '
          '${level.name.toUpperCase().padRight(5)} | $event'
          '${detail.isEmpty ? '' : ' | $detail'}\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // 日志自身失败不向上抛：写日志绝不能影响主流程。
    }
  }

  void _rotateIfNeeded(File file) {
    if (!file.existsSync()) return;
    if (file.lengthSync() < maxBytes) return;
    final Directory dir = file.parent;
    final File oldest = File(pathJoin(dir.path, 'app.log.${maxFiles - 1}'));
    if (oldest.existsSync()) oldest.deleteSync();
    for (int i = maxFiles - 2; i >= 1; i--) {
      final File from = File(pathJoin(dir.path, 'app.log.$i'));
      if (from.existsSync()) {
        from.renameSync(pathJoin(dir.path, 'app.log.${i + 1}'));
      }
    }
    file.renameSync(pathJoin(dir.path, 'app.log.1'));
  }

  static String _timestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }
}
