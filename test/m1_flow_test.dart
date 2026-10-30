import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:no_white_writer/app_context.dart';
import 'package:no_white_writer/core/i18n/i18n.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';
import 'package:no_white_writer/core/storage/export_service.dart';
import 'package:no_white_writer/core/storage/export_snapshot_store.dart';
import 'package:no_white_writer/core/storage/instance_lock.dart';
import 'package:no_white_writer/core/storage/library_store.dart';
import 'package:no_white_writer/state/editor_controller.dart';
import 'package:no_white_writer/state/export_controller.dart';
import 'package:no_white_writer/state/library_controller.dart';
import 'package:no_white_writer/state/settings_controller.dart';

import 'support/page_harness.dart';
import 'support/fake_platform.dart';

class _Harness {
  _Harness(this.app, this.dir);

  final AppContext app;
  final Directory dir;
}

/// 注意：真实的文件 IO 不能放在 testWidgets 的 fake-async 区里 await，
/// 否则测试会一直挂着；统一用 `tester.runAsync` 包住。
Future<_Harness> _buildHarness() async {
  final Directory dir = await Directory.systemTemp.createTemp('nww_test_');
  final AppPaths paths = AppPaths(dataRoot: dir, documentsRoot: dir);
  await paths.ensureLayout();

  const AtomicFileWriter writer = AtomicFileWriter();
  final SettingsStore settingsStore = SettingsStore(paths, writer);
  final SettingsController settings = SettingsController(
    store: settingsStore,
    initial: AppSettings(),
  );
  final ChapterStore chapters = ChapterStore(paths);
  final BookStore books = BookStore(paths, writer, chapters);
  final LibraryStore libraryStore = LibraryStore(paths, writer);
  final LibraryController library = LibraryController(
    paths: paths,
    libraryStore: libraryStore,
    bookStore: books,
    chapterStore: chapters,
    settings: settings,
  );
  final ExportService exports = ExportService(paths, writer);
  final EditorController editor = EditorController(
    chapters: chapters,
    books: books,
    exports: exports,
    library: library,
    settings: settings,
  );
  final I18nController i18n = I18nController();
  await library.load();

  final AppContext app = AppContext(
    platform: FakePlatformServices(root: dir, documents: dir),
    paths: paths,
    libraryStore: libraryStore,
    settingsStore: settingsStore,
    bookStore: books,
    chapterStore: chapters,
    exports: exports,
    settings: settings,
    library: library,
    editor: editor,
    i18n: i18n,
    exporter: ExportController(
      reader: ExportSnapshotStore(paths),
      editor: editor,
      library: library,
      settings: settings,
      service: exports,
    ),
    instanceLock: InstanceLock('${dir.path}/instance.lock'),
  );
  return _Harness(app, dir);
}

void main() {
  testWidgets('书架在 1280×820 下头部操作可见、无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _Harness h = (await tester.runAsync(_buildHarness))!;
    addTearDown(() async {
      try {
        await h.dir.delete(recursive: true);
      } on Object {
        // 临时目录清理失败不影响测试结论。
      }
    });
    await tester.runAsync(() => h.app.library.createBook('验收书'));

    await tester.pumpWidget(FluentApp(home: shelfPage(app: h.app)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('新建'), findsOneWidget);
    expect(find.byType(ComboBox<LibrarySort>), findsOneWidget);
    final List<String?> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data)
        .toList();
    debugPrint('SHELF TEXTS: $texts');
    expect(
      texts.any((String? t) => t != null && t.contains('本 ·')),
      isTrue,
      reason: '头部应显示「N 本 · 排序」副标题',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑器停止输入 5 秒后自动落盘', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _Harness h = (await tester.runAsync(_buildHarness))!;
    addTearDown(() async {
      try {
        await h.dir.delete(recursive: true);
      } on Object {
        // 同上。
      }
    });

    final BookSummary summary = (await tester.runAsync(
      () => h.app.library.createBook('自动保存书'),
    ))!;
    final BookIndex book = (await tester.runAsync(
      () => h.app.library.openBook(summary),
    ))!;
    final Volume volume = book.volumes.first;
    final ChapterMeta chapter = volume.chapters.first;

    await tester.pumpWidget(
      FluentApp(
        home: editorPage(
          app: h.app,
          book: book,
          volume: volume,
          chapter: chapter,
        ),
      ),
    );
    await tester.pump();
    // 等 initState 里的 open() 真正完成（真实 IO），否则它会覆盖随后输入的文字。
    for (int i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final Finder body = find.byKey(const ValueKey('chapter-body'));
      if (h.app.editor.state == SaveState.clean &&
          !h.app.editor.isDirty &&
          body.evaluate().isNotEmpty &&
          !tester.widget<TextField>(body).readOnly) {
        break;
      }
    }
    expect(h.app.editor.state, SaveState.clean);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chapter-body')))
          .readOnly,
      isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('chapter-body')),
      '　　第一段测试文本。',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(h.app.editor.isDirty, isTrue);

    await tester.pump(const Duration(seconds: 5));
    // 自动保存是真实文件 IO：让事件循环转几圈，直到不再处于 saving。
    for (int i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final SaveState s = h.app.editor.state;
      if (!h.app.editor.isDirty &&
          s != SaveState.saving &&
          s != SaveState.dirty) {
        break;
      }
    }
    debugPrint(
      'EDITOR state=${h.app.editor.state.name} dirty=${h.app.editor.isDirty} '
      'text=${h.app.editor.text.text.replaceAll('\n', r'\n')} '
      'error=${h.app.editor.errorMessage}',
    );

    final String? saved = await tester.runAsync<String?>(
      () => h.app.chapterStore.readText(book.id, volume.id, chapter.id),
    );
    expect(saved, '　　第一段测试文本。');
    expect(h.app.editor.isDirty, isFalse);
    expect(tester.takeException(), isNull);

    // 卸载页面，释放 TextField 的光标闪烁 Timer（否则测试结束会报 timersPending）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  });
}
