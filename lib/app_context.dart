import 'core/i18n/i18n.dart';
import 'core/platform/platform_services.dart';
import 'core/storage/app_paths.dart';
import 'core/storage/book_store.dart';
import 'core/storage/chapter_store.dart';
import 'core/storage/export_service.dart';
import 'core/storage/instance_lock.dart';
import 'core/storage/library_store.dart';
import 'state/editor_controller.dart';
import 'state/export_controller.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'state/ui_operation_guards.dart';

/// 组合根与应用生命周期持有的依赖；页面只接收各自实际使用的能力。
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
    required this.i18n,
    required this.instanceLock,
    required this.exporter,
    this.recoveredChapterCount = 0,
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
  final I18nController i18n;
  final ExportController exporter;

  final UiOperationGuards uiGuards = UiOperationGuards();

  /// 必须被 AppContext 长期引用：锁句柄一旦被 GC 回收，OS 会释放锁，单实例失效。
  final InstanceLock instanceLock;

  /// 启动时真正恢复的章节数量（不含"文件缺失"标记）。
  final int recoveredChapterCount;
}
