import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';

import 'support/app_harness.dart';

class FaultWriter extends AtomicFileWriter {
  bool failIndex = false, failSummary = false, holdIndex = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> writeAtomically(File f, String s) async {
    if (f.path.endsWith('book.json')) {
      if (failIndex) throw const FileSystemException('index fault');
      if (holdIndex) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    }
    if (f.path.endsWith('library.json') && failSummary) {
      throw const FileSystemException('summary fault');
    }
    await super.writeAtomically(f, s);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppHarness, BookSummary, BookIndex, Volume, ChapterMeta)> setup({
    AtomicFileWriter writer = const AtomicFileWriter(),
  }) async {
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('结构');
    final book = await h.app.library.openBook(summary);
    final volume = book.volumes.first;
    final chapter = volume.chapters.first;
    await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
    return (h, summary, book, volume, chapter);
  }

  test('新章默认未命名，非法编号/溢出在创建文件前阻止', () async {
    final (h, summary, book, volume, chapter) = await setup();
    expect(chapter.title, '未命名章节');
    await h.app.library.setNumbering(
      book,
      volume,
      const ChapterNumbering(enabled: true, start: 999999999),
    );
    await expectLater(
      h.app.library.appendChapter(book, volume),
      throwsFormatException,
    );
    expect(volume.chapters, hasLength(1));
    expect(
      Directory(h.app.paths.volumeDir(book.id, volume.id))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt')),
      hasLength(1),
    );
    expect((await h.app.bookStore.load(summary)).allChapters.length, 1);
  });

  test('排序索引失败恢复内存，摘要失败不回滚已提交顺序', () async {
    final writer = FaultWriter();
    final (h, summary, book, volume, a) = await setup(writer: writer);
    final b = await h.app.library.appendChapter(book, volume);
    writer.failIndex = true;
    await expectLater(
      h.app.library.moveChapter(book, volume, b, -1),
      throwsA(isA<FileSystemException>()),
    );
    expect(volume.chapters.first.id, a.id);
    writer.failIndex = false;
    writer.failSummary = true;
    await expectLater(
      h.app.library.moveChapter(book, volume, b, -1),
      throwsA(isA<FileSystemException>()),
    );
    expect(volume.chapters.first.id, b.id);
    expect((await h.app.bookStore.load(summary)).allChapters.first.id, b.id);
  });

  test('跨卷先flush草稿，在途保存后绑定改到目标，后续保存不复活源', () async {
    final writer = FaultWriter();
    final (h, summary, book, source, chapter) = await setup(writer: writer);
    final target = await h.app.library.appendVolume(book);
    h.app.editor.text.text = '第一稿';
    writer.holdIndex = true;
    final save = h.app.editor.saveNow();
    await writer.entered.future;
    h.app.editor.text.text = '最新草稿';
    final Future<bool> moving = Future<bool>.sync(
      () => h.app.editor.runStructure(book, () async {
        await h.app.library.relocateChapter(book, chapter.id, target.id, 0);
      }),
    );
    writer.holdIndex = false;
    writer.release.complete();
    await save;
    expect(await moving, isTrue);
    expect(h.app.editor.volume?.id, target.id);
    expect(h.app.editor.text.text, '最新草稿');
    h.app.editor.text.text = '移动后续写';
    expect(await h.app.editor.flush(), isTrue);
    expect(
      await h.app.chapterStore.fileOf(book.id, source.id, chapter.id).exists(),
      isFalse,
    );
    expect(
      await h.app.chapterStore.readText(book.id, target.id, chapter.id),
      '移动后续写',
    );
    expect(
      (await h.app.bookStore.load(summary)).volumeOfChapter(chapter.id)?.id,
      target.id,
    );
  });

  test('IME组合中不移动；flush失败不执行结构动作且保留草稿', () async {
    final writer = FaultWriter();
    final (h, _, book, _, _) = await setup(writer: writer);
    h.app.editor.title.value = const TextEditingValue(
      text: '组合',
      composing: TextRange(start: 0, end: 2),
    );
    bool called = false;
    expect(
      await h.app.editor.runStructure(book, () async {
        called = true;
      }),
      isFalse,
    );
    expect(called, isFalse);
    expect(
      h.app.editor.title.value.composing,
      const TextRange(start: 0, end: 2),
    );
    h.app.editor.title.text = '未存标题';
    writer.failIndex = true;
    expect(
      await h.app.editor.runStructure(book, () async {
        called = true;
      }),
      isFalse,
    );
    expect(called, isFalse);
    expect(h.app.editor.title.text, '未存标题');
  });

  test('删除提交失败不丢正文，成功后清空绑定并不复活', () async {
    final writer = FaultWriter();
    final (h, _, book, volume, chapter) = await setup(writer: writer);
    h.app.editor.text.text = '保留正文';
    expect(await h.app.editor.flush(), isTrue);
    writer.failIndex = true;
    expect(
      await h.app.editor.runStructure(
        book,
        () => h.app.library.deleteChapter(book, volume, chapter),
      ),
      isFalse,
    );
    expect(
      await h.app.chapterStore.readText(book.id, volume.id, chapter.id),
      '保留正文',
    );
    expect(book.chapterById(chapter.id), isNotNull);
    writer.failIndex = false;
    expect(
      await h.app.editor.runStructure(
        book,
        () => h.app.library.deleteChapter(book, volume, chapter),
      ),
      isTrue,
    );
    await h.app.editor.saveNow(force: true);
    expect(h.app.editor.hasChapter, isFalse);
    expect(
      await h.app.chapterStore.fileOf(book.id, volume.id, chapter.id).exists(),
      isFalse,
    );
  });

  test('书架删除摘要写入失败恢复原目录和卡片，重试仍为同一ID', () async {
    final writer = FaultWriter();
    final (h, summary, book, volume, chapter) = await setup(writer: writer);
    h.app.editor.text.text = '删书失败也要保留';
    await h.app.editor.flush();
    await h.app.editor.close();
    writer.failSummary = true;
    await expectLater(
      h.app.library.deleteBook(summary),
      throwsA(isA<FileSystemException>()),
    );
    expect(h.app.library.books.map((b) => b.id), contains(summary.id));
    expect(
      await h.app.paths
          .chapterFile(book.id, volume.id, chapter.id)
          .readAsString(),
      '删书失败也要保留',
    );
    expect(
      (await h.app.libraryStore.load()).books.map((b) => b.id),
      contains(summary.id),
    );
    writer.failSummary = false;
    await h.app.library.deleteBook(summary);
    expect(h.app.library.books, isEmpty);
    final trashed = Directory(h.app.paths.trashDir)
        .listSync()
        .whereType<Directory>();
    expect(trashed, hasLength(1));
  });

  test('不允许跨书ID或无效拖放索引，不改变任何顺序', () async {
    final (h, _, book, volume, chapter) = await setup();
    await expectLater(
      h.app.library.relocateChapter(book, chapter.id, 'other-book-volume', 0),
      throwsStateError,
    );
    await expectLater(
      h.app.library.relocateChapter(book, chapter.id, volume.id, -1),
      throwsRangeError,
    );
    expect(volume.chapters.single.id, chapter.id);
  });
}
