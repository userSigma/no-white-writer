import 'core/platform/platform_services.dart';
import 'core/storage/app_paths.dart';
import 'core/storage/book_store.dart';
import 'core/storage/chapter_store.dart';
import 'core/storage/export_service.dart';
import 'core/storage/export_snapshot_store.dart';
import 'state/export_controller.dart';
import 'core/storage/instance_lock.dart';
import 'core/storage/library_store.dart';
import 'state/editor_controller.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';

/// 依赖容器：main() 里装配一次，页面通过构造参数拿到（不做全局单例）。
class AppContext {
  AppContext({
    required this.platform,
    required this.paths,
    required this.libraryStore,
    required this.settingsStore,
    required this.bookStore,
    required this.chapterStore,
    required this.exports,
    required this.settings,
    required this.library,
    required this.editor,
    required this.instanceLock,
    this.exportReader,
    this.recovered = const <RecoveryRecord>[],
  });

  final PlatformServices platform;
  final AppPaths paths;
  final LibraryStore libraryStore;
  final SettingsStore settingsStore;
  final BookStore bookStore;
  final ChapterStore chapterStore;
  final ExportService exports;
  final SettingsController settings;
  final LibraryController library;
  final EditorController editor;
  final ExportSnapshotStore? exportReader;
  ExportController? _exporter;
  ExportController get exporter => _exporter ??= ExportController(
    reader: exportReader ?? ExportSnapshotStore(paths),
    editor: editor,
    library: library,
    settings: settings,
    service: exports,
  );

  final Map<Object, Future<bool> Function()> _uiGuards = {};
  Object registerUiGuard(Future<bool> Function() guard) {
    final token = Object();
    _uiGuards[token] = guard;
    return token;
  }

  void removeUiGuard(Object token) => _uiGuards.remove(token);

  Future<bool> flushUiGuards() async {
    try {
      for (final entry in _uiGuards.entries.toList()) {
        if (_uiGuards.containsKey(entry.key) && !await entry.value()) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 必须被 AppContext 长期引用：锁句柄一旦被 GC 回收，OS 会释放锁，单实例失效。
  final InstanceLock instanceLock;

  /// 启动时崩溃恢复的记录（只含真正恢复的章节，不含"文件缺失"标记）。
  final List<RecoveryRecord> recovered;
}
