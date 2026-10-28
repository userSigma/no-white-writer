import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';

import 'app.dart';
import 'app_context.dart';
import 'core/i18n/i18n.dart';
import 'core/logging/app_logger.dart';
import 'core/models.dart';
import 'core/platform/platform_services.dart';
import 'core/storage/app_paths.dart';
import 'core/storage/atomic_file_writer.dart';
import 'core/storage/book_store.dart';
import 'core/storage/chapter_store.dart';
import 'core/storage/export_service.dart';
import 'core/storage/instance_lock.dart';
import 'core/storage/library_store.dart';
import 'state/editor_controller.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'ui/editor_page.dart';
import 'ui/shelf_page.dart';
import 'ui/theme/tokens.dart';

/// 进程入口：装配平台层、日志、单实例锁、存储与控制器（PLAN.md §5.2）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final PlatformServices platform = createPlatformServices();
  final Directory dataRoot = await platform.dataRoot();
  final Directory documentsRoot = await platform.documentsRoot();
  final AppPaths paths = AppPaths(
    dataRoot: dataRoot,
    documentsRoot: documentsRoot,
  );
  await paths.ensureLayout();
  await AppLogger.instance.init(Directory(paths.logsDir));
  AppLogger.instance.info('app.start', <String, Object?>{
    'platform': platform.platformLabel,
    'dataRoot': paths.dataRootPath,
    'pid': pid,
  });

  final InstanceLock lock = InstanceLock(paths.instanceLockFile.path);
  if (!await lock.tryAcquire()) {
    await platform.initialize();
    await platform.setWindowTitle('不白写作已在运行');
    runApp(const _AlreadyRunningApp());
    return;
  }

  const AtomicFileWriter writer = AtomicFileWriter();
  final SettingsStore settingsStore = SettingsStore(paths, writer);
  final AppSettings settings = await settingsStore.load();

  final double? width = settings.windowWidth;
  final double? height = settings.windowHeight;
  final WindowGeometry? geometry = (width != null && height != null)
      ? WindowGeometry(
          x: settings.windowX ?? 0,
          y: settings.windowY ?? 0,
          width: width,
          height: height,
          maximized: settings.windowMaximized,
        )
      : null;
  await platform.initialize(
    geometry: geometry,
    maximized: settings.windowMaximized,
  );
  await platform.setMinimumWindowSize(const Size(900, 600));

  final ChapterStore chapterStore = ChapterStore(paths);
  final BookStore bookStore = BookStore(paths, writer, chapterStore);
  final LibraryStore libraryStore = LibraryStore(paths, writer);
  final ExportService exports = ExportService(paths, writer);

  final SettingsController settingsController = SettingsController(
    store: settingsStore,
    initial: settings,
  );
  final LibraryController library = LibraryController(
    paths: paths,
    libraryStore: libraryStore,
    bookStore: bookStore,
    chapterStore: chapterStore,
    settings: settingsController,
  );
  final EditorController editor = EditorController(
    chapters: chapterStore,
    books: bookStore,
    exports: exports,
    library: library,
    settings: settingsController,
  );

  // i18n：先扫描外部语言包（languages/*.json），再应用持久化的语言选择；
  // 坏语言包逐个记日志跳过，不阻断启动。
  final I18nController i18n = I18nController();
  final List<String> languageErrors = await i18n.loadExternal(
    Directory(paths.languagesDir),
  );
  for (final String error in languageErrors) {
    AppLogger.instance.warn('i18n.pack.skipped', error);
  }
  if (!i18n.applySaved(settings.language)) {
    AppLogger.instance.warn('i18n.language.unknown', settings.language);
  }

  // 崩溃恢复必须在 library.load 之前：恢复后的正文长度会影响书架字数统计。
  final List<RecoveryRecord> recovered = <RecoveryRecord>[];
  final LibraryIndex rawLibrary = await libraryStore.load();
  for (final BookSummary summary in rawLibrary.books) {
    final BookIndex book = await bookStore.load(summary);
    recovered.addAll(await chapterStore.recover(book));
  }
  if (recovered.isNotEmpty) {
    AppLogger.instance.warn('app.recover.applied', <String, Object?>{
      'count': recovered.length,
      'chapters': recovered
          .map(
            (RecoveryRecord record) =>
                '${record.chapterTitle}:${record.source}',
          )
          .join(', '),
    });
  }

  // 崩溃恢复的记录传进 AppContext，书架首帧弹提示（Q12）。
  final List<RecoveryRecord> restored = recovered
      .where((RecoveryRecord record) => record.source != 'missing')
      .toList(growable: false);

  // 恢复后的正文可能与索引里的字数不一致，重建受影响书的统计（不改正文）。
  if (restored.isNotEmpty) {
    final LibraryIndex index = await libraryStore.load();
    final Set<String> affected = restored
        .map((RecoveryRecord record) => record.bookId)
        .toSet();
    for (final BookSummary summary in index.books) {
      if (!affected.contains(summary.id)) continue;
      final BookIndex book = await bookStore.load(summary);
      await bookStore.refreshWordCounts(book);
      summary
        ..volumeCount = book.volumes.length
        ..chapterCount = book.allChapters.length
        ..wordCount = book.totalWordCount
        ..updatedAt = DateTime.now();
    }
    await libraryStore.save(index);
  }

  final AppContext context = AppContext(
    platform: platform,
    paths: paths,
    libraryStore: libraryStore,
    settingsStore: settingsStore,
    bookStore: bookStore,
    chapterStore: chapterStore,
    exports: exports,
    settings: settingsController,
    library: library,
    editor: editor,
    i18n: i18n,
    instanceLock: lock,
    recovered: restored,
  );

  await library.load();

  // 验收辅助：NWW_DEV_PAGE=editor|catalog 从工作区启动，settings 在书架上
  // 自动弹出同一个设置选单；都不影响默认书架入口。
  Widget? devHome;
  final String devPage = Platform.environment['NWW_DEV_PAGE'] ?? '';
  if (devPage == 'settings') {
    devHome = ShelfPage(app: context, autoOpenSettings: true);
  } else if (devPage.isNotEmpty) {
    final List<BookSummary> books = library.books;
    if (books.isNotEmpty) {
      final BookIndex book = await library.openBook(books.first);
      if (devPage == 'editor' || devPage == 'catalog') {
        // catalog 旧验收入口也映射到统一工作区；空作品同样可以打开。
        devHome = EditorPage(app: context, book: book);
        final String devType = Platform.environment['NWW_DEV_TYPE'] ?? '';
        if (devType.isNotEmpty) {
          void prefill() {
            if (!editor.hasChapter || editor.loading) return;
            editor.removeListener(prefill);
            final String text = '${editor.text.text}$devType';
            editor.text.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          }

          editor.addListener(prefill);
        }
      }
    }
  }

  runApp(NoWhiteWriterApp(app: context, home: devHome));
}

/// 第二个实例：不抢锁、不写数据，只提示切回已有的窗口。
class _AlreadyRunningApp extends StatelessWidget {
  const _AlreadyRunningApp();

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: '不白写作已在运行',
      theme: buildFluentTheme(AppThemeData.light),
      darkTheme: buildFluentTheme(AppThemeData.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('zh'),
      localizationsDelegates: FluentLocalizations.localizationsDelegates,
      supportedLocales: FluentLocalizations.supportedLocales,
      home: ScaffoldPage(
        // Builder：这里才是 FluentApp 的主题之下，能取到 FluentTheme。
        content: Builder(
          builder: (BuildContext context) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(FluentIcons.info, size: 40),
                  const SizedBox(height: 16),
                  const Text('不白写作已经在运行了', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(
                    '请从任务栏切回刚才的窗口；这一份实例不会再动磁盘上的作品。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedTextColor(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
