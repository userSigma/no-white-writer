import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/state/library_controller.dart';
import 'package:no_white_writer/ui/book_details_dialog.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';

import 'support/app_harness.dart';

Future<AppHarness> harness(WidgetTester tester, {double width = 1280}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final AppHarness h = (await tester.runAsync(createHarness))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    bool finished = false;
    Object? failure;
    h.dispose().then<void>(
      (_) {
        finished = true;
      },
      onError: (Object error) {
        failure = error;
        finished = true;
      },
    );
    await finishIo(tester, until: () => finished);
    expect(finished, isTrue, reason: '临时测试资源清理应结束');
    expect(failure, isNull);
  });
  return h;
}

Future<void> finishIo(WidgetTester tester, {bool Function()? until}) async {
  for (int i = 0; i < (until == null ? 60 : 500); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until?.call() ?? false) break;
  }
  await tester.pump(const Duration(milliseconds: 250));
}

bool editorReady(WidgetTester tester) {
  final Finder body = find.byKey(const ValueKey('chapter-body'));
  return body.evaluate().isNotEmpty && !tester.widget<TextField>(body).readOnly;
}

Future<void> flushEdits(WidgetTester tester, AppHarness h) async {
  bool finished = false;
  () async {
    await h.app.editor.flush();
    await h.app.settings.flush();
    finished = true;
  }();
  // IO 的回调在发起它的 fake-async zone 中；等待时必须继续 pump。
  await finishIo(tester, until: () => finished);
  expect(finished, isTrue, reason: '保存与设置写入应结束');
}

