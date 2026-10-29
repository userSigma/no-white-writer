import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';
import 'support/fake_platform.dart';

Future<void> drag(WidgetTester t, Finder from, Finder to) async {
  final start = t.getCenter(from), end = t.getCenter(to);
  final gesture = await t.startGesture(start);
  await gesture.moveBy(const Offset(0, 10));
  await t.pump(const Duration(milliseconds: 50));
  for (int i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 8)!);
    await t.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await t.pump();
}

void main() {
  for (final width in [1280.0, 900.0]) {
    testWidgets('真实握柄跨卷及反向拖回：$width 保留字节备份当前章及手动折叠', (tester) async {
      final h = await widgetHarness(tester, width: width, height: 820);
      late Volume source, target;
      late ChapterMeta chapter;
      late List<int> original, backup;
      final book = (await tester.runAsync(() async {
        final s = await h.app.library.createBook('真实拖动');
        final b = await h.app.library.openBook(s);
        source = b.volumes.first;
        chapter = source.chapters.first;
        target = await h.app.library.structure.appendVolume(b, title: '目标卷');
        await h.app.library.setVolumeExpanded(b, source.id, true);
        await h.app.library.structure.setNumbering(
          b,
          source,
          const ChapterNumbering(enabled: true),
        );
        await h.app.library.structure.setNumbering(
          b,
          target,
          const ChapterNumbering(enabled: true, padding: 3),
        );
        original = [239, 187, 191, ...utf8.encode('保留\r\n正文。')];
        backup = utf8.encode('上一个备份\r\n');
        await h.app.paths
            .chapterFile(b.id, source.id, chapter.id)
            .writeAsBytes(original);
        await File(
          '${h.app.paths.chapterFile(b.id, source.id, chapter.id).path}.bak',
        ).writeAsBytes(backup);
        return b;
      }))!;
      await tester.pumpWidget(
        NoWhiteWriterApp(
          app: h.app,
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      if (width < 1000) {
        await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
      await tester.pumpAndSettle();
      expect(find.text('移动'), findsOneWidget);
      expect(find.text('上移章'), findsNothing);
      await tester.tap(find.text('移动'));
      await finishIo(
        tester,
        until: () => find
            .byKey(ValueKey('chapter-grip-${chapter.id}'))
            .evaluate()
            .isNotEmpty,
      );
      final gripIcon = find.descendant(
        of: find.byKey(ValueKey('chapter-grip-${chapter.id}')),
        matching: find.byType(Icon),
      );
      final icon = tester.widget<Icon>(gripIcon);
      expect(
        icon.color ?? IconTheme.of(tester.element(gripIcon)).color,
        Colors.black,
        reason: '握柄自身白底不能画白色图标',
      );
      final initialText = h.app.editor.text.text;
      await drag(
        tester,
        find.byKey(ValueKey('chapter-grip-${chapter.id}')),
        find.byKey(ValueKey('chapter-drop-volume-${target.id}')),
      );
      await finishIo(
        tester,
        until: () =>
            book.volumeOfChapter(chapter.id)?.id == target.id &&
            h.app.editor.volume?.id == target.id &&
            !h.app.editor.structuralBusy &&
            editorReady(tester),
      );
      expect(book.volumeOfChapter(chapter.id)?.id, target.id);
      expect(h.app.editor.volume?.id, target.id);
      expect(h.app.editor.chapter?.id, chapter.id);
      expect(h.app.editor.text.text, initialText);
      expect(
        (h.app.platform as FakePlatformServices).lastTitle,
        contains('第001章 ${chapter.title}'),
      );
      expect(tester.takeException(), isNull);
      expect(h.app.library.expandedVolumesOf(book), {source.id});
      await tester.runAsync(() async {
        expect(
          await h.app.paths
              .chapterFile(book.id, target.id, chapter.id)
              .readAsBytes(),
          original,
        );
        expect(
          await File(
            '${h.app.paths.chapterFile(book.id, target.id, chapter.id).path}.bak',
          ).readAsBytes(),
          backup,
        );
        expect(
          await h.app.paths
              .chapterFile(book.id, source.id, chapter.id)
              .exists(),
          isFalse,
        );
        final fresh = await h.app.bookStore.load(h.app.library.books.single);
        expect(fresh.volumeOfChapter(chapter.id)?.id, target.id);
      });
      await tester.tap(find.byKey(ValueKey('toggle-volume-${target.id}')));
      await tester.pumpAndSettle();
      await drag(
        tester,
        find.byKey(ValueKey('chapter-grip-${chapter.id}')),
        find.byKey(ValueKey('chapter-drop-volume-${source.id}')),
      );
      await finishIo(
        tester,
        until: () =>
            book.volumeOfChapter(chapter.id)?.id == source.id &&
            h.app.editor.volume?.id == source.id &&
            !h.app.editor.structuralBusy &&
            editorReady(tester),
      );
      expect(book.volumeOfChapter(chapter.id)?.id, source.id);
      await tester.tap(find.text('完成移动'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('chapter-grip-${chapter.id}')), findsNothing);
      if (width < 1000) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chapter-pane-barrier')),
          findsNothing,
        );
      }
      await finishWidget(tester, h);
    });
  }
  testWidgets('同卷章间落点、原位、无效落点、取消与卷排序是真实手势', (tester) async {
    final h = await widgetHarness(tester);
    late Volume a, b;
    late ChapterMeta second;
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('排序');
      final book = await h.app.library.openBook(s);
      a = book.volumes.first;
      second = await h.app.library.structure.appendChapter(
        book,
        a,
        title: '第二章',
      );
      b = await h.app.library.structure.appendVolume(book, title: '第二卷');
      await h.app.library.setVolumeExpanded(book, a.id, true);
      return book;
    }))!;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(ValueKey('chapter-menu-${second.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await finishIo(
      tester,
      until: () => find
          .byKey(ValueKey('chapter-grip-${second.id}'))
          .evaluate()
          .isNotEmpty,
    );
    final first = a.chapters.first.id;
    await drag(
      tester,
      find.byKey(ValueKey('chapter-grip-${second.id}')),
      find.byKey(ValueKey('chapter-gap-${a.id}-0')),
    );
    await finishIo(
      tester,
      until: () => a.chapters.first.id == second.id && editorReady(tester),
    );
    expect(a.chapters.map((c) => c.id), [second.id, first]);
    final indexBefore = await tester.runAsync(
      () => h.app.paths.bookFile(book.id).readAsBytes(),
    );
    await drag(
      tester,
      find.byKey(ValueKey('chapter-grip-${second.id}')),
      find.byKey(ValueKey('chapter-gap-${a.id}-0')),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await drag(
      tester,
      find.byKey(ValueKey('chapter-grip-${second.id}')),
      find.byKey(const ValueKey('chapter-body')),
    );
    await tester.pumpAndSettle();
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('chapter-grip-${second.id}'))),
    );
    await g.moveBy(const Offset(10, 20));
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => h.app.paths.bookFile(book.id).readAsBytes()),
      indexBefore,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chapter-body')))
          .readOnly,
      isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('volume-menu-${b.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(ValueKey('volume-grip-${b.id}')).evaluate().isNotEmpty,
    );
    await drag(
      tester,
      find.byKey(ValueKey('volume-grip-${b.id}')),
      find.byKey(const ValueKey('volume-gap-0')),
    );
    await finishIo(
      tester,
      until: () => book.volumes.first.id == b.id && editorReady(tester),
    );
    expect(book.volumes.map((v) => v.id), [b.id, a.id]);
    expect(book.volumes.map((v) => v.order), [0, 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });
  testWidgets('长目录边缘滚动揭示落点；实际拖动锁住正文和重复入口', (tester) async {
    final h = await widgetHarness(tester, height: 720);
    late Volume source, target;
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('长目录');
      final b = await h.app.library.openBook(s);
      source = b.volumes.first;
      for (int i = 0; i < 20; i++) {
        await h.app.library.structure.appendChapter(b, source, title: '长章$i');
      }
      target = await h.app.library.structure.appendVolume(b, title: '底部目标');
      await h.app.library.setVolumeExpanded(b, source.id, true);
      return b;
    }))!;
    final chapter = source.chapters.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await finishIo(
      tester,
      until: () => find
          .byKey(ValueKey('chapter-grip-${chapter.id}'))
          .evaluate()
          .isNotEmpty,
    );
    final list = find.byType(ListView), rect = tester.getRect(list);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('chapter-grip-${chapter.id}'))),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chapter-body')))
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(ValueKey('add-chapter-${source.id}')))
          .onPressed,
      isNull,
    );
    await gesture.moveTo(Offset(rect.center.dx, rect.bottom - 10));
    await tester.pump(const Duration(seconds: 8));
    expect(tester.widget<ListView>(list).controller!.offset, greaterThan(0));
    final drop = find.byKey(ValueKey('chapter-drop-volume-${target.id}'));
    expect(drop.hitTestable(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(drop));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await finishIo(
      tester,
      until: () =>
          h.app.editor.volume?.id == target.id &&
          !h.app.editor.structuralBusy &&
          editorReady(tester),
    );
    expect(book.volumeOfChapter(chapter.id)?.id, target.id);
    expect(h.app.library.expandedVolumesOf(book), {source.id});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });
  testWidgets('Tab可达握柄，用方向键排序和Ctrl方向键跨卷', (tester) async {
    final h = await widgetHarness(tester);
    late Volume a, b;
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('键盘移动');
      final book = await h.app.library.openBook(s);
      a = book.volumes.first;
      await h.app.library.structure.appendChapter(book, a, title: '另一章');
      b = await h.app.library.structure.appendVolume(book, title: '目标卷');
      await h.app.library.setVolumeExpanded(book, a.id, true);
      return book;
    }))!;
    final chapter = a.chapters.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await finishIo(
      tester,
      until: () => find
          .byKey(ValueKey('chapter-grip-${chapter.id}'))
          .evaluate()
          .isNotEmpty,
    );
    Future<void> tabToGrip() async {
      final focus = Focus.of(
        tester.element(find.byKey(ValueKey('chapter-grip-${chapter.id}'))),
      );
      for (
        int i = 0;
        i < 30 &&
            !(FocusManager.instance.primaryFocus?.ancestors.contains(focus) ??
                false);
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(FocusManager.instance.primaryFocus?.ancestors, contains(focus));
    }

    await tabToGrip();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await finishIo(
      tester,
      until: () =>
          a.chapters.last.id == chapter.id &&
          !h.app.editor.structuralBusy &&
          editorReady(tester),
    );
    expect(a.chapters.last.id, chapter.id);
    await tabToGrip();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await finishIo(
      tester,
      until: () =>
          h.app.editor.volume?.id == b.id &&
          !h.app.editor.structuralBusy &&
          editorReady(tester),
    );
    expect(book.volumeOfChapter(chapter.id)?.id, b.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });
}
