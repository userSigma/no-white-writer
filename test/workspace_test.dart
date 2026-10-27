import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/workspace_controller.dart';

import 'support/app_harness.dart';

class _FailingWriter extends AtomicFileWriter {
  bool fail = false;
  @override
  Future<void> writeAtomically(File target, String content) async {
    if (fail && target.path.endsWith('book.json')) {
      throw const FileSystemException('simulated workspace write failure');
    }
    await super.writeAtomically(target, content);
  }
}

Future<WorkspaceController> workspace(AppHarness h, BookIndex book) async {
  final WorkspaceController controller = WorkspaceController(
    book: book,
    library: h.app.library,
    editor: h.app.editor,
  );
  addTearDown(controller.dispose);
  expect(await controller.initialize(), isTrue);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次打开选择首章，选章持久化并在重新打开后恢复', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('上次章节');
    final BookIndex book = await h.app.library.openBook(summary);
    final ChapterMeta second = await h.app.library.appendChapter(
      book,
      book.volumes.first,
    );
    final WorkspaceController w = await workspace(h, book);
    expect(w.chapter?.id, book.allChapters.first.id);
    expect(await w.select(book.volumes.first, second), isTrue);
    expect(await w.close(), isTrue);
    await h.app.library.load();
    final BookIndex reopened = await h.app.library.openBook(
      h.app.library.books.single,
    );
    final WorkspaceController next = await workspace(h, reopened);
    expect(next.chapter?.id, second.id);
    expect(
      (await h.app.libraryStore.load()).books.single.lastOpenedChapterId,
      second.id,
    );
  });

  test('上次章节已失效时退回第一章，无章节时正常空态', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('无效章节');
    summary.lastOpenedChapterId = 'missing';
    final BookIndex book = await h.app.library.openBook(summary);
    final WorkspaceController w = await workspace(h, book);
    expect(w.chapter?.id, book.allChapters.first.id);
    expect(await w.close(), isTrue);
    await h.app.library.deleteVolume(book, book.volumes.first);
    expect(await w.initialize(), isTrue);
    expect(w.chapter, isNull);
    expect(h.app.editor.hasChapter, isFalse);
  });

  test('删除当前章前保存，依次选择后章、前章、空态且不复活', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('安全删除');
    final BookIndex book = await h.app.library.openBook(summary);
    final Volume volume = book.volumes.first;
    final ChapterMeta first = volume.chapters.first;
    final ChapterMeta second = await h.app.library.appendChapter(book, volume);
    final ChapterMeta third = await h.app.library.appendChapter(book, volume);
    final WorkspaceController w = await workspace(h, book);
    await w.select(volume, second);
    h.app.editor.title.text = '删除前标题';
    h.app.editor.text.text = '删除前正文';
    expect(
      await w.change(
        () => h.app.library.deleteChapter(book, volume, second),
        deletingIds: <String>{second.id},
      ),
      isTrue,
    );
    expect(w.chapter?.id, third.id);
    expect(
      h.app.chapterStore.fileOf(book.id, volume.id, second.id).existsSync(),
      isFalse,
    );
    expect(
      await w.change(
        () => h.app.library.deleteChapter(book, volume, third),
        deletingIds: <String>{third.id},
      ),
      isTrue,
    );
    expect(w.chapter?.id, first.id);
    expect(
      await w.change(
        () => h.app.library.deleteChapter(book, volume, first),
        deletingIds: <String>{first.id},
      ),
      isTrue,
    );
    expect(w.chapter, isNull);
    await h.app.editor.saveNow(force: true);
    expect(
      h.app.chapterStore.fileOf(book.id, volume.id, first.id).existsSync(),
      isFalse,
    );
    expect((await h.app.bookStore.load(summary)).allChapters, isEmpty);
  });

  test('删除当前卷选相邻卷章节，删除非当前章不切换', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('卷删除');
    final BookIndex book = await h.app.library.openBook(summary);
    final Volume first = book.volumes.first;
    final Volume second = await h.app.library.appendVolume(book);
    final ChapterMeta chapter = await h.app.library.appendChapter(book, second);
    final ChapterMeta extra = await h.app.library.appendChapter(book, second);
    final WorkspaceController w = await workspace(h, book);
    expect(
      await w.change(
        () => h.app.library.deleteVolume(book, first),
        deletingIds: first.chapters.map((ChapterMeta c) => c.id).toSet(),
      ),
      isTrue,
    );
    expect(w.chapter?.id, chapter.id);
    expect(
      await w.change(
        () => h.app.library.deleteChapter(book, second, extra),
        deletingIds: <String>{extra.id},
      ),
      isTrue,
    );
    expect(w.chapter?.id, chapter.id);
  });

  test('草稿保存失败则不执行目录变更或切章', () async {
    final _FailingWriter writer = _FailingWriter();
    final AppHarness h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('失败保护');
    final BookIndex book = await h.app.library.openBook(summary);
    final ChapterMeta next = await h.app.library.appendChapter(
      book,
      book.volumes.first,
    );
    final WorkspaceController w = await workspace(h, book);
    final String original = w.chapter!.id;
    h.app.editor.text.text = '未保存草稿';
    writer.fail = true;
    bool mutated = false;
    expect(
      await w.change(() async {
        mutated = true;
      }),
      isFalse,
    );
    expect(mutated, isFalse);
    expect(await w.select(book.volumes.first, next), isFalse);
    expect(w.chapter?.id, original);
    expect(h.app.editor.text.text, '未保存草稿');
    expect(w.error, isNotNull);
    writer.fail = false;
    expect(await w.select(book.volumes.first, next), isTrue);
  });

  test('目录操作重入被拒绝，创建指定新章后自动选中', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('操作串行');
    final BookIndex book = await h.app.library.openBook(summary);
    final WorkspaceController w = await workspace(h, book);
    final Completer<void> entered = Completer<void>();
    final Completer<void> release = Completer<void>();
    final Future<bool> pending = w.change(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    expect(w.busy, isTrue);
    expect(await w.change(() async => fail('不应重入')), isFalse);
    release.complete();
    expect(await pending, isTrue);
    ChapterMeta? added;
    expect(
      await w.change(() async {
        added = await h.app.library.appendChapter(book, book.volumes.first);
      }, selectAfter: () => added?.id),
      isTrue,
    );
    expect(w.chapter?.id, added!.id);
  });
}
