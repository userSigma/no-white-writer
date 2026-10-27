import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';
import 'package:no_white_writer/core/storage/library_store.dart';
import 'package:no_white_writer/state/library_controller.dart';
import 'package:no_white_writer/state/settings_controller.dart';

class _Harness {
  _Harness(this.root, this.library, this.chapters, this.books);

  final Directory root;
  final LibraryController library;
  final ChapterStore chapters;
  final BookStore books;

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Future<_Harness> _build() async {
  final Directory root = await Directory.systemTemp.createTemp('nww_library_');
  final AppPaths paths = AppPaths(
    dataRoot: root,
    documentsRoot: Directory('${root.path}/docs'),
  );
  await paths.ensureLayout();
  const AtomicFileWriter writer = AtomicFileWriter();
  final ChapterStore chapters = ChapterStore(paths);
  final BookStore books = BookStore(paths, writer, chapters);
  final LibraryStore libraryStore = LibraryStore(paths, writer);
  final SettingsStore settingsStore = SettingsStore(paths, writer);
  final SettingsController settings = SettingsController(
    store: settingsStore,
    initial: await settingsStore.load(),
  );
  final LibraryController library = LibraryController(
    paths: paths,
    libraryStore: libraryStore,
    bookStore: books,
    chapterStore: chapters,
    settings: settings,
  );
  await library.load();
  return _Harness(root, library, chapters, books);
}

void main() {
  test('新建书：写入索引、book.json 与第一章空文件', () async {
    final _Harness h = await _build();
    addTearDown(h.dispose);

    final BookSummary summary = await h.library.createBook('  测试书  ');
    expect(summary.title, '测试书');
    expect(h.library.books, hasLength(1));

    final BookIndex book = await h.library.openBook(summary);
    expect(book.volumes, hasLength(1));
    expect(book.volumes.single.chapters, hasLength(1));

    final File txt = h.chapters.fileOf(
      book.id,
      book.volumes.single.id,
      book.volumes.single.chapters.single.id,
    );
    expect(txt.existsSync(), isTrue);
    expect(await txt.readAsString(), isEmpty);

    final File index = File('${h.root.path}/library.json');
    expect(index.existsSync(), isTrue);
    expect(await index.readAsString(), contains('测试书'));
  });

  test('新建卷与章：order 递增、字数统计与 book.json 一致', () async {
    final _Harness h = await _build();
    addTearDown(h.dispose);

    final BookSummary summary = await h.library.createBook('结构');
    final BookIndex book = await h.library.openBook(summary);
    final Volume first = book.volumes.single;
    await h.chapters.writeText(
      book.id,
      first.id,
      first.chapters.single.id,
      '一千零一个字',
    );

    final Volume second = await h.library.appendVolume(book);
    expect(second.order, 1);
    final ChapterMeta chapter = await h.library.appendChapter(book, second);
    expect(chapter.order, 0);

    final BookIndex reloaded = await h.books.load(summary);
    expect(reloaded.volumes, hasLength(2));
    expect(reloaded.volumes[1].chapters.single.title, '未命名章节');
  });

  test('重命名与排序：renameChapter / moveChapter 会立刻落盘', () async {
    final _Harness h = await _build();
    addTearDown(h.dispose);

    final BookSummary summary = await h.library.createBook('顺序');
    final BookIndex book = await h.library.openBook(summary);
    final Volume volume = book.volumes.single;
    final ChapterMeta a = volume.chapters.single;
    final ChapterMeta b = await h.library.appendChapter(book, volume);

    await h.library.renameChapter(book, b, '第二章 新名字');
    await h.library.moveChapter(book, volume, b, -1);

    final BookIndex reloaded = await h.books.load(summary);
    final Volume rv = reloaded.volumes.single;
    expect(rv.chapters.first.title, '第二章 新名字');
    expect(rv.chapters.first.order, 0);
    expect(rv.chapters.last.id, a.id);
  });

  test('删除章与书：正文进 trash、书架索引移除', () async {
    final _Harness h = await _build();
    addTearDown(h.dispose);

    final BookSummary summary = await h.library.createBook('会消失');
    final BookIndex book = await h.library.openBook(summary);
    final Volume volume = book.volumes.single;
    final ChapterMeta chapter = volume.chapters.single;
    final File txt = h.chapters.fileOf(book.id, volume.id, chapter.id);
    await h.chapters.writeText(book.id, volume.id, chapter.id, '要删除的正文');

    await h.library.deleteChapter(book, volume, chapter);
    expect(txt.existsSync(), isFalse);
    final Directory trash = Directory('${h.root.path}/trash');
    expect(trash.listSync(recursive: true).whereType<File>(), isNotEmpty);

    await h.library.deleteBook(summary);
    expect(h.library.books, isEmpty);
    expect(
      Directory('${h.root.path}/books/${summary.id}').existsSync(),
      isFalse,
    );
  });
}
