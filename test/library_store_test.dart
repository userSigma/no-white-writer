import 'dart:convert';
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

class InterruptingLibraryWriter extends AtomicFileWriter {
  InterruptingLibraryWriter(this.indexFile);

  final File indexFile;
  bool fail = true;

  @override
  Future<void> writeAtomically(File target, String content) {
    if (fail && target.path == indexFile.path) {
      throw StateError('模拟书架索引写入中断');
    }
    return super.writeAtomically(target, content);
  }
}

void main() {
  late Directory root;
  late AppPaths paths;
  late BookStore books;
  late LibraryStore libraryStore;
  late List<LibraryController> controllers;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nww-library-store-');
    paths = AppPaths(dataRoot: root, documentsRoot: root);
    await paths.ensureLayout();
    final ChapterStore chapters = ChapterStore(paths);
    books = BookStore(paths, const AtomicFileWriter(), chapters);
    libraryStore = LibraryStore(paths, const AtomicFileWriter());
    controllers = <LibraryController>[];
  });

  tearDown(() async {
    for (final LibraryController controller in controllers) {
      controller.dispose();
    }
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<BookIndex> seedBook(String id) async {
    final BookIndex book = BookIndex(
      id: id,
      title: '作品 $id',
      volumes: <Volume>[
        Volume(
          id: 'v',
          title: '第一卷',
          order: 0,
          chapters: <ChapterMeta>[
            ChapterMeta(id: 'c', title: '第一章', order: 0, wordCount: 4),
          ],
        ),
      ],
    );
    await books.save(book);
    final File chapter = paths.chapterFile(id, 'v', 'c');
    await chapter.parent.create(recursive: true);
    await chapter.writeAsString('当前正文', flush: true);
    return book;
  }

  BookSummary summaryOf(BookIndex book, {DateTime? updatedAt}) {
    final DateTime now = updatedAt ?? DateTime(2026);
    return BookSummary(
      id: book.id,
      title: book.title,
      createdAt: DateTime(2025),
      updatedAt: now,
      coverSeed: 42,
      volumeCount: book.volumes.length,
      chapterCount: book.allChapters.length,
      wordCount: book.totalWordCount,
    );
  }

  Future<LibraryController> loadController([
    AtomicFileWriter writer = const AtomicFileWriter(),
  ]) async {
    final SettingsStore settingsStore = SettingsStore(paths, writer);
    final LibraryController controller = LibraryController(
      paths: paths,
      libraryStore: LibraryStore(paths, writer),
      bookStore: books,
      chapterStore: ChapterStore(paths),
      settings: SettingsController(
        store: settingsStore,
        initial: AppSettings(),
      ),
    );
    controllers.add(controller);
    await controller.load();
    return controller;
  }

  Future<void> writeLibrary(List<Object?> entries) async {
    await paths.libraryFile.writeAsString(
      jsonEncode(<String, Object?>{'schemaVersion': 1, 'books': entries}),
      flush: true,
    );
  }

  Future<List<File>> corruptIndexes() async {
    return root
        .list()
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>()
        .where((File file) => file.path.contains('library.json.corrupt-'))
        .toList();
  }

  test('library.json 无法解析时扫描作品目录重建书架', () async {
    await seedBook('b');
    await paths.libraryFile.writeAsString('{broken', flush: true);

    final LibraryController controller = await loadController();

    expect(controller.error, isNull);
    expect(controller.books.single.id, 'b');
    expect(controller.books.single.title, '作品 b');
    expect(controller.books.single.chapterCount, 1);
    expect(controller.books.single.wordCount, 4);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsString(), '{broken');
    final Map<String, dynamic> persisted = jsonDecode(
      await paths.libraryFile.readAsString(),
    ) as Map<String, dynamic>;
    expect((persisted['books'] as List<dynamic>).single['id'], 'b');
  });

  test('书架摘要指向不存在目录时按真实作品身份重建', () async {
    final BookIndex actual = await seedBook('b');
    final BookIndex ghost = BookIndex(id: 'ghost', title: '不存在的作品');
    await writeLibrary(<Object?>[summaryOf(ghost).toJson()]);

    final LibraryController controller = await loadController();

    expect(controller.error, isNull);
    expect(controller.books.map((BookSummary b) => b.id), <String>['b']);
    expect(controller.books.single.title, actual.title);
  });

  test('books 含非对象条目时不静默省略真实作品', () async {
    final BookIndex first = await seedBook('b');
    await seedBook('c');
    await writeLibrary(<Object?>[summaryOf(first).toJson(), null]);

    final LibraryController controller = await loadController();

    expect(controller.error, isNull);
    expect(controller.books.map((BookSummary b) => b.id).toSet(), <String>{
      'b',
      'c',
    });
    expect(await corruptIndexes(), hasLength(1));
  });

  test('目录与有效书架一致时不重写索引', () async {
    final BookIndex book = await seedBook('b');
    await libraryStore.save(
      LibraryIndex(books: <BookSummary>[summaryOf(book)]),
    );
    final List<int> original = await paths.libraryFile.readAsBytes();
    final InterruptingLibraryWriter writer = InterruptingLibraryWriter(
      paths.libraryFile,
    );

    final LibraryController controller = await loadController(writer);

    expect(controller.error, isNull);
    expect(controller.books.single.id, 'b');
    expect(await paths.libraryFile.readAsBytes(), original);
  });

  test('重建写盘失败不覆盖已留存的原书架，恢复后可重试', () async {
    await seedBook('b');
    final BookIndex ghost = BookIndex(id: 'ghost', title: '旧摘要');
    await writeLibrary(<Object?>[summaryOf(ghost).toJson()]);
    final List<int> original = await paths.libraryFile.readAsBytes();
    final List<int> chapter = await paths
        .chapterFile('b', 'v', 'c')
        .readAsBytes();
    final InterruptingLibraryWriter writer = InterruptingLibraryWriter(
      paths.libraryFile,
    );

    final LibraryController controller = await loadController(writer);

    expect(controller.error, contains('模拟书架索引写入中断'));
    expect(await paths.libraryFile.exists(), isFalse);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsBytes(), original);
    expect(await paths.chapterFile('b', 'v', 'c').readAsBytes(), chapter);

    writer.fail = false;
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.books.single.id, 'b');
  });

  test('损坏书架留存后重建中断，重试仍从作品目录恢复', () async {
    await seedBook('b');
    await paths.libraryFile.writeAsString('{broken', flush: true);
    final InterruptingLibraryWriter writer = InterruptingLibraryWriter(
      paths.libraryFile,
    );

    final LibraryController controller = await loadController(writer);

    expect(controller.error, contains('模拟书架索引写入中断'));
    expect(await paths.libraryFile.exists(), isFalse);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsString(), '{broken');

    writer.fail = false;
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.books.single.id, 'b');
    expect(await corruptIndexes(), hasLength(1));
  });
}