Future<void> finishPage(WidgetTester tester, AppHarness h) async {
  await flushEdits(tester, h);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('标题和正文支持 Ctrl+A 全选', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    final BookSummary summary = (await tester.runAsync(
      () => h.app.library.createBook('键盘验收'),
    ))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.tap(find.text(summary.title).first);
    await finishIo(tester, until: () => editorReady(tester));
    for (final String key in <String>['chapter-title', 'chapter-body']) {
      final Finder field = find.byKey(ValueKey(key));
      await tester.enterText(field, 'Keyboard selection');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 18),
        reason: key,
      );
    }
    await finishPage(tester, h);
  });

  testWidgets('书架卡片在各宽度及列数临界处保持 220×300', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    await tester.runAsync(() => h.app.library.createBook('固定卡片'));
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    final Finder cards = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_BookCard',
    );
    for (final double width in <double>[900, 1000, 1015, 1016, 1280, 1600]) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pump(const Duration(milliseconds: 200));
      expect(cards, findsOneWidget);
      expect(tester.getSize(cards), const Size(220, 300), reason: '窗口宽 $width');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('新建表单单行50字、备注固定三行，回车只移焦', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.tap(find.text('新建').first);
    await tester.pumpAndSettle();
    final Finder name = find.byKey(const ValueKey('book-title-input'));
    final Finder notes = find.byKey(const ValueKey('book-notes-input'));
    expect(name, findsOneWidget);
    expect(notes, findsOneWidget);
    final TextBox nameBox = tester.widget<TextBox>(name);
    final TextBox notesBox = tester.widget<TextBox>(notes);
    expect(nameBox.maxLines, 1);
    expect(nameBox.maxLength, 50);
    expect(notesBox.minLines, 3);
    expect(notesBox.maxLines, 3);
    await tester.enterText(name, '👩‍💻' * 51);
    expect(nameBox.controller!.text, '👩‍💻' * 50);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '中' * 51,
        selection: const TextSelection.collapsed(offset: 51),
        composing: const TextRange(start: 50, end: 51),
      ),
    );
    await tester.pump();
    expect(nameBox.controller!.text, '中' * 51);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '中' * 51,
        selection: const TextSelection.collapsed(offset: 51),
      ),
    );
    await tester.pump();
    expect(nameBox.controller!.text, '中' * 50);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(notesBox.focusNode!.hasFocus, isTrue);
    expect(h.app.library.books, isEmpty);
    await tester.enterText(notes, '一\n二\n三\n四\n五');
    expect(tester.widget<TextBox>(notes).maxLines, 3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(h.app.library.books, isEmpty);
  });

  testWidgets('按书名排序新建作品仍打开创建目标并持久化备注', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    await tester.runAsync(() => h.app.library.createBook('A旧作品'));
    h.app.library.setSort(LibrarySort.title);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('book-title-input')),
      'Z新作品',
    );
    await tester.enterText(
      find.byKey(const ValueKey('book-notes-input')),
      '备注一\n备注二',
    );
    await tester.tap(find.text('创建'));
    await finishIo(
      tester,
      until: () => h.app.editor.book?.title == 'Z新作品' && editorReady(tester),
    );
    expect(find.byType(EditorPage), findsOneWidget);
    expect(h.app.editor.book?.title, 'Z新作品');
    expect(h.app.editor.book?.notes, '备注一\n备注二');
    // 新建卷入口已并入书名右侧菜单，不再单独占位。
    expect(find.text('新建卷'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('book-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('新建卷'), findsOneWidget);
    expect(find.text('自动章节序号设置'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finishPage(tester, h);
  });

  testWidgets('直接点书进入工作区，标题栏独立且窄屏仍有全部管理入口', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    final BookSummary summary = (await tester.runAsync(
      () => h.app.library.createBook('直接写作'),
    ))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.tap(find.text(summary.title).first);
    await finishIo(tester, until: () => editorReady(tester));
    expect(find.byType(EditorPage), findsOneWidget);
    final Finder title = find.byKey(const ValueKey('chapter-title'));
    final Finder body = find.byKey(const ValueKey('chapter-body'));
    expect(title, findsOneWidget);
    expect(body, findsOneWidget);
    expect(tester.widget<TextField>(title).maxLines, 1);
    expect(
      tester.getRect(title).bottom,
      lessThanOrEqualTo(tester.getRect(body).top),
    );
    await tester.enterText(title, '工作区标题');
    await tester.enterText(body, '工作区正文');
    expect(h.app.editor.title.text, '工作区标题');
    await flushEdits(tester, h);
    tester.view.physicalSize = const Size(900, 600);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    // 新建卷入口已并入书名右侧菜单，窄屏仍可达。
    expect(find.text('新建卷'), findsNothing);
    expect(find.byKey(const ValueKey('book-menu-button')), findsOneWidget);
    expect(find.text('作品信息'), findsNothing);
    await tester.tap(
      find.byKey(ValueKey('toggle-volume-${h.app.editor.volume!.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('add-chapter-${h.app.editor.volume!.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('chapter-menu-${h.app.editor.chapter!.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await finishPage(tester, h);
  });

  for (final double width in <double>[900, 1280]) {
    testWidgets('${width.toInt()}宽度共用卷章增改排删且删除后不复活', (
      WidgetTester tester,
    ) async {
      final AppHarness h = await harness(tester, width: width);
      final BookSummary summary = (await tester.runAsync(
        () => h.app.library.createBook('管理验收'),
      ))!;
      final BookIndex book = (await tester.runAsync(
        () => h.app.library.openBook(summary),
      ))!;
      final ChapterMeta first = book.allChapters.first;
      await tester.pumpWidget(
        FluentApp(
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      final Finder paneBarrier = find.byKey(
        const ValueKey('chapter-pane-barrier'),
      );

      Future<void> openPane() async {
        if (width < 1000 && paneBarrier.evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
          await tester.pumpAndSettle();
        }
      }

      Future<void> closePane() async {
        if (width < 1000 && paneBarrier.evaluate().isNotEmpty) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
      }

      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        // 当前章删除会显示持续动画的 ProgressRing；不能等待所有动画停止。
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> nameDialog(String name) async {
        await tester.enterText(find.byType(TextBox).last, name);
        await tester.tap(find.text('确定'));
        await tester.pump();
      }

      await openPane();
      await tapVisible(find.byKey(const ValueKey('book-menu-button')));
      await tester.tap(find.text('新建卷'));
      await tester.pump(const Duration(milliseconds: 250));
      await nameDialog('第二卷');
      await finishIo(
        tester,
        until: () => book.volumes.length == 2 && editorReady(tester),
      );
      final Volume second = book.volumes.last;
      final Finder volumeMenu = find.byKey(
        ValueKey('volume-menu-${second.id}'),
      );
      await tapVisible(volumeMenu);
      expect(find.text('上移卷'), findsNothing);
      expect(find.text('下移卷'), findsNothing);
      await tapVisible(find.text('移动'));
      await finishIo(
        tester,
        until: () =>
            find
                .byKey(ValueKey('volume-grip-${second.id}'))
                .evaluate()
                .isNotEmpty &&
            editorReady(tester),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tapVisible(volumeMenu);
      await tapVisible(find.text('在本卷新建章'));
      await finishIo(
        tester,
        until: () =>
            h.app.editor.chapter?.id != first.id &&
            !h.app.editor.structuralBusy &&
            editorReady(tester),
      );
      final ChapterMeta created = h.app.editor.chapter!;
      expect(created.title, '未命名章节');
      expect(h.app.library.expandedVolumesOf(book), isEmpty);
      await tapVisible(find.byKey(ValueKey('toggle-volume-${second.id}')));
      await tester.pumpAndSettle();
      if (width < 1000) await closePane();
      await tester.enterText(
        find.byKey(const ValueKey('chapter-body')),
        '测试正文',
      );
      await flushEdits(tester, h);
      await openPane();
      final Finder chapterMenu = find.byKey(
        ValueKey('chapter-menu-${created.id}'),
      );
      await tapVisible(chapterMenu);
      expect(find.text('上移章'), findsNothing);
      expect(find.text('移动'), findsOneWidget);
      await tapVisible(find.text('重命名章'));
      await nameDialog('改名后的第二章');
      await finishIo(
        tester,
        until: () => created.title == '改名后的第二章' && editorReady(tester),
      );
      await tapVisible(chapterMenu);
      await tapVisible(find.text('删除章'));
      await tapVisible(find.widgetWithText(FilledButton, '删除'));
      await finishIo(
        tester,
        until: () =>
            h.app.editor.chapter?.id == first.id && editorReady(tester),
      );
      expect(
        h.app.chapterStore.fileOf(book.id, second.id, created.id).existsSync(),
        isFalse,
      );
      await tapVisible(volumeMenu);
      await tapVisible(find.text('删除卷'));
      await tapVisible(find.widgetWithText(FilledButton, '删除'));
      await finishIo(
        tester,
        until: () => book.volumes.length == 1 && editorReady(tester),
      );
      await tapVisible(
        find.byKey(ValueKey('volume-menu-${book.volumes.first.id}')),
      );
      await tapVisible(find.text('删除卷'));
      await tapVisible(find.widgetWithText(FilledButton, '删除'));
      await finishIo(
        tester,
        until: () =>
            book.volumes.isEmpty && find.text('还没有章节').evaluate().isNotEmpty,
      );
      if (width < 1000) await closePane();
      expect(find.text('还没有章节'), findsOneWidget);
      expect(find.byKey(const ValueKey('chapter-body')), findsNothing);
      await flushEdits(tester, h);
      expect(book.volumes, isEmpty);
      expect(tester.takeException(), isNull);
      await finishPage(tester, h);
    });
  }

  testWidgets('旧长书名仅改备注不裁切，表单失败留草稿且提交去重', (WidgetTester tester) async {
    final String oldTitle = '旧' * 60;
    int calls = 0;
    final Completer<bool> submitted = Completer<bool>();
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (BuildContext context) => Button(
            child: const Text('打开表单'),
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => BookDetailsDialog<bool>(
                initialTitle: oldTitle,
                initialNotes: '旧备注',
                onSave: (String title, String notes) async {
                  calls++;
                  expect(title, oldTitle);
                  expect(notes, '新备注');
                  if (calls == 1) throw StateError('模拟失败');
                  return submitted.future;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开表单'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('book-notes-input')),
      '新备注',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('未保存'), findsOneWidget);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('book-title-input')))
          .controller!
          .text,
      oldTitle,
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(calls, 2);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存中…'))
          .onPressed,
      isNull,
    );
    submitted.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailsDialog<bool>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卷展开状态跨返回书架记忆，侧栏显示作品统计', (WidgetTester tester) async {
    final AppHarness h = await harness(tester);
    final BookSummary summary = (await tester.runAsync(
      () => h.app.library.createBook('记忆卷'),
    ))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.tap(find.text(summary.title).first);
    await finishIo(tester, until: () => editorReady(tester));
    final String volumeId = h.app.editor.volume!.id;
    await tester.tap(find.byKey(ValueKey('toggle-volume-$volumeId')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('chapter-row-${h.app.editor.chapter!.id}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('toggle-volume-$volumeId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('back-to-shelf')));
    await finishIo(
      tester,
      until: () => find.byType(EditorPage).evaluate().isEmpty,
    );
    expect(find.byType(EditorPage), findsNothing);
    await tester.tap(find.text(summary.title).first);
    await finishIo(tester, until: () => editorReady(tester));
    expect(h.app.library.expandedVolumesOf(h.app.editor.book!), isEmpty);
    expect(
      find.byKey(ValueKey('chapter-row-${h.app.editor.chapter!.id}')),
      findsNothing,
    );
    expect(find.text('1 卷 · 1 章 · 0 字'), findsOneWidget);
    await finishPage(tester, h);
  });
}
