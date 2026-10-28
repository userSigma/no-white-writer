import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/app_harness.dart';
import 'support/fake_platform.dart';
import 'support/widget_harness.dart';

/// G：真实章／卷／书菜单导出，全部以菜单打开时捕获的稳定 ID 为目标。
void main() {
  late Directory out;

  Future<void> useOut(WidgetTester tester, AppHarness h) async {
    out = Directory('${h.root.path}/exports')..createSync();
    h.app.settings.setExportDirectory(out.path);
    await tester.runAsync(h.app.settings.flush);
  }

  List<File> outFiles() =>
      out
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  List<String> outNames() =>
      outFiles().map((f) => f.uri.pathSegments.last).toList();

  Map<String, String> outTexts() => {
    for (final file in outFiles()) file.path: file.readAsStringSync(),
  };

  Future<(AppHarness, BookIndex)> seed(
    WidgetTester tester, {
    required String bookTitle,
    required List<String> chapterTitles,
    required List<String> bodies,
    AtomicFileWriter writer = const AtomicFileWriter(),
    Future<List<int>> Function(File)? exportReadBytes,
  }) async {
    final h = await widgetHarness(
      tester,
      writer: writer,
      exportReadBytes: exportReadBytes,
    );
    await useOut(tester, h);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook(bookTitle);
      final opening = await h.app.library.openBook(summary);
      final volume = opening.volumes.first;
      await h.app.library.setVolumeExpanded(opening, volume.id, true);
      await h.app.library.renameVolume(opening, volume, '第1卷');
      // 新建作品自带一个默认章，直接复用为第一，其余追加。
      final existing = volume.chapters.first;
      await h.app.library.renameChapter(opening, existing, chapterTitles.first);
      await h.app.chapterStore.writeText(
        opening.id,
        volume.id,
        existing.id,
        bodies.first,
      );
      for (var i = 1; i < chapterTitles.length; i++) {
        final chapter = await h.app.library.appendChapter(opening, volume);
        await h.app.library.renameChapter(opening, chapter, chapterTitles[i]);
        // 正文按存储层预置，导出只读磁盘，绕开编辑器防抖时序。
        await h.app.chapterStore.writeText(
          opening.id,
          volume.id,
          chapter.id,
          bodies[i],
        );
      }
      // 库对象不保证同步到旧实例，导出前重新从磁盘加载。
      final fresh = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: fresh,
        inVolume: fresh.volumes.first,
        inChapter: fresh.volumes.first.chapters.first,
      );
      return fresh;
    }))!;
    return (h, book);
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    AppHarness h,
    BookIndex book,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
  }

  Future<void> openChapterMenu(WidgetTester tester, String chapterId) async {
    await tester.tap(find.byKey(ValueKey('chapter-menu-$chapterId')));
    await tester.pumpAndSettle();
  }

  List<String> sourceBytes(AppHarness h, String bookId) {
    final dir = Directory('${h.root.path}/books/$bookId');
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.txt') || f.path.endsWith('.bak'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: '原稿字节保护断言不能对空文件集通过');
    return [
      for (final f in files) '${f.path}|${f.readAsBytesSync().join(',')}',
    ];
  }

  testWidgets('章菜单导出当前章且不改绑定、偏好、原稿字节', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单章导出',
      chapterTitles: ['第一章甲', '第二章乙'],
      bodies: ['甲\n乙\n丙', '丁'],
    );
    final current = book.allChapters.toList().first;
    await pumpEditor(tester, h, book);
    await tester.runAsync(
      () => h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: current,
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final lastOpened = h.app.settings.settings.lastOpenedBookId;
    final expanded = h.app.settings.settings.expandedVolumes.map(
      (id, volumes) => MapEntry(id, List<String>.of(volumes)),
    );
    final before = sourceBytes(h, book.id);

    await openChapterMenu(tester, current.id);
    expect(find.text('导出本章'), findsOneWidget);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('export-result-path'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(outNames(), hasLength(1));
    final text = outTexts().values.single;
    expect(text, '甲\n乙\n丙\n');
    expect(find.byKey(const ValueKey('export-result-path')), findsOneWidget);
    expect(h.app.editor.chapter!.id, current.id);
    expect(h.app.settings.settings.lastOpenedBookId, lastOpened);
    expect(h.app.settings.settings.expandedVolumes, expanded);
    expect(sourceBytes(h, book.id), before);

    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('非当前章的菜单导出不换绑定也不改原稿', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单非当前章',
      chapterTitles: ['甲章', '乙章'],
      bodies: ['一', '二'],
    );
    final first = book.allChapters.toList()[0];
    final second = book.allChapters.toList()[1];
    await pumpEditor(tester, h, book);
    await tester.runAsync(
      () => h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: first,
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final before = sourceBytes(h, book.id);

    await openChapterMenu(tester, second.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('export-result-path'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(outTexts().values.single, '二\n');
    expect(h.app.editor.chapter!.id, first.id);
    expect(h.app.editor.title.text, first.title);
    expect(sourceBytes(h, book.id), before);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('卷菜单导出整卷且按卷内顺序分章', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单卷导出',
      chapterTitles: ['一', '二'],
      bodies: ['甲', '乙'],
    );
    final volume = book.volumes.first;
    await pumpEditor(tester, h, book);
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    expect(find.text('导出本卷'), findsOneWidget);
    await tester.tap(find.text('导出本卷'));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('export-result-path'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(
      outTexts().values.single,
      '──── 卷：第1卷 ────\n\n──── 章：一 ────\n\n甲\n──── 章：二 ────\n\n乙\n',
    );
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('书架书籍菜单导出全书且保留空卷头', (tester) async {
    final h = await widgetHarness(tester);
    await useOut(tester, h);
    final summary = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('书架导出书');
      final index = await h.app.library.openBook(s);
      final first = index.volumes.first;
      await h.app.library.setVolumeExpanded(index, first.id, true);
      await h.app.library.renameVolume(index, first, '第一卷');
      final chapter = first.chapters.first;
      await h.app.library.renameChapter(index, chapter, '首章');
      await h.app.chapterStore.writeText(index.id, first.id, chapter.id, '正文');
      await h.app.editor.open(
        inBook: index,
        inVolume: first,
        inChapter: chapter,
      );
      await h.app.library.appendVolume(index, title: '空卷');
      return s;
    }))!;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('book-menu-${summary.id}')));
    await tester.pumpAndSettle();
    expect(find.text('导出本书'), findsOneWidget);
    await tester.tap(find.text('导出本书'));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('export-result-path'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(
      outTexts().values.single,
      '──── 卷：第一卷 ────\n\n──── 章：首章 ────\n\n正文\n──── 卷：空卷 ────\n\n',
    );
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('没有章节时书籍菜单只提示暂无章节可导出', (tester) async {
    final h = await widgetHarness(tester);
    await useOut(tester, h);
    final summary = (await tester.runAsync(() async {
      final created = await h.app.library.createBook('空书导出');
      final index = await h.app.library.openBook(created);
      final volume = index.volumes.first;
      await h.app.library.deleteChapter(index, volume, volume.chapters.first);
      return created;
    }))!;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('book-menu-${summary.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出本书'));
    await finishIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('暂无章节可导出'), findsOneWidget);
    expect(outNames(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('写盘失败显示具体问题，修好后重试成功', (tester) async {
    final writer = _FaultWriter();
    final h = await widgetHarness(tester, writer: writer);
    await useOut(tester, h);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('导出重试');
      final index = await h.app.library.openBook(s);
      await h.app.library.setVolumeExpanded(
        index,
        index.volumes.first.id,
        true,
      );
      final chapter = await h.app.library.appendChapter(
        index,
        index.volumes.first,
      );
      await h.app.chapterStore.writeText(
        index.id,
        index.volumes.first.id,
        chapter.id,
        '重试正文',
      );
      await h.app.editor.open(
        inBook: index,
        inVolume: index.volumes.first,
        inChapter: chapter,
      );
      return index;
    }))!;
    await pumpEditor(tester, h, book);
    final chapter = book.allChapters.toList().last;

    writer.fail = true;
    await openChapterMenu(tester, chapter.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(tester, until: () => find.text('重试').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.textContaining('导出本章失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-retry')), findsOneWidget);
    expect(outNames(), isEmpty);
    expect(
      out.listSync(recursive: true).where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    expect(h.app.exporter.busy, isFalse);

    writer.fail = false;
    await tester.tap(find.byKey(const ValueKey('export-retry')));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    expect(outTexts().values.single, '重试正文\n');
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('组词中菜单导出被拒绝且不留文件', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '组词导出',
      chapterTitles: ['组词章'],
      bodies: ['正文'],
    );
    final chapter = book.allChapters.toList().first;
    await pumpEditor(tester, h, book);
    h.app.editor.title.value = const TextEditingValue(
      text: '组词中',
      composing: TextRange(start: 0, end: 3),
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pump();
    expect(h.app.editor.isComposing, isTrue);

    expect(
      tester
          .widget<IconButton>(
            find.byKey(ValueKey('chapter-menu-${chapter.id}')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
    await tester.pumpAndSettle();
    expect(find.text('导出本章'), findsNothing);
    expect(
      h.app.editor.title.value.composing,
      const TextRange(start: 0, end: 3),
    );
    expect(outNames(), isEmpty);
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('菜单打开后目标被删，导出失败而不是换一章', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '删后导出',
      chapterTitles: ['留下的章', '被删的章'],
      bodies: ['留', '删'],
    );
    final victim = book.allChapters.toList()[1];
    await pumpEditor(tester, h, book);
    await openChapterMenu(tester, victim.id);
    await tester.runAsync(() async {
      await h.app.library.deleteChapter(book, book.volumes.first, victim);
    });
    await tester.tap(find.text('导出本章'));
    await finishIo(tester, until: () => find.text('重试').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(find.textContaining('导出本章失败'), findsOneWidget);
    expect(outTexts().values.where((t) => t.contains('留')).toList(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('标题组词中导出被拒后恢复组词可正常导出', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '组词恢复导出',
      chapterTitles: ['恢复章'],
      bodies: ['恢复正文'],
    );
    final chapter = book.allChapters.toList().first;
    await pumpEditor(tester, h, book);
    h.app.editor.title.value = const TextEditingValue(
      text: '恢复中',
      composing: TextRange(start: 0, end: 3),
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
    await tester.pumpAndSettle();
    expect(find.text('导出本章'), findsNothing);
    expect(
      h.app.editor.title.value.composing,
      const TextRange(start: 0, end: 3),
    );
    expect(outFiles(), isEmpty);

    await tester.runAsync(() async {
      h.app.editor.title.value = const TextEditingValue(
        text: '恢复完成',
        selection: TextSelection.collapsed(offset: 4),
      );
      await h.app.editor.flush();
    });
    await finishIo(tester, until: () => editorReady(tester));
    await openChapterMenu(tester, chapter.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('export-result-path'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(outTexts().values.single, '恢复正文\n');
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('空标题与自动编号在菜单导出里用展示名', (tester) async {
    final h = await widgetHarness(tester);
    await useOut(tester, h);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('菜单空名');
      final opening = await h.app.library.openBook(summary);
      final volume = opening.volumes.first;
      await h.app.library.setVolumeExpanded(opening, volume.id, true);
      await h.app.library.renameVolume(opening, volume, '');
      await h.app.library.renameChapter(opening, volume.chapters.first, '');
      await h.app.chapterStore.writeText(
        opening.id,
        volume.id,
        volume.chapters.first.id,
        '甲',
      );
      await h.app.library.setNumbering(
        opening,
        volume,
        const ChapterNumbering(
          enabled: true,
          start: 7,
          prefix: 'No.',
          suffix: '',
        ),
      );
      final second = await h.app.library.appendVolume(opening);
      await h.app.library.renameVolume(opening, second, '');
      final other = await h.app.library.appendChapter(opening, second);
      await h.app.library.renameChapter(opening, other, '');
      await h.app.chapterStore.writeText(opening.id, second.id, other.id, '乙');
      await h.app.library.setNumbering(
        opening,
        second,
        const ChapterNumbering(
          enabled: true,
          start: 20,
          prefix: 'Next.',
          suffix: '',
        ),
      );
      await h.app.library.setVolumeExpanded(opening, second.id, true);
      final fresh = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: fresh,
        inVolume: fresh.volumes.first,
        inChapter: fresh.volumes.first.chapters.first,
      );
      return fresh;
    }))!;
    await pumpEditor(tester, h, book);
    final chapter = book.allChapters.toList().first;

    await openChapterMenu(tester, chapter.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(outNames().single, 'No.7.txt');
    expect(outTexts().values.single, '甲\n');
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    final before = sourceBytes(h, book.id);
    await openChapterMenu(tester, book.volumes.last.chapters.single.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    expect(outNames(), containsAll(['No.7.txt', 'Next.20.txt']));
    expect(outTexts().values, containsAll(['甲\n', '乙\n']));
    expect(sourceBytes(h, book.id), before);
    expect(h.app.editor.chapter?.id, chapter.id);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('空正文章节也导出为空文件', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单空正文',
      chapterTitles: ['空章'],
      bodies: [''],
    );
    final chapter = book.allChapters.toList().first;
    await pumpEditor(tester, h, book);

    await openChapterMenu(tester, chapter.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(outFiles(), hasLength(1));
    expect(outTexts().values.single, '\n');
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('没有章节的卷菜单只提示暂无章节可导出', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单空卷',
      chapterTitles: ['有章'],
      bodies: ['正文'],
    );
    final empty = (await tester.runAsync(() async {
      final volume = await h.app.library.appendVolume(book, title: '空卷');
      await h.app.library.setVolumeExpanded(book, volume.id, true);
      return volume;
    }))!;
    await pumpEditor(tester, h, book);

    await tester.tap(find.byKey(ValueKey('volume-menu-${empty.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出本卷'));
    await finishIo(
      tester,
      until: () => find.text('暂无章节可导出').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无章节可导出'), findsOneWidget);
    expect(outNames(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('export-notice-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('导出进行中禁止二次菜单及删除移动入口', (tester) async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final h = await widgetHarness(
      tester,
      exportReadBytes: (file) async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        return file.readAsBytes();
      },
    );
    await useOut(tester, h);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('菜单并发');
      final opening = await h.app.library.openBook(summary);
      final volume = opening.volumes.first;
      await h.app.library.setVolumeExpanded(opening, volume.id, true);
      await h.app.library.renameChapter(opening, volume.chapters.first, '并发章');
      await h.app.chapterStore.writeText(
        opening.id,
        volume.id,
        volume.chapters.first.id,
        '并发正文',
      );
      final fresh = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: fresh,
        inVolume: fresh.volumes.first,
        inChapter: fresh.volumes.first.chapters.first,
      );
      return fresh;
    }))!;
    await pumpEditor(tester, h, book);
    final chapter = book.allChapters.toList().first;

    try {
      await openChapterMenu(tester, chapter.id);
      await tester.tap(find.text('导出本章'));
      await finishIo(tester, until: () => entered.isCompleted);
      expect(outFiles(), isEmpty);
      expect(h.app.exporter.busy, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(ValueKey('chapter-menu-${chapter.id}')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
      await tester.pumpAndSettle();
      expect(find.text('导出本章'), findsNothing);
      expect(find.text('删除章'), findsNothing);
      expect(find.text('移动'), findsNothing);
      expect(book.allChapters.single.id, chapter.id);
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(h.app.exporter.busy, isFalse);
    expect(outTexts().values.single, '并发正文\n');
    expect(outFiles(), hasLength(1));
    expect(find.byKey(const ValueKey('export-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('真实菜单读取失败无残稿，原目标重试成功', (tester) async {
    var fail = true;
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单读取故障',
      chapterTitles: ['读取目标'],
      bodies: ['完整正文'],
      exportReadBytes: (file) {
        if (fail && file.path.endsWith('.txt')) {
          throw const FileSystemException('菜单读取失败');
        }
        return file.readAsBytes();
      },
    );
    await pumpEditor(tester, h, book);
    final before = sourceBytes(h, book.id);
    final chapter = book.allChapters.single;
    await openChapterMenu(tester, chapter.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('export-retry')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('菜单读取失败'), findsOneWidget);
    expect(outFiles(), isEmpty);
    expect(
      out.listSync(recursive: true).where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    expect(sourceBytes(h, book.id), before);
    expect(h.app.exporter.busy, isFalse);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('export-retry')));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    expect(outTexts().values.single, '完整正文\n');
    expect(sourceBytes(h, book.id), before);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('打开导出目录失败仍保留成功文件和完整路径', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '打开目录失败',
      chapterTitles: ['已成功导出的章'],
      bodies: ['不得重复写出的正文'],
    );
    await pumpEditor(tester, h, book);
    final platform = h.app.platform as FakePlatformServices;
    platform.revealResult = false;
    await openChapterMenu(tester, book.allChapters.single.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    final path = outFiles().single.path;
    final bytes = File(path).readAsBytesSync();
    await tester.tap(find.byKey(const ValueKey('export-open-directory')));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('export-open-error')).evaluate().isNotEmpty,
    );
    expect(platform.revealed, isTrue);
    expect(find.byKey(const ValueKey('export-result-path')), findsOneWidget);
    expect(find.text(path), findsOneWidget);
    expect(find.byKey(const ValueKey('export-retry')), findsNothing);
    expect(outFiles(), hasLength(1));
    expect(File(path).readAsBytesSync(), bytes);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('真实菜单重复同名导出不覆盖旧文件', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '同名菜单',
      chapterTitles: ['同名章'],
      bodies: ['不被覆盖的正文'],
    );
    await pumpEditor(tester, h, book);
    final before = sourceBytes(h, book.id);
    for (var count = 1; count <= 2; count++) {
      await openChapterMenu(tester, book.allChapters.single.id);
      await tester.tap(find.text('导出本章'));
      await finishIo(
        tester,
        until: () => find
            .byKey(const ValueKey('export-result-path'))
            .evaluate()
            .isNotEmpty,
      );
      expect(outFiles(), hasLength(count));
      expect(outTexts().values, everyElement('不被覆盖的正文\n'));
      await tester.tap(find.byKey(const ValueKey('export-close')));
      await tester.pumpAndSettle();
    }
    expect(outNames(), containsAll(['同名章.txt', '同名章 (2).txt']));
    expect(sourceBytes(h, book.id), before);
    await finishWidget(tester, h);
  });

  testWidgets('真实菜单等待在途保存，成功后只导出最新稿', (tester) async {
    final writer = _HeldIndexWriter();
    var reads = 0;
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单等保存',
      chapterTitles: ['旧章名'],
      bodies: ['旧正文'],
      writer: writer,
      exportReadBytes: (file) {
        reads++;
        return file.readAsBytes();
      },
    );
    await pumpEditor(tester, h, book);
    writer.release = Completer<void>();
    late Future<void> saving;
    await tester.runAsync(() async {
      h.app.editor.title.text = '在途新章名';
      h.app.editor.text.text = '在途最新正文';
      saving = h.app.editor.saveNow();
    });
    try {
      await finishIo(tester, until: () => writer.entered.isCompleted);
      expect(writer.entered.isCompleted, isTrue);
      await openChapterMenu(tester, book.allChapters.single.id);
      await tester.tap(find.text('导出本章'));
      await finishIo(tester, until: () => h.app.exporter.busy);
      expect(h.app.exporter.busy, isTrue);
      expect(reads, 0);
      expect(outFiles(), isEmpty);
    } finally {
      if (!writer.release!.isCompleted) writer.release!.complete();
    }
    await tester.runAsync(() => saving);
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    expect(reads, greaterThan(0));
    expect(outNames().single, '在途新章名.txt');
    expect(outTexts().values.single, '在途最新正文\n');
    expect(h.app.editor.title.text, '在途新章名');
    expect(h.app.editor.isDirty, isFalse);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  for (final field in ['chapter-title', 'chapter-body']) {
    testWidgets('真实 $field 组词时点击菜单保持输入连接与草稿', (tester) async {
      final (h, book) = await seed(
        tester,
        bookTitle: '真实组词菜单',
        chapterTitles: ['原章名'],
        bodies: ['原正文'],
      );
      await pumpEditor(tester, h, book);
      final chapter = book.allChapters.single;
      final before = sourceBytes(h, book.id);
      final indexBefore = h.app.paths.bookFile(book.id).readAsBytesSync();
      await tester.tap(find.byKey(ValueKey(field)));
      const composing = TextEditingValue(
        text: ' 组词中 ',
        composing: TextRange(start: 1, end: 4),
        selection: TextSelection.collapsed(offset: 4),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      expect(h.app.editor.isComposing, isTrue);
      final controller = field == 'chapter-title'
          ? h.app.editor.title
          : h.app.editor.text;
      expect(controller.value.composing, composing.composing);
      await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
      await finishIo(tester);
      await tester.pumpAndSettle();
      expect(controller.value, composing, reason: '菜单点击不得通过失焦清除 composing');
      expect(find.text('导出本章'), findsNothing);
      expect(sourceBytes(h, book.id), before);
      expect(h.app.paths.bookFile(book.id).readAsBytesSync(), indexBefore);
      expect(outFiles(), isEmpty);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '组词完成',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();
      await finishWidget(tester, h);
    });
  }

  testWidgets('导出完成后再删章不影响已导出的文件', (tester) async {
    final (h, book) = await seed(
      tester,
      bookTitle: '菜单导出后删除',
      chapterTitles: ['将删章', '保留章'],
      bodies: ['删前正文', '保留正文'],
    );
    final victim = book.allChapters.toList().first;
    await pumpEditor(tester, h, book);

    await openChapterMenu(tester, victim.id);
    await tester.tap(find.text('导出本章'));
    await finishIo(
      tester,
      until: () => find
          .byKey(const ValueKey('export-result-path'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();
    final before = outTexts().values.single;
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();

    await openChapterMenu(tester, victim.id);
    await tester.tap(find.text('删除章'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '删除');
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await finishIo(
      tester,
      until: () =>
          book.allChapters.every((chapter) => chapter.id != victim.id) &&
          h.app.editor.chapter?.id != victim.id &&
          editorReady(tester),
    );
    await tester.pumpAndSettle();
    expect(
      book.allChapters.map((chapter) => chapter.id),
      isNot(contains(victim.id)),
    );
    expect(h.app.editor.chapter?.id, isNot(victim.id));
    expect(
      h.app.paths
          .chapterFile(book.id, book.volumes.first.id, victim.id)
          .existsSync(),
      isFalse,
    );
    final persisted = await tester.runAsync(
      () => h.app.bookStore.load(h.app.library.books.single),
    );
    expect(
      persisted!.allChapters.map((chapter) => chapter.id),
      isNot(contains(victim.id)),
    );
    expect(outTexts().values.single, before);
    await finishWidget(tester, h);
  });
}

class _FaultWriter extends AtomicFileWriter {
  bool fail = false;

  @override
  Future<void> writeAtomically(File file, String text) async {
    if (fail && file.path.replaceAll('\\', '/').contains('/exports/')) {
      await File('${file.path}.tmp').writeAsString('只有部分内容');
      throw const FileSystemException('模拟导出写盘失败');
    }
    await super.writeAtomically(file, text);
  }
}

class _HeldIndexWriter extends AtomicFileWriter {
  Completer<void>? release;
  final entered = Completer<void>();

  @override
  Future<void> writeAtomically(File file, String text) async {
    if (release != null && file.uri.pathSegments.last == 'book.json') {
      if (!entered.isCompleted) entered.complete();
      await release!.future;
    }
    await super.writeAtomically(file, text);
  }
}
