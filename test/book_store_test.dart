import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';

class InterruptingWriter extends AtomicFileWriter {
  InterruptingWriter(this.indexFile);

  final File indexFile;
  bool fail = true;

  @override
  Future<void> writeAtomically(File target, String content) {
    if (fail && target.path == indexFile.path) {
      throw StateError('模拟索引写入中断');
    }
    return super.writeAtomically(target, content);
  }
}

void main() {
  late Directory root;
  late AppPaths paths;
  late ChapterStore chapters;
  late BookStore books;

  const String bookId = 'b';
  const String volumeId = 'v';
  const String chapterId = 'c';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nww-book-store-');
    paths = AppPaths(dataRoot: root, documentsRoot: root);
    await paths.ensureLayout();
    chapters = ChapterStore(paths);
    books = BookStore(paths, const AtomicFileWriter(), chapters);
    final File chapter = paths.chapterFile(bookId, volumeId, chapterId);
    await chapter.parent.create(recursive: true);
    await chapter.writeAsString('当前正文', flush: true);
    await File('${chapter.path}.bak').writeAsString('历史备份', flush: true);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  BookSummary summary() => BookSummary(
    id: bookId,
    title: '书架书名',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    coverSeed: 0,
  );

  BookIndex validIndex() => BookIndex(
    id: bookId,
    title: '索引书名',
    volumes: <Volume>[
      Volume(
        id: volumeId,
        title: '原卷名',
        order: 0,
        chapters: <ChapterMeta>[
          ChapterMeta(id: chapterId, title: '原章名', order: 0),
        ],
      ),
    ],
  );

  Future<List<File>> corruptIndexes() async {
    final List<File> files = await Directory(paths.bookDir(bookId))
        .list()
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>()
        .where((File file) => file.path.contains('book.json.corrupt-'))
        .toList();
    return files;
  }

  test('book.json 的书籍 ID 不符时留存原索引并按目录身份重建', () async {
    final Map<String, dynamic> raw = validIndex().toJson()..['id'] = 'other';
    await paths.bookFile(bookId).writeAsString(jsonEncode(raw), flush: true);
    final List<int> original = await paths.bookFile(bookId).readAsBytes();

    final BookIndex loaded = await books.load(summary());

    expect(loaded.id, bookId);
    expect(loaded.title, summary().title);
    expect(loaded.volumes.single.id, volumeId);
    expect(loaded.allChapters.single.id, chapterId);
    expect(loaded.allChapters.single.title, '第 1 章');
    expect(loaded.totalWordCount, 4);
    expect(await paths.bookFile(bookId).readAsBytes(), isNot(original));
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsBytes(), original);
  });

  test('卷列表含非对象条目时不静默丢弃索引内容', () async {
    final Map<String, dynamic> raw = validIndex().toJson()
      ..['volumes'] = <Object?>[null];
    await paths.bookFile(bookId).writeAsString(jsonEncode(raw), flush: true);
    final List<int> original = await paths.bookFile(bookId).readAsBytes();

    final BookIndex loaded = await books.load(summary());

    expect(loaded.allChapters.map((ChapterMeta c) => c.id), <String>[
      chapterId,
    ]);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsBytes(), original);
  });

  test('章节列表含非对象条目时不静默丢弃索引内容', () async {
    final Map<String, dynamic> raw = validIndex().toJson();
    (raw['volumes'] as List<dynamic>).single['chapters'] = <Object?>['broken'];
    await paths.bookFile(bookId).writeAsString(jsonEncode(raw), flush: true);
    final List<int> original = await paths.bookFile(bookId).readAsBytes();

    final BookIndex loaded = await books.load(summary());

    expect(loaded.allChapters.map((ChapterMeta c) => c.id), <String>[
      chapterId,
    ]);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsBytes(), original);
  });

  test('重建写盘失败不覆盖原有效索引或正文，恢复后可重试', () async {
    await books.save(validIndex());
    final List<int> originalIndex = await paths.bookFile(bookId).readAsBytes();
    final File chapter = paths.chapterFile(bookId, volumeId, chapterId);
    final File backup = File('${chapter.path}.bak');
    final List<int> originalText = await chapter.readAsBytes();
    final List<int> originalBackup = await backup.readAsBytes();
    final InterruptingWriter writer = InterruptingWriter(
      paths.bookFile(bookId),
    );
    final BookStore interrupted = BookStore(paths, writer, chapters);

    await expectLater(interrupted.rebuild(summary()), throwsStateError);

    expect(await paths.bookFile(bookId).readAsBytes(), originalIndex);
    expect(await chapter.readAsBytes(), originalText);
    expect(await backup.readAsBytes(), originalBackup);
    expect(await File('${paths.bookFile(bookId).path}.tmp').exists(), isFalse);

    writer.fail = false;
    final BookIndex rebuilt = await interrupted.rebuild(summary());
    expect(rebuilt.id, bookId);
    expect(rebuilt.allChapters.single.id, chapterId);
    expect(await chapter.readAsBytes(), originalText);
    expect(await backup.readAsBytes(), originalBackup);
  });

  test('损坏索引已留存后重建中断，重试仍从正文恢复', () async {
    final Map<String, dynamic> raw = validIndex().toJson()..['id'] = 'other';
    await paths.bookFile(bookId).writeAsString(jsonEncode(raw), flush: true);
    final List<int> corrupt = await paths.bookFile(bookId).readAsBytes();
    final InterruptingWriter writer = InterruptingWriter(
      paths.bookFile(bookId),
    );
    final BookStore interrupted = BookStore(paths, writer, chapters);

    await expectLater(interrupted.load(summary()), throwsStateError);

    expect(await paths.bookFile(bookId).exists(), isFalse);
    final List<File> retained = await corruptIndexes();
    expect(retained, hasLength(1));
    expect(await retained.single.readAsBytes(), corrupt);
    expect(
      await paths.chapterFile(bookId, volumeId, chapterId).readAsString(),
      '当前正文',
    );

    writer.fail = false;
    final BookIndex rebuilt = await interrupted.load(summary());
    expect(rebuilt.id, bookId);
    expect(rebuilt.allChapters.single.id, chapterId);
    expect(await corruptIndexes(), hasLength(1));
  });
}
