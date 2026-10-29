import 'dart:io';

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
import 'package:no_white_writer/state/library_controller.dart';
import 'package:no_white_writer/state/settings_controller.dart';

import 'fake_platform.dart';

class AppHarness {
  AppHarness(this.app, this.root);
  final AppContext app;
  final Directory root;

  Future<void> dispose() async {
    await app.editor.flush();
    app.exporter.dispose();
    app.editor.dispose();
    await app.settings.flush();
    app.settings.dispose();
    app.i18n.dispose();
    app.library.dispose();
    await root.delete(recursive: true);
  }
}

Future<AppHarness> createHarness({
  AtomicFileWriter writer = const AtomicFileWriter(),
  Future<List<int>> Function(File)? exportReadBytes,
}) async {
  final Directory root = await Directory.systemTemp.createTemp('nww_revision_');
  final AppPaths paths = AppPaths(dataRoot: root, documentsRoot: root);
  await paths.ensureLayout();
  final SettingsStore settingsStore = SettingsStore(paths, writer);
  final SettingsController settings = SettingsController(
    store: settingsStore,
    initial: AppSettings(autoIndent: false),
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
  return AppHarness(
    AppContext(
      platform: FakePlatformServices(root: root, documents: root),
      paths: paths,
      libraryStore: libraryStore,
      settingsStore: settingsStore,
      bookStore: books,
      chapterStore: chapters,
      exports: exports,
      exportReader: ExportSnapshotStore(paths, readBytes: exportReadBytes),
      settings: settings,
      library: library,
      editor: editor,
      i18n: i18n,
      instanceLock: InstanceLock('${root.path}/instance.lock'),
    ),
    root,
  );
}
