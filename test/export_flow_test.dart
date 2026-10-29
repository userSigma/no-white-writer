import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:no_white_writer/core/chapter_numbering.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/editor_controller.dart';
import 'package:no_white_writer/state/export_controller.dart';

import 'support/app_harness.dart';

class _ExportWriter extends AtomicFileWriter {
  bool failIndex = false;
  bool failExport = false;
  bool holdIndex = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> writeAtomically(File target, String content) async {
    if (failExport && target.path.endsWith('.txt')) {
      await File('${target.path}.tmp').writeAsString('partial export');
      throw const FileSystemException('coordinator export write fault');
    }
    if (holdIndex && target.path.endsWith('book.json')) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    if (failIndex && target.path.endsWith('book.json')) {
      throw const FileSystemException('export flow index failure');
    }
    await super.writeAtomically(target, content);
  }
}

Future<(BookIndex, Volume, ChapterMeta)> _open(AppHarness h) async {
  final summary = await h.app.library.createBook('导出保护');
  final book = await h.app.library.openBook(summary);
  final volume = book.volumes.first;
  final chapter = volume.chapters.first;
  await h.app.editor.open(inBook: book, inVolume: volume, inChapter: chapter);
  h.app.settings.settings.exportDirectory = '${h.root.path}/exports';
  return (book, volume, chapter);
}

Future<File?> _exportCurrent(AppHarness h) => h.app.exporter.export(
  ExportTarget.chapter(
    h.app.editor.book!.id,
    h.app.editor.volume!.id,
    h.app.editor.chapter!.id,
  ),
);

