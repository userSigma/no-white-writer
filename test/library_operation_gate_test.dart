import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';

import 'support/app_harness.dart';

class _ConcurrencyWriter extends AtomicFileWriter {
  bool holdFirstBookWrite = false;
  bool holdNextLibraryWrite = false;
  int bookWriteFailures = 0;
  int libraryWriteFailures = 0;

  final firstBookWriteEntered = Completer<void>();
  final releaseFirstBookWrite = Completer<void>();
  final libraryWriteEntered = Completer<void>();
  final releaseLibraryWrite = Completer<void>();

  @override
  Future<void> writeAtomically(File target, String content) async {
    if (target.path.endsWith('book.json')) {
      if (bookWriteFailures > 0) {
        bookWriteFailures--;
        throw const FileSystemException('injected book write failure');
      }
      if (holdFirstBookWrite) {
        holdFirstBookWrite = false;
        firstBookWriteEntered.complete();
        await releaseFirstBookWrite.future;
      }
    }
    if (target.path.endsWith('library.json')) {
      if (libraryWriteFailures > 0) {
        libraryWriteFailures--;
        throw const FileSystemException('injected library write failure');
      }
      if (holdNextLibraryWrite) {
        holdNextLibraryWrite = false;
        libraryWriteEntered.complete();
        await releaseLibraryWrite.future;
      }
    }
    await super.writeAtomically(target, content);
  }
}

Future<(BookSummary, BookIndex, Volume, ChapterMeta)> _openChapter(
  AppHarness h,
) async {
  final summary = await h.app.library.createBook('并发保护');
  final book = await h.app.library.openBook(summary);
  final volume = book.volumes.single;
  final chapter = volume.chapters.single;
  await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
  return (summary, book, volume, chapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通结构写重叠时后写不得覆盖先提交的其他字段', () async {
    final writer = _ConcurrencyWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await _openChapter(h);

    writer.holdFirstBookWrite = true;
    final volumeRename = h.app.library.renameVolume(book, volume, '卷名甲');
    await writer.firstBookWriteEntered.future;
    final chapterRename = h.app.library.renameChapter(book, chapter, '章名乙');
    writer.releaseFirstBookWrite.complete();
    await Future.wait<void>([volumeRename, chapterRename]);

    final saved = await h.app.bookStore.load(summary);
    expect(saved.volumes.single.title, '卷名甲', reason: '后到的章名修改不得基于旧快照覆盖先提交的卷名');
    expect(saved.allChapters.single.title, '章名乙');
    expect(book.volumes.single.title, '卷名甲');
    expect(book.allChapters.single.title, '章名乙');
  });

  test('章节摘要保存未完成时导出预约必须等待', () async {
    final writer = _ConcurrencyWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    await _openChapter(h);
    h.app.editor.text.text = '等待摘要保存';

    writer.holdNextLibraryWrite = true;
    final saving = h.app.editor.saveNow();
    await writer.libraryWriteEntered.future;
    var reserved = false;
    final reservation = h.app.library.beginExport().then((_) {
      reserved = true;
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(reserved, isFalse, reason: '摘要仍在写盘时，导出不得完成预约并开始读取快照');
    } finally {
      writer.releaseLibraryWrite.complete();
      await saving;
      await reservation;
      if (h.app.library.exporting) h.app.library.endExport();
    }
  });

  test('写入失败后后续写入和导出预约仍可继续', () async {
    final writer = _ConcurrencyWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await _openChapter(h);

    writer.bookWriteFailures = 1;
    await expectLater(
      h.app.library.renameVolume(book, volume, '失败卷名'),
      throwsA(isA<FileSystemException>()),
    );
    expect(h.app.library.blockedBooks.contains(book.id), isFalse);

    await h.app.library.renameChapter(book, chapter, '失败后的章名');
    await h.app.library.beginExport();
    try {
      expect(h.app.library.exporting, isTrue);
      await expectLater(
        h.app.library.appendVolume(book),
        throwsA(isA<StateError>()),
      );
    } finally {
      h.app.library.endExport();
    }

    final saved = await h.app.bookStore.load(summary);
    expect(saved.volumes.single.title, '未命名卷');
    expect(saved.allChapters.single.title, '失败后的章名');
    expect(h.app.library.exporting, isFalse);
  });

  test('排队写入期间摘要失败不得假回滚已提交索引', () async {
    final writer = _ConcurrencyWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await _openChapter(h);

    writer.holdFirstBookWrite = true;
    writer.libraryWriteFailures = 1;
    final volumeRename = h.app.library.renameVolume(book, volume, '已提交卷名');
    await writer.firstBookWriteEntered.future;
    final chapterRename = h.app.library.renameChapter(book, chapter, '后续章名');
    writer.releaseFirstBookWrite.complete();
    await expectLater(volumeRename, throwsA(isA<FileSystemException>()));
    await chapterRename;

    final saved = await h.app.bookStore.load(summary);
    expect(
      saved.volumes.single.title,
      '已提交卷名',
      reason: '摘要失败不能回滚已提交索引，后续写入也不能将其覆盖',
    );
    expect(saved.allChapters.single.title, '后续章名');
    expect(book.volumes.single.title, saved.volumes.single.title);
    expect(book.allChapters.single.title, saved.allChapters.single.title);
    expect(h.app.library.blockedBooks.contains(book.id), isFalse);
  });

  test('书库控制器关闭后拒绝写入和导出预约', () async {
    final h = await createHarness();
    var disposed = false;
    addTearDown(() async {
      if (!disposed) await h.dispose();
    });
    final (_, book, _, _) = await _openChapter(h);
    await h.dispose();
    disposed = true;

    await expectLater(
      h.app.library.appendVolume(book),
      throwsA(isA<StateError>()),
    );
    await expectLater(h.app.library.beginExport(), throwsA(isA<StateError>()));
    expect(h.app.library.exporting, isFalse);
  });
}
