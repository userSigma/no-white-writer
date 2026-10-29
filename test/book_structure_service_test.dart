import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/state/book_mutation_transaction.dart';

import 'support/app_harness.dart';

class _FaultWriter extends AtomicFileWriter {
  bool failSummary = false;
  bool holdIndex = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> writeAtomically(File file, String contents) async {
    if (holdIndex && file.path.endsWith('book.json')) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    if (failSummary && file.path.endsWith('library.json')) {
      throw const FileSystemException('service summary fault');
    }
    await super.writeAtomically(file, contents);
  }
}

class _UnreadableBookStore extends BookStore {
  _UnreadableBookStore(AppHarness h)
    : super(h.app.paths, const AtomicFileWriter(), h.app.chapterStore);
  bool unreadable = true;

  @override
  Future<BookIndex> load(BookSummary summary) {
    if (unreadable) throw const FileSystemException('service reload fault');
    return super.load(summary);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('structure operations preserve volume/chapter identity', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('对象身份');
    final book = await h.app.library.openBook(summary);
    final originalVolume = book.volumes.single;
    final originalChapter = originalVolume.chapters.single;
    final service = h.app.library.structure;
    await service.renameVolume(book, originalVolume, '改卷名');
    await h.app.library.structure.renameChapter(book, originalChapter, '改章名');
    final target = await service.appendVolume(book, title: '空卷');
    final added = await service.appendChapter(book, originalVolume);
    expect(book.volumes.first, same(originalVolume));
    expect(book.chapterById(originalChapter.id), same(originalChapter));
    expect(book.chapterById(added.id), same(added));
    expect(book.volumes.last, same(target));
    await service.relocateChapter(book, originalChapter.id, target.id, 0);
    expect(book.volumeOfChapter(originalChapter.id), same(target));
    expect(target.chapters.single, same(originalChapter));
    await service.reorderVolume(book, target.id, 0);
    expect(book.volumes.first, same(target));
    expect(book.volumes.last, same(originalVolume));
    await service.deleteChapter(book, originalVolume, added);
    expect(originalVolume.chapters, isEmpty);
    expect(book.chapterById(originalChapter.id), same(originalChapter));
    final persisted = await h.app.bookStore.load(summary);
    expect(persisted.volumes.first.id, target.id);
    expect(persisted.chapterById(originalChapter.id)?.title, '改章名');
  });

  test('structure writes share library FIFO and export barrier', () async {
    final writer = _FaultWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('共享队列');
    final book = await h.app.library.openBook(summary);
    final volume = book.volumes.single;
    final chapter = volume.chapters.single;
    writer.holdIndex = true;
    final first = h.app.library.structure.renameVolume(book, volume, '先写卷');
    await writer.entered.future;
    final second = h.app.library.structure.renameChapter(book, chapter, '后写章');
    final export = h.app.library.beginExport();
    addTearDown(h.app.library.endExport);
    await expectLater(
      h.app.library.structure.appendVolume(book),
      throwsA(isA<StateError>()),
    );
    writer.holdIndex = false;
    writer.release.complete();
    await Future.wait([first, second, export]);
    final persisted = await h.app.bookStore.load(summary);
    expect(persisted.volumes.single.title, '先写卷');
    expect(persisted.allChapters.single.title, '后写章');
    expect(book.volumes.single, same(volume));
    expect(book.allChapters.single, same(chapter));
  });

  test(
    'summary failure follows committed disk and retains references',
    () async {
      final writer = _FaultWriter();
      final h = await createHarness(writer: writer);
      addTearDown(h.dispose);
      final summary = await h.app.library.createBook('恢复');
      final book = await h.app.library.openBook(summary);
      final volume = book.volumes.single;
      final chapter = volume.chapters.single;
      writer.failSummary = true;
      await expectLater(
        h.app.library.structure.renameVolume(book, volume, '已落盘'),
        throwsA(isA<FileSystemException>()),
      );
      expect(volume.title, '已落盘');
      expect(book.volumes.single, same(volume));
      expect(book.allChapters.single, same(chapter));
      expect(h.app.library.blockedBooks, isNot(contains(book.id)));
      writer.failSummary = false;
      await h.app.library.structure.renameChapter(book, chapter, '继续写');
      final persisted = await h.app.bookStore.load(summary);
      expect(persisted.volumes.single.title, '已落盘');
      expect(persisted.allChapters.single.title, '继续写');
    },
  );

  test(
    'unreadable actual state blocks book; successful reload clears block',
    () async {
      final h = await createHarness();
      addTearDown(h.dispose);
      final summary = await h.app.library.createBook('读盘保护');
      final book = await h.app.library.openBook(summary);
      final volume = book.volumes.single;
      final chapter = volume.chapters.single;
      final store = _UnreadableBookStore(h);
      final transaction = BookMutationTransaction(
        bookStore: store,
        findSummary: (_) => summary,
        saveSummary: (_) async {},
        notifyChanged: () {},
      );
      await expectLater(
        transaction.syncActual(book),
        throwsA(isA<FileSystemException>()),
      );
      expect(transaction.blockedBooks, contains(book.id));
      store.unreadable = false;
      await transaction.syncActual(book);
      expect(transaction.blockedBooks, isEmpty);
      expect(book.volumes.single, same(volume));
      expect(book.allChapters.single, same(chapter));
    },
  );
}
