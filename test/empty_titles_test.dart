import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/editor_controller.dart';

import 'support/app_harness.dart';

class _FailIndexWriter extends AtomicFileWriter {
  bool fail = false;
  @override
  Future<void> writeAtomically(File target, String content) async {
    if (fail && target.path.endsWith('book.json')) {
      throw const FileSystemException('empty title index failure');
    }
    await super.writeAtomically(target, content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无编号空章显示占位而不污染原名', () {
    final chapter = ChapterMeta(id: 'c', title: '', order: 0);
    final volume = Volume(id: 'v', title: '', order: 0, chapters: [chapter]);
    expect(displayChapterTitle(volume, chapter), '未命名章节');
    expect(chapter.title, '');
    expect(volume.title, '');
  });

  test('有编号空章只显示编号且没有尾空格', () {
    final chapter = ChapterMeta(id: 'c', title: '', order: 0);
    final volume = Volume(
      id: 'v',
      title: '',
      order: 0,
      chapters: [chapter],
      numbering: const ChapterNumbering(enabled: true),
    );
    expect(displayChapterTitle(volume, chapter), '第1章');
    expect(chapter.title, '');
  });

  test('JSON显式空标题与旧数据缺字段分开处理', () {
    expect(Volume.fromJson({'id': 'v', 'title': ''}).title, '');
    expect(ChapterMeta.fromJson({'id': 'c', 'title': ''}).title, '');
    expect(Volume.fromJson({'id': 'v'}).title, '未命名卷');
    expect(ChapterMeta.fromJson({'id': 'c'}).title, '未命名章');
  });

  test('新建仍保留默认卷章名而非自动创建空名称', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('新建默认名');
    final book = await h.app.library.openBook(summary);
    expect(book.volumes.first.title, '未命名卷');
    expect(book.allChapters.first.title, '未命名章节');
    final volume = await h.app.library.appendVolume(book);
    final chapter = await h.app.library.appendChapter(book, volume);
    expect(volume.title, '未命名卷');
    expect(chapter.title, '未命名章节');
  });

  test('编辑器清空章名落盘且不改正文备份字节', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('空标题正文保护');
    final book = await h.app.library.openBook(summary);
    final volume = book.volumes.first;
    final chapter = volume.chapters.first;
    final file = h.app.chapterStore.fileOf(book.id, volume.id, chapter.id);
    final backup = File('${file.path}.bak');
    final before = await file.readAsBytes();
    final beforeBackup = await backup.exists()
        ? await backup.readAsBytes()
        : null;
    await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
    h.app.editor.title.text = '   ';
    expect(await h.app.editor.flush(), isTrue);
    expect(h.app.editor.title.text, '');
    expect((await h.app.bookStore.load(summary)).allChapters.first.title, '');
    expect(await file.readAsBytes(), before);
    expect(await backup.exists(), beforeBackup != null);
    if (beforeBackup != null) expect(await backup.readAsBytes(), beforeBackup);
    expect(chapter.id, book.allChapters.first.id);
  });

  test('卷和非当前章空名通过结构写入并原样回读', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('结构空名');
    final book = await h.app.library.openBook(summary);
    final volume = book.volumes.first;
    final chapter = volume.chapters.first;
    await h.app.library.renameVolume(book, volume, '   ');
    await h.app.library.renameChapter(book, chapter, '');
    final saved = await h.app.bookStore.load(summary);
    expect(volume.title, '');
    expect(chapter.title, '');
    expect(saved.volumes.first.title, '');
    expect(saved.allChapters.first.title, '');
  });

  test('清空标题写盘失败不复原旧名且能重试', () async {
    final writer = _FailIndexWriter();
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('空名失败');
    final book = await h.app.library.openBook(summary);
    final volume = book.volumes.first;
    final chapter = volume.chapters.first;
    await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
    h.app.editor.title.text = '';
    writer.fail = true;
    try {
      expect(await h.app.editor.flush(), isFalse);
      expect(h.app.editor.title.text, '');
      expect(chapter.title, '未命名章节');
      expect(h.app.editor.state, SaveState.failed);
    } finally {
      writer.fail = false;
    }
    expect(await h.app.editor.flush(), isTrue);
    expect((await h.app.bookStore.load(summary)).allChapters.first.title, '');
  });
}