Future<Map<String, List<int>>> _sourceBytes(AppHarness h) async {
  final bytes = <String, List<int>>{};
  await for (final entity in Directory(
    h.app.paths.booksDir,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) bytes[entity.path] = await entity.readAsBytes();
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fault in ['blocked', 'journal', 'chapter-tmp']) {
    test('$fault 停止导出、不修改冲突物，清除已知故障后可重试', () async {
      final h = await createHarness();
      addTearDown(h.dispose);
      final (book, volume, chapter) = await _open(h);
      File? conflict;
      if (fault == 'blocked') {
        h.app.library.blockedBooks.add(book.id);
      } else {
        conflict = File(
          fault == 'journal'
              ? '${h.app.paths.bookDir(book.id)}/.chapter-move.json'
              : '${h.app.paths.chapterFile(book.id, volume.id, chapter.id).path}.tmp',
        );
        await conflict.writeAsString('unresolved conflict');
      }
      final sources = await _sourceBytes(h);
      await expectLater(
        _exportCurrent(h),
        throwsA(
          fault == 'blocked' ? isA<StateError>() : isA<FileSystemException>(),
        ),
      );
      expect(await _sourceBytes(h), sources);
      expect(h.app.library.exporting, isFalse);
      expect(h.app.exporter.busy, isFalse);
      expect(h.app.editor.structuralBusy, isFalse);
      expect(await Directory('${h.root.path}/exports').exists(), isFalse);
      h.app.library.blockedBooks.remove(book.id);
      if (conflict != null) await conflict.delete();
      expect(await _exportCurrent(h), isA<File>());
    });
  }

  for (final scope in ExportScope.values) {
    test('$scope 写失败保留全部源字节、清理残片并释放所有门禁后可重试', () async {
      final writer = _ExportWriter();
      final h = await createHarness(writer: writer);
      addTearDown(h.dispose);
      final (book, volume, chapter) = await _open(h);
      final target = switch (scope) {
        ExportScope.chapter => ExportTarget.chapter(
          book.id,
          volume.id,
          chapter.id,
        ),
        ExportScope.volume => ExportTarget.volume(book.id, volume.id),
        ExportScope.book => ExportTarget.book(book.id),
      };
      final sources = await _sourceBytes(h);
      writer.failExport = true;
      try {
        await expectLater(
          h.app.exporter.export(target),
          throwsA(isA<FileSystemException>()),
        );
        expect(h.app.library.exporting, isFalse);
        expect(h.app.exporter.busy, isFalse);
        expect(h.app.editor.structuralBusy, isFalse);
        expect(await _sourceBytes(h), sources);
        final output = Directory('${h.root.path}/exports');
        final files = await output
            .list(recursive: true, followLinks: false)
            .where((e) => e is File)
            .toList();
        expect(files, isEmpty);
      } finally {
        writer.failExport = false;
      }
      expect(await h.app.exporter.export(target), isA<File>());
      expect(await _sourceBytes(h), sources);
    });
  }

  test('非当前章直接导出，不改变当前绑定、展开偏好与 lastOpened', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final (book, volume, current) = await _open(h);
    final other = await h.app.library.structure.appendChapter(
      book,
      volume,
      title: '非当前章',
    );
    await h.app.chapterStore.writeText(book.id, volume.id, other.id, '非当前正文');
    final prefs = jsonEncode(h.app.settings.settings.toJson());
    final last = h.app.library.lastChapterId(book.id);
    final sources = await _sourceBytes(h);
    final index = await h.app.paths.bookFile(book.id).readAsBytes();
    final file = (await h.app.exporter.export(
      ExportTarget.chapter(book.id, volume.id, other.id),
    ))!;
    expect(await file.readAsString(), '非当前正文\n');
    expect(h.app.editor.chapter!.id, current.id);
    expect(h.app.editor.text.text, '');
    expect(h.app.editor.title.text, current.title);
    expect(jsonEncode(h.app.settings.settings.toJson()), prefs);
    expect(h.app.library.lastChapterId(book.id), last);
    expect(await _sourceBytes(h), sources);
    expect(await h.app.paths.bookFile(book.id).readAsBytes(), index);
  });

  test('卷与书按当前数组顺序导出，独立编号、空名及空卷头正确', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final (book, first, current) = await _open(h);
    h.app.editor.title.text = '第一';
    h.app.editor.text.text = '甲';
    expect(await h.app.editor.flush(), isTrue);
    await h.app.library.structure.renameVolume(book, first, '正文卷');
    final second = await h.app.library.structure.appendChapter(
      book,
      first,
      title: '第二',
    );
    await h.app.chapterStore.writeText(book.id, first.id, second.id, '乙');
    await h.app.library.structure.relocateChapter(book, second.id, first.id, 0);
    final numbered = await h.app.library.structure.appendVolume(book);
    await h.app.library.structure.renameVolume(book, numbered, '');
    final emptyTitle = await h.app.library.structure.appendChapter(
      book,
      numbered,
    );
    await h.app.library.structure.renameChapter(book, emptyTitle, '');
    await h.app.chapterStore.writeText(
      book.id,
      numbered.id,
      emptyTitle.id,
      '丙',
    );
    await h.app.library.structure.setNumbering(
      book,
      numbered,
      const ChapterNumbering(
        enabled: true,
        prefix: 'No.',
        suffix: '',
        start: 7,
        padding: 3,
      ),
    );
    await h.app.library.structure.reorderVolume(book, numbered.id, 0);
    await h.app.library.structure.appendVolume(book, title: '空卷');
    final index = await h.app.paths.bookFile(book.id).readAsBytes();
    final file = (await h.app.exporter.export(
      ExportTarget.volume(book.id, first.id),
    ))!;
    const plain =
        '──── 卷：正文卷 ────\n\n──── 章：第二 ────\n\n乙\n──── 章：第一 ────\n\n甲\n';
    expect(await file.readAsString(), plain);
    final whole = (await h.app.exporter.export(ExportTarget.book(book.id)))!;
    expect(
      await whole.readAsString(),
      '──── 卷：未命名卷 ────\n\n──── 章：No.007 ────\n\n丙\n'
      '$plain──── 卷：空卷 ────\n\n',
    );
    expect(h.app.editor.chapter!.id, current.id);
    expect(emptyTitle.title, '');
    expect(numbered.title, '');
    expect(await h.app.paths.bookFile(book.id).readAsBytes(), index);
  });

  test('无章卷书返回暂无章节且不建输出目录，合法空正文仍可导出', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final (book, volume, chapter) = await _open(h);
    expect(await h.app.editor.close(), isTrue);
    await h.app.library.structure.deleteChapter(book, volume, chapter);
    expect(
      await h.app.exporter.export(ExportTarget.volume(book.id, volume.id)),
      isNull,
    );
    expect(h.app.exporter.message, '暂无章节可导出');
    expect(await h.app.exporter.export(ExportTarget.book(book.id)), isNull);
    expect(await Directory('${h.root.path}/exports').exists(), isFalse);
    final empty = await h.app.library.structure.appendChapter(book, volume);
    final file = (await h.app.exporter.export(
      ExportTarget.chapter(book.id, volume.id, empty.id),
    ))!;
    expect(await file.readAsString(), '\n');
  });

  test('全书最后一章读完前不输出，读失败不留下部分书稿并解锁', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var textReads = 0;
    var fail = true;
    final h = await createHarness(
      exportReadBytes: (file) async {
        if (file.path.endsWith('.txt') && ++textReads == 2 && fail) {
          entered.complete();
          await release.future;
          throw FileSystemException(
            'last chapter injected read failure',
            file.path,
          );
        }
        return file.readAsBytes();
      },
    );
    addTearDown(h.dispose);
    final (book, volume, _) = await _open(h);
    await h.app.library.structure.appendChapter(book, volume);
    final pending = h.app.exporter
        .export(ExportTarget.book(book.id))
        .then<Object?>((file) => file, onError: (Object error) => error);
    try {
      final phase = await Future.any([
        entered.future.then((_) => 'reading'),
        pending.then((_) => 'finished'),
      ]);
      expect(phase, 'reading');
      expect(await Directory('${h.root.path}/exports').exists(), isFalse);
    } finally {
      release.complete();
      await pending;
    }
    expect(await pending, isA<FileSystemException>());
    expect(await Directory('${h.root.path}/exports').exists(), isFalse);
    expect(h.app.library.exporting, isFalse);
    expect(h.app.exporter.busy, isFalse);
    expect(h.app.editor.structuralBusy, isFalse);
    fail = false;
    expect(
      await h.app.exporter.export(ExportTarget.book(book.id)),
      isA<File>(),
    );
  });

  for (final field in ['title', 'body']) {
    test('$field 组合态的常规导出不写草稿和输出、不清理组词范围', () async {
      final h = await createHarness();
      addTearDown(h.dispose);
      final (book, _, _) = await _open(h);
      final index = await h.app.paths.bookFile(book.id).readAsBytes();
      final controller = field == 'title'
          ? h.app.editor.title
          : h.app.editor.text;
      controller.value = const TextEditingValue(
        text: '未定组词',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      expect(await _exportCurrent(h), isNull);
      expect(controller.value.composing, const TextRange(start: 0, end: 4));
      expect(await h.app.paths.bookFile(book.id).readAsBytes(), index);
      expect(await Directory('${h.root.path}/exports').exists(), isFalse);
      expect(h.app.editor.structuralBusy, isFalse);
    });
  }

  test('常规导出遇保存失败不走内存逃生，保留草稿且不产生文件', () async {
    final writer = _ExportWriter();
    final h = await createHarness(writer: writer);
    addTearDown(() async {
      writer.failIndex = false;
      await h.dispose();
    });
    await _open(h);
    h.app.editor.title.text = '保存失败标题';
    h.app.editor.text.text = '保存失败正文';
    writer.failIndex = true;
    expect(await _exportCurrent(h), isNull);
    expect(h.app.editor.state, SaveState.failed);
    expect(h.app.editor.isDirty, isTrue);
    expect(h.app.editor.title.text, '保存失败标题');
    expect(h.app.editor.text.text, '保存失败正文');
    expect(await Directory('${h.root.path}/exports').exists(), isFalse);
    expect(h.app.editor.structuralBusy, isFalse);
  });

  for (final name in [
    'create',
    'open',
    'details',
    'deleteBook',
    'appendChapter',
    'appendVolume',
    'numbering',
    'relocate',
    'reorder',
    'deleteChapter',
    'deleteVolume',
    'renameVolume',
    'renameChapter',
    'renameBook',
    'remember',
    'reload',
    'detailsRead',
    'expanded',
  ]) {
    test('严格快照读取期间拒绝后到的 $name 结构操作', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final h = await createHarness(
        exportReadBytes: (file) async {
          if (file.path.endsWith('.txt')) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return file.readAsBytes();
        },
      );
      addTearDown(h.dispose);
      final (book, volume, chapter) = await _open(h);
      final other = await h.app.library.structure.appendVolume(book);
      final second = await h.app.library.structure.appendChapter(book, volume);
      final library = h.app.library;
      final summary = library.books.single;
      final index = await h.app.paths.bookFile(book.id).readAsBytes();
      final mutations = <String, Future<void> Function()>{
        'create': () async {
          await library.createBook('不应创建');
        },
        'open': () async {
          await library.openBook(summary);
        },
        'details': () => library.updateBookDetails(book, '不准改名', '不准备注'),
        'deleteBook': () => library.deleteBook(summary),
        'appendChapter': () async {
          await library.structure.appendChapter(book, volume);
        },
        'appendVolume': () async {
          await library.structure.appendVolume(book);
        },
        'numbering': () => library.structure.setNumbering(
          book,
          volume,
          const ChapterNumbering(enabled: true),
        ),
        'relocate': () =>
            library.structure.relocateChapter(book, chapter.id, other.id, 0),
        'reorder': () => library.structure.reorderVolume(book, other.id, 0),
        'deleteChapter': () =>
            library.structure.deleteChapter(book, volume, second),
        'deleteVolume': () => library.structure.deleteVolume(book, other),
        'renameVolume': () =>
            library.structure.renameVolume(book, volume, '不准改卷'),
        'renameChapter': () =>
            library.structure.renameChapter(book, second, '不准改章'),
        'renameBook': () => library.renameBook(summary, '不准改书'),
        'remember': () => library.rememberChapter(book.id, second.id),
        'reload': () => library.load(),
        'detailsRead': () async {
          await library.readBookDetails(summary);
        },
        'expanded': () => library.setVolumeExpanded(book, volume.id, true),
      };
      final pending = _exportCurrent(h)
          .then<Object?>((file) => file, onError: (Object error) => error);
      await entered.future;
      try {
        expect(h.app.exporter.busy, isTrue);
        expect(await _exportCurrent(h), isNull);
        await expectLater(mutations[name]!(), throwsA(isA<StateError>()));
        expect(await h.app.paths.bookFile(book.id).readAsBytes(), index);
        expect(h.app.editor.chapter!.id, chapter.id);
      } finally {
        release.complete();
        await pending;
      }
      expect(h.app.exporter.busy, isFalse);
      expect(h.app.editor.structuralBusy, isFalse);
    });
  }

  test('导出等待已经进入的结构提交，快照不读取旧卷名', () async {
    final writer = _ExportWriter();
    var reads = 0;
    final h = await createHarness(
      writer: writer,
      exportReadBytes: (file) async {
        reads++;
        return file.readAsBytes();
      },
    );
    addTearDown(h.dispose);
    final (book, volume, _) = await _open(h);
    writer.holdIndex = true;
    final mutation = h.app.library.structure.renameVolume(
      book,
      volume,
      '提交后的卷',
    );
    await writer.entered.future;
    final pending = _exportCurrent(h);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(reads, 0, reason: '先前结构提交结束前，不能读取 book.json');
    } finally {
      writer.holdIndex = false;
      writer.release.complete();
      await mutation;
      await pending;
    }
    expect((await pending)!.path, contains('提交后的卷'));
    expect(h.app.exporter.busy, isFalse);
  });

  test('已阻止写入的编辑绑定不能通过常规导出绕过保护', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    await _open(h);
    h.app.editor.state = SaveState.blocked;
    expect(await _exportCurrent(h), isNull);
    expect(h.app.editor.state, SaveState.blocked);
    expect(await Directory('${h.root.path}/exports').exists(), isFalse);
    expect(h.app.editor.structuralBusy, isFalse);
  });
}
