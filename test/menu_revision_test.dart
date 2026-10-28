import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/state/library_controller.dart';
import 'package:no_white_writer/ui/context_menu.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

void expectBorderless(Button button) {
  for (final states in <Set<WidgetState>>[
    {},
    {WidgetState.hovered},
    {WidgetState.focused},
    {WidgetState.disabled},
    {WidgetState.pressed},
  ]) {
    final shape = button.style?.shape?.resolve(states);
    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).side, BorderSide.none);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [1280.0, 900.0]) {
      testWidgets('真实书架右键菜单无容器与项目描边 $brightness $width', (tester) async {
        final h = await widgetHarness(tester, width: width);
        await tester.runAsync(() => h.app.library.createBook('右键无框'));
        await tester.pumpWidget(
          FluentApp(
            theme: buildFluentTheme(AppThemeData.builtinFor(brightness)),
            home: ShelfPage(app: h.app),
          ),
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('右键无框').first),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('context-menu'));
        expect(menu, findsOneWidget);
        final box = tester.widget<Container>(menu).decoration! as BoxDecoration;
        expect(box.border, isNull);
        final buttons = tester.widgetList<Button>(
          find.descendant(of: menu, matching: find.byType(Button)),
        );
        for (final button in buttons) {
          expectBorderless(button);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(menu, findsNothing);
        // Existing keyboard entry must still work after pointer dismissal.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(menu, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await finishWidget(tester, h);
      });

      testWidgets('真实卷章行去常态卡框且保留当前章与焦点 $brightness $width', (tester) async {
        final h = await widgetHarness(tester, width: width);
        final book = (await tester.runAsync(() async {
          final summary = await h.app.library.createBook('平面目录');
          final book = await h.app.library.openBook(summary);
          await h.app.library.setVolumeExpanded(
            book,
            book.volumes.first.id,
            true,
          );
          return book;
        }))!;
        await tester.pumpWidget(
          FluentApp(
            theme: buildFluentTheme(AppThemeData.builtinFor(brightness)),
            home: EditorPage(app: h.app, book: book),
          ),
        );
        await finishIo(tester, until: () => editorReady(tester));
        if (width < 1000) {
          await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
          await tester.pumpAndSettle();
        }
        final volume = book.volumes.first, chapter = volume.chapters.first;
        final card = tester.widget<Container>(
          find.byKey(ValueKey('volume-${volume.id}')),
        );
        expect((card.decoration as BoxDecoration?)?.border, isNull);
        final select = tester.widget<Button>(
          find.byKey(ValueKey('select-chapter-${chapter.id}')),
        );
        expectBorderless(select);
        final row = tester.widget<Container>(
          find.byKey(ValueKey('chapter-row-${chapter.id}')),
        );
        expect(row.color, isNotNull);
        await tester.tap(find.byKey(ValueKey('chapter-menu-${chapter.id}')));
        await tester.pumpAndSettle();
        expect(find.text('重命名章'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await finishWidget(tester, h);
      });
    }
  }

  for (final position in [
    Offset.zero,
    const Offset(599, 0),
    const Offset(0, 419),
    const Offset(599, 419),
  ]) {
    testWidgets('菜单四角 $position 跳禁用、Tab限域、末项滚动和焦点恢复', (tester) async {
      final h = await widgetHarness(tester, width: 600, height: 420);
      String? chosen;
      var background = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) => Column(
              children: [
                Button(
                  focusNode: focus,
                  onPressed: () async {
                    chosen = await showContextMenu(context, position, [
                      const MenuAction('disabled', '禁用', enabled: false),
                      for (int i = 1; i <= 20; i++) MenuAction('$i', '项目 $i'),
                    ]);
                  },
                  child: const Text('测试菜单'),
                ),
                Button(onPressed: () => background++, child: const Text('背景')),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('测试菜单'));
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('context-menu'));
      final rect = tester.getRect(menu);
      expect(rect.left, greaterThanOrEqualTo(8));
      expect(rect.right, lessThanOrEqualTo(592));
      expect(rect.bottom, lessThanOrEqualTo(412));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      for (int i = 0; i < 18; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();
      expect(find.text('项目 20').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, '20');
      expect(background, 0);
      expect(focus.hasFocus, isTrue);
      await finishWidget(tester, h);
    });
  }

  testWidgets('菜单方向键跳过中间禁用项，全禁用安全取消且背景不接收首次点击', (tester) async {
    final h = await widgetHarness(tester);
    String? choice;
    var allDisabled = false;
    var background = 0;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              Button(
                onPressed: () async {
                  choice = await showContextMenu(
                    context,
                    const Offset(100, 100),
                    [
                      MenuAction('a', '首项', enabled: !allDisabled),
                      const MenuAction('b', '不可用', enabled: false),
                      MenuAction('c', '末项', enabled: !allDisabled),
                    ],
                  );
                },
                child: const Text('测试开关'),
              ),
              Button(onPressed: () => background++, child: const Text('背景动作')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('测试开关'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(choice, 'c');
    allDisabled = true;
    await tester.tap(find.text('测试开关'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-menu')), findsOneWidget);
    // Deliberately hit the barrier at an underlying control's coordinates.
    await tester.tapAt(tester.getCenter(find.text('背景动作')));
    await tester.pumpAndSettle();
    expect(background, 0);
    expect(find.byKey(const ValueKey('context-menu')), findsNothing);
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  testWidgets('菜单打开后改变书架排序仍编辑原书 ID', (tester) async {
    final h = await widgetHarness(tester);
    final target = (await tester.runAsync(() async {
      final target = await h.app.library.createBook('Z-原菜单');
      await h.app.library.createBook('A-其他书');
      return target;
    }))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('book-menu-${target.id}')));
    await tester.pumpAndSettle();
    h.app.library.setSort(LibrarySort.title);
    await tester.pump();
    await tester.tap(find.text('编辑信息'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('book-title-input')).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('book-title-input')))
          .controller!
          .text,
      'Z-原菜单',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('空菜单不创建无法操作的路由', (tester) async {
    final h = await widgetHarness(tester);
    var finished = false;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) => Button(
            onPressed: () async {
              await showContextMenu(context, Offset.zero, []);
              finished = true;
            },
            child: const Text('空菜单'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('空菜单'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.byKey(const ValueKey('context-menu')), findsNothing);
    await finishWidget(tester, h);
  });
}
