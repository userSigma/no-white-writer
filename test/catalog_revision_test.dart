import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/page_harness.dart';
import 'support/widget_harness.dart';

void main() {
  testWidgets('+ 直接创建一次，默认标题选中，折叠偏好不被新建改变', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('目录');
      return h.app.library.openBook(s);
    }))!;
    final volume = book.volumes.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: editorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    expect(
      find.byKey(ValueKey('chapter-row-${volume.chapters.first.id}')),
      findsNothing,
    );
    await tester.tap(find.byKey(ValueKey('toggle-volume-${volume.id}')));
    await tester.pumpAndSettle();
    final plus = find.byKey(ValueKey('add-chapter-${volume.id}'));
    expect(plus, findsOneWidget);
    await tester.tap(plus);
    await tester.tap(plus);
    await finishIo(
      tester,
      until: () => book.allChapters.length == 2 && editorReady(tester),
    );
    expect(book.allChapters.length, 2);
    expect(h.app.editor.title.text, '未命名章节');
    expect(
      h.app.editor.title.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(find.byKey(const ValueKey('name-input')), findsNothing);
    expect(h.app.library.expandedVolumesOf(book), {volume.id});
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  testWidgets('卷名内联改名，IME 回车不提前提交，Esc 取消', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('改名');
      return h.app.library.openBook(s);
    }))!;
    final v = book.volumes.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: editorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('volume-name-${v.id}'));
    expect(input, findsOneWidget);
    await tester.enterText(input, '新卷名');
    final controller = tester.widget<TextBox>(input).controller!;
    controller.value = const TextEditingValue(
      text: '新卷名中',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 3, end: 4),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(v.title, isNot('新卷名中'));
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(
      tester,
      until: () => input.evaluate().isEmpty && editorReady(tester),
    );
    expect(v.title, '新卷名中');
    expect(h.app.library.expandedVolumesOf(book), isEmpty);
    await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(input, '不要保存');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(v.title, '新卷名中');
    await finishWidget(tester, h);
  });

  testWidgets('宽屏折叠跨宽窄返回保持，窄面板选章不自动关闭', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('折叠');
      return h.app.library.openBook(s);
    }))!;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: editorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final collapse = find.byKey(const ValueKey('toggle-sidebar'));
    expect(collapse, findsOneWidget);
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(find.text('新建卷'), findsNothing);
    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    final v = book.volumes.first;
    await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('select-chapter-${v.chapters.first.id}')),
    );
    await finishIo(tester, until: () => editorReady(tester));
    expect(find.byKey(const ValueKey('chapter-pane-barrier')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chapter-pane-barrier')), findsNothing);
    tester.view.physicalSize = const Size(1280, 820);
    await tester.pumpAndSettle();
    expect(find.text('新建卷'), findsNothing);
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('chapter-row-${v.chapters.first.id}')),
      findsOneWidget,
    );
    await finishWidget(tester, h);
  });

  testWidgets('章节编号菜单校验、预览和卷内独立只读标题编号', (tester) async {
    final h = await widgetHarness(tester);
    final BookIndex book = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('编号');
      return h.app.library.openBook(s);
    }))!;
    final v = book.volumes.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: editorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(ValueKey('volume-menu-${v.id}')));
    await tester.pumpAndSettle();
    // 卷菜单不再单独提供「卷设置」，编号入口收敛为「章节编号」子菜单。
    expect(find.text('卷设置'), findsNothing);
    expect(find.text('章节编号'), findsOneWidget);
    await tester.tap(find.text('章节编号'));
    await tester.pumpAndSettle();
    expect(find.text('跟随全局编号'), findsOneWidget);
    expect(find.text('卷内独立编号'), findsOneWidget);
    expect(find.text('不编号'), findsOneWidget);
    // 选择「卷内独立编号」先落模式，再直接打开规则浮窗。
    await tester.tap(find.text('卷内独立编号'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('numbering-dialog')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('numbering-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('numbering-padding')),
      '3',
    );
    await tester.pump();
    expect(find.textContaining('第001章'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('numbering-step')), '0');
    await tester.pump();
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('numbering-save')),
    );
    expect(save.onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('numbering-step')), '1');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('numbering-save')));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('chapter-number')).evaluate().isNotEmpty &&
          editorReady(tester),
    );
    expect(v.numbering.padding, 3);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chapter-title')))
          .controller!
          .text,
      v.chapters.first.title,
    );
    expect(find.byKey(const ValueKey('chapter-number')), findsOneWidget);
    expect(find.text('第001章'), findsOneWidget);
    await finishWidget(tester, h);
  });
}
