import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/editor_controller.dart';

import 'support/app_harness.dart';

TextEditingController titleOf(EditorController editor) => editor.title;

class _ControlledWriter extends AtomicFileWriter {
  bool failIndex = false;
  bool failLibrary = false;
  bool holdIndex = false;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> writeAtomically(File target, String content) async {
    if (failLibrary && target.path.endsWith('library.json')) {
      throw const FileSystemException('simulated library write failure');
    }
    if (target.path.endsWith('book.json')) {
      if (failIndex) {
        throw const FileSystemException('simulated index write failure');
      }
      if (holdIndex) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    }
    await super.writeAtomically(target, content);
  }
}

Future<(BookSummary, BookIndex, Volume, ChapterMeta)> openFirst(
  AppHarness h,
) async {
  final BookSummary summary = await h.app.library.createBook(
    '测试作品',
    notes: '备注',
  );
  final BookIndex book = await h.app.library.openBook(summary);
  final Volume volume = book.volumes.first;
  final ChapterMeta chapter = volume.chapters.first;
  await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
  return (summary, book, volume, chapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('撤回到成功保存的正文会立即恢复干净状态', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    await openFirst(h);
    h.app.editor.text.text = '草稿';
    expect(h.app.editor.isDirty, isTrue);
    h.app.editor.text.text = '';
    expect(h.app.editor.isDirty, isFalse);
  });

  test('正文读取失败时阻止保存且不覆盖原字节', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final BookSummary summary = await h.app.library.createBook('读取失败');
    final BookIndex book = await h.app.library.openBook(summary);
    final Volume volume = book.volumes.first;
    final ChapterMeta chapter = volume.chapters.first;
    final File file = h.app.chapterStore.fileOf(book.id, volume.id, chapter.id);
    final List<int> original = <int>[0xFF, 0xFE, 0xFA];
    await file.writeAsBytes(original);

    expect(
      await h.app.editor.open(
        inBook: book,
        inVolume: volume,
        inChapter: chapter,
      ),
      isFalse,
    );
    expect(h.app.editor.state, SaveState.blocked);
    expect(h.app.editor.text.text, isEmpty);
    expect(await h.app.editor.flush(), isFalse);
    await h.app.editor.saveNow(force: true);
    expect(await file.readAsBytes(), original);
  });

  test('标题与正文统一保存，标题不进入 txt 或字数', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await openFirst(h);
    final EditorController editor = h.app.editor;
    titleOf(editor).text = '新章节名';
    editor.text.text = '正文';
    expect(editor.isDirty, isTrue);
    expect(await editor.flush(), isTrue);
    final BookIndex saved = await h.app.bookStore.load(summary);
    expect(saved.allChapters.first.title, '新章节名');
    expect(saved.allChapters.first.wordCount, 2);
    expect(saved.notes, '备注');
    expect(
      await h.app.chapterStore.readText(book.id, volume.id, chapter.id),
      '正文',
    );
    expect(editor.isDirty, isFalse);
  });

  test('只改标题也能保存，空白标题修剪为空串并持久化', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await openFirst(h);
    titleOf(h.app.editor).text = '改过的标题';
    expect(await h.app.editor.flush(), isTrue);
    titleOf(h.app.editor).text = '   ';
    expect(await h.app.editor.flush(), isTrue);
    expect(titleOf(h.app.editor).text, '');
    expect((await h.app.bookStore.load(summary)).allChapters.first.title, '');
    expect(
      await h.app.chapterStore.readText(book.id, volume.id, chapter.id),
      '',
    );
  });

  test('索引失败保留标题正文草稿，flush 失败且可重试', () async {
    final _ControlledWriter writer = _ControlledWriter();
    final AppHarness h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    await openFirst(h);
    titleOf(h.app.editor).text = '尚未保存的标题';
    h.app.editor.text.text = '尚未保存的正文';
    writer.failIndex = true;
    expect(await h.app.editor.flush(), isFalse);
    expect(h.app.editor.state, SaveState.failed);
    expect(titleOf(h.app.editor).text, '尚未保存的标题');
    expect(h.app.editor.text.text, '尚未保存的正文');
    expect(h.app.editor.isDirty, isTrue);
    writer.failIndex = false;
    expect(await h.app.editor.flush(), isTrue);
    expect(h.app.editor.isDirty, isFalse);
  });

  test('flush 等待在途保存并保存期间继续输入的最新快照', () async {
    final _ControlledWriter writer = _ControlledWriter();
    final AppHarness h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final (summary, book, volume, chapter) = await openFirst(h);
    titleOf(h.app.editor).text = '第一版';
    h.app.editor.text.text = '甲';
    writer.holdIndex = true;
    final Future<void> pending = h.app.editor.saveNow();
    await writer.entered.future;
    titleOf(h.app.editor).text = '第二版';
    h.app.editor.text.text = '乙';
    final Future<bool> flush = h.app.editor.flush();
    writer.holdIndex = false;
    writer.release.complete();
    await pending;
    expect(await flush, isTrue);
    expect(
      (await h.app.bookStore.load(summary)).allChapters.first.title,
      '第二版',
    );
    expect(
      await h.app.chapterStore.readText(book.id, volume.id, chapter.id),
      '乙',
    );
  });

  test('标题 IME 组合态跳过普通保存，关窗强制落盘', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final (summary, _, _, _) = await openFirst(h);
    titleOf(h.app.editor).value = const TextEditingValue(
      text: '正在组词',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    await h.app.editor.saveNow();
    expect(
      (await h.app.bookStore.load(summary)).allChapters.first.title,
      '未命名章节',
    );
    expect(h.app.editor.isDirty, isTrue);
    expect(await h.app.editor.flushForExit(), isTrue);
    expect(
      (await h.app.bookStore.load(summary)).allChapters.first.title,
      '正在组词',
    );
  });

  test('切章保存旧草稿，解除绑定后不能再写旧文件', () async {
    final AppHarness h = await createHarness();
    addTearDown(h.dispose);
    final (summary, book, volume, first) = await openFirst(h);
    final ChapterMeta next = await h.app.library.appendChapter(book, volume);
    titleOf(h.app.editor).text = '第一章草稿标题';
    h.app.editor.text.text = '第一章草稿正文';
    await h.app.editor.open(inBook: book, inVolume: volume, inChapter: next);
    expect(
      await h.app.chapterStore.readText(book.id, volume.id, first.id),
      '第一章草稿正文',
    );
    expect(
      (await h.app.bookStore.load(summary)).chapterById(first.id)!.title,
      '第一章草稿标题',
    );
    expect(h.app.editor.text.text, '');
    expect(await h.app.editor.close(), isTrue);
    await h.app.library.deleteChapter(book, volume, next);
    await h.app.editor.saveNow(force: true);
    expect(
      h.app.chapterStore.fileOf(book.id, volume.id, next.id).existsSync(),
      isFalse,
    );
    expect(h.app.editor.hasChapter, isFalse);
  });

  test('创建失败重试只产生一个可见作品，失败的新目录进入 trash', () async {
    final _ControlledWriter writer = _ControlledWriter();
    final AppHarness h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    writer.failLibrary = true;
    await expectLater(
      h.app.library.createBook('重试作品', notes: '草稿'),
      throwsA(isA<FileSystemException>()),
    );
    expect(h.app.library.books, isEmpty);
    expect(Directory(h.app.paths.booksDir).listSync(), isEmpty);
    writer.failLibrary = false;
    await h.app.library.createBook('重试作品', notes: '草稿');
    expect(h.app.library.books, hasLength(1));
  });

  test('作品信息保存失败还原书架摘要和内存作品，重试保留备注', () async {
    final _ControlledWriter writer = _ControlledWriter();
    final AppHarness h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final (summary, book, _, _) = await openFirst(h);
    writer.failLibrary = true;
    await expectLater(
      h.app.library.updateBookDetails(book, '改名草稿', '备注草稿'),
      throwsA(isA<FileSystemException>()),
    );
    expect(book.title, '测试作品');
    expect(book.notes, '备注');
    expect(summary.title, '测试作品');
    writer.failLibrary = false;
    await h.app.library.updateBookDetails(book, '改名草稿', '备注草稿');
    expect((await h.app.bookStore.load(summary)).notes, '备注草稿');
  });

  test('旧作品没有备注时按空字符串序列化', () {
    final BookIndex old = BookIndex.fromJson({'id': 'old', 'title': '旧作品'});
    expect(old.toJson()['notes'], '');
  });

  test('作品备注往返保留换行且不迁移旧 ID 和书名', () {
    final BookIndex book = BookIndex.fromJson({
      'id': 'new',
      'title': '新作品',
      'notes': '第一行\n第二行',
    });
    expect(BookIndex.fromJson(book.toJson()).toJson()['notes'], '第一行\n第二行');
    expect(book.id, 'new');
    expect(book.title, '新作品');
  });

  test('同一文件并发字符串及字节写入按请求顺序完成', () async {
    final Directory dir = await Directory.systemTemp.createTemp('nww_queue_');
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/index.json');
    const AtomicFileWriter writer = AtomicFileWriter();
    final List<Future<void>> writes = <Future<void>>[];
    for (int i = 0; i < 30; i++) {
      writes.add(
        i.isEven
            ? writer.writeAtomically(file, '$i')
            : writer.writeBytesAtomically(file, '$i'.codeUnits),
      );
    }
    await Future.wait(writes);
    expect(await file.readAsString(), '29');
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('失败的原子写不会阻断下一次写入', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'nww_queue_fail_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/index.json');
    await Directory(file.path).create();
    const AtomicFileWriter writer = AtomicFileWriter();
    await expectLater(
      writer.writeAtomically(file, '失败'),
      throwsA(isA<FileSystemException>()),
    );
    await Directory(file.path).delete();
    await writer.writeAtomically(file, '成功');
    expect(await file.readAsString(), '成功');
  });
}
