import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/book_details_dialog.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

class _FaultWriter extends AtomicFileWriter {
  bool fail = false;
  @override
  Future<void> writeAtomically(File f, String s) async {
    if (fail && f.path.endsWith('book.json')) {
      throw const FileSystemException('forms fault');
    }
    await super.writeAtomically(f, s);
  }
}

void main() {
  testWidgets('作品信息不以清除组词伪装提交，候选上屏后可保存', (tester) async {
    final h = await widgetHarness(tester);
    int saved = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: BookDetailsDialog<bool>(
          onSave: (name, notes) async {
            saved++;
            return true;
          },
        ),
      ),
    );
    final name = find.byKey(const ValueKey('book-title-input'));
    await tester.tap(name);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '作者候选',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 4),
      ),
    );
    await tester.pump();
    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(saved, 0);
    expect(
      tester.widget<TextBox>(name).controller!.value.composing,
      const TextRange(start: 2, end: 4),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '作者候选',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await finishWidget(tester, h);
  });
  testWidgets('内联失焦提交、允许空白和写盘失败草稿可重试', (tester) async {
    final writer = _FaultWriter(),
        h = await widgetHarness(tester, writer: writer);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('内联边界');
      return h.app.library.openBook(s);
    }))!;
    final v = book.volumes.first,
        input = find.byKey(ValueKey('volume-name-${book.volumes.first.id}'));
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    Future<void> rename() async {
      await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
    }

    await rename();
    await tester.enterText(input, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(
      tester,
      until: () => input.evaluate().isEmpty && editorReady(tester),
    );
    expect(v.title, '');
    expect(find.text('卷名为空，已保留原名'), findsNothing);
    await rename();
    await tester.enterText(input, '失焦保存');
    await tester.tap(find.byKey(const ValueKey('chapter-body')));
    await finishIo(
      tester,
      until: () => input.evaluate().isEmpty && editorReady(tester),
    );
    expect(v.title, '失焦保存');
    await rename();
    await tester.enterText(input, '失败稿还在');
    writer.fail = true;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(
      tester,
      until: () =>
          find.textContaining('forms fault').evaluate().isNotEmpty &&
          editorReady(tester),
    );
    expect(v.title, '失焦保存');
    expect(tester.widget<TextBox>(input).controller!.text, '失败稿还在');
    writer.fail = false;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(
      tester,
      until: () => input.evaluate().isEmpty && editorReady(tester),
    );
    expect(v.title, '失败稿还在');
    await finishWidget(tester, h);
  });
  testWidgets('真实空标题占位呈灰色而不写回模型', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('占位');
      final b = await h.app.library.openBook(summary);
      await h.app.library.renameVolume(b, b.volumes.first, '');
      await h.app.library.renameChapter(b, b.allChapters.first, '');
      return b;
    }))!;
    final v = book.volumes.first;
    final c = v.chapters.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final chapterRow = find.byKey(ValueKey('chapter-row-${c.id}'));
    if (chapterRow.evaluate().isEmpty) {
      await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
      await tester.pumpAndSettle();
    }
    final volumeText = find.descendant(
      of: find.byKey(ValueKey('volume-${v.id}')),
      matching: find.text('未命名卷'),
    );
    final chapterText = find.descendant(
      of: chapterRow,
      matching: find.text('未命名章节'),
    );
    expect(volumeText, findsOneWidget);
    expect(chapterText, findsOneWidget);
    expect(
      tester.widget<Text>(volumeText).style!.color,
      mutedTextColor(tester.element(volumeText)),
    );
    expect(
      tester.widget<Text>(chapterText).style!.color,
      mutedTextColor(tester.element(chapterText)),
    );
    expect(v.title, '');
    expect(c.title, '');
    await finishWidget(tester, h);
  });

  for (final current in [true, false]) {
    testWidgets('章菜单可清空${current ? '当前' : '非当前'}章名', (tester) async {
      final h = await widgetHarness(tester);
      final book = (await tester.runAsync(() async {
        final s = await h.app.library.createBook('章菜单空名');
        final b = await h.app.library.openBook(s);
        await h.app.library.appendChapter(b, b.volumes.first);
        return b;
      }))!;
      final v = book.volumes.first;
      final c = current ? v.chapters.first : v.chapters.last;
      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(AppThemeData.light),
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      final menu = find.byKey(ValueKey('chapter-menu-${c.id}'));
      if (menu.evaluate().isEmpty) {
        await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
        await tester.pumpAndSettle();
      }
      final selected = h.app.editor.chapter!.id;
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名章'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('name-input')), '  ');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await finishIo(tester);
      expect(c.title, '');
      expect(h.app.editor.chapter!.id, selected);
      expect(find.byKey(const ValueKey('name-input')), findsNothing);
      await finishWidget(tester, h);
    });
  }

  for (final current in [true, false]) {
    testWidgets('${current ? '当前' : '非当前'}空章名保存失败保留对话框草稿并可重试', (tester) async {
      final writer = _FaultWriter();
      final h = await widgetHarness(tester, writer: writer);
      final book = (await tester.runAsync(() async {
        final s = await h.app.library.createBook('章名失败草稿');
        final b = await h.app.library.openBook(s);
        await h.app.library.appendChapter(b, b.volumes.first);
        return b;
      }))!;
      final v = book.volumes.first;
      final c = current ? v.chapters.first : v.chapters.last;
      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(AppThemeData.light),
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      final menu = find.byKey(ValueKey('chapter-menu-${c.id}'));
      if (menu.evaluate().isEmpty) {
        await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
        await tester.pumpAndSettle();
      }
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名章'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('name-input'));
      await tester.enterText(input, '');
      writer.fail = true;
      try {
        await tester.tap(find.widgetWithText(FilledButton, '确定'));
        await finishIo(tester);
        expect(input, findsOneWidget);
        expect(tester.widget<TextBox>(input).controller!.text, '');
        expect(find.textContaining('forms fault'), findsWidgets);
        expect(c.title, '未命名章节');
      } finally {
        writer.fail = false;
      }
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await finishIo(
        tester,
        until: () => input.evaluate().isEmpty && editorReady(tester),
      );
      expect(c.title, '');
      await finishWidget(tester, h);
    });
  }

  testWidgets('章名对话框保护IME，取消空草稿不写盘，回车可提交空值', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('章名组合态');
      return h.app.library.openBook(s);
    }))!;
    final v = book.volumes.first, c = v.chapters.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final menu = find.byKey(ValueKey('chapter-menu-${c.id}'));
    if (menu.evaluate().isEmpty) {
      await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
      await tester.pumpAndSettle();
    }
    Future<void> openName() async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名章'));
      await tester.pumpAndSettle();
    }

    final file = h.app.paths.bookFile(book.id);
    final before = (await tester.runAsync(file.readAsBytes))!;
    final input = find.byKey(const ValueKey('name-input'));
    await openName();
    await tester.tap(input);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '候选',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确定'))
          .onPressed,
      isNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(input, findsOneWidget, reason: '提交动作不得结束未完成的组词草稿');
    expect(
      tester.widget<TextBox>(input).controller!.value.composing,
      const TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(input, findsOneWidget);
    expect(
      tester.widget<TextBox>(input).controller!.value.composing,
      const TextRange(start: 0, end: 2),
    );
    expect((await tester.runAsync(file.readAsBytes))!, before);
    await tester.enterText(input, '');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(input, findsNothing, reason: '已结束组词后的 Escape 应真正取消对话框');
    expect(c.title, '未命名章节');
    expect((await tester.runAsync(file.readAsBytes))!, before);
    await openName();
    await tester.enterText(input, ' ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(
      tester,
      until: () => input.evaluate().isEmpty && editorReady(tester),
    );
    expect(c.title, '');
    await finishWidget(tester, h);
  });

  for (final width in [1280.0, 900.0]) {
    testWidgets('$width 隐藏目录前保护内联IME并提交已完成卷名', (tester) async {
      final h = await widgetHarness(tester, width: width);
      final book = (await tester.runAsync(() async {
        final s = await h.app.library.createBook('目录草稿');
        return h.app.library.openBook(s);
      }))!;
      final v = book.volumes.first,
          input = find.byKey(ValueKey('volume-name-${book.volumes.first.id}'));
      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(AppThemeData.light),
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      if (width < 1000) {
        await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '还在候选',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 2, end: 4),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(input, findsOneWidget, reason: '输入法提交动作不能清除未结束的组合态');
      expect(
        tester.widget<TextBox>(input).controller!.value.composing,
        const TextRange(start: 2, end: 4),
      );
      expect(v.title, '未命名卷');
      Future<void> closePane() async {
        if (width >= 1000) {
          await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
        } else {
          // 窄窗浮层居中 440 宽，点左侧遮罩关闭。
          await tester.tapAt(const Offset(20, 300));
        }
        await tester.pumpAndSettle();
      }

      await closePane();
      expect(input, findsOneWidget, reason: '组合输入未结束，目录不能销毁草稿');
      expect(
        tester.widget<TextBox>(input).controller!.value.composing,
        const TextRange(start: 2, end: 4),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '完成后的卷名',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();
      await closePane();
      await finishIo(
        tester,
        until: () => input.evaluate().isEmpty && v.title == '完成后的卷名',
      );
      expect(v.title, '完成后的卷名');
      expect(input, findsNothing);
      await finishWidget(tester, h);
    });
  }
  testWidgets('章节编号规则阻止非法整数和IME半成品，取消只保留模式，失败可重试', (tester) async {
    final writer = _FaultWriter(),
        h = await widgetHarness(tester, writer: writer);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('设置边界');
      return h.app.library.openBook(s);
    }))!;
    final v = book.volumes.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    Future<void> settings() async {
      await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节编号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('卷内独立编号'));
      await finishIo(
        tester,
        until: () => find
            .byKey(const ValueKey('numbering-dialog'))
            .evaluate()
            .isNotEmpty,
      );
    }

    final save = find.byKey(const ValueKey('numbering-save')),
        step = find.byKey(const ValueKey('numbering-step')),
        prefix = find.byKey(const ValueKey('numbering-prefix'));
    await settings();
    // 卷内独立编号在进入规则浮窗前已落盘（legacy enabled 镜像开启）。
    expect(v.numberingMode, VolumeNumberingMode.independent);
    await tester.enterText(step, '0');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(step, '1.5');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(step, '1');
    await tester.tap(prefix);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '章',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(save).onPressed,
      isNull,
      reason: 'IME组词不能当作已提交前缀',
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '章',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // 取消规则编辑只丢弃草稿，卷菜单已选定的独立编号模式保留。
    expect(v.numberingMode, VolumeNumberingMode.independent);
    expect(v.numbering.prefix, '第');
    expect(v.numbering.step, 1);
    await settings();
    await tester.enterText(prefix, 'No.');
    await tester.pump();
    writer.fail = true;
    await tester.tap(save);
    await finishIo(
      tester,
      until: () =>
          find.textContaining('forms fault').evaluate().isNotEmpty &&
          find.byKey(const ValueKey('numbering-dialog')).evaluate().isNotEmpty,
    );
    expect(v.numbering.prefix, '第');
    writer.fail = false;
    await tester.tap(save);
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('numbering-dialog')).evaluate().isEmpty &&
          editorReady(tester),
    );
    expect(v.numbering.prefix, 'No.');
    await finishWidget(tester, h);
  });
}
