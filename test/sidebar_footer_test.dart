import 'package:fluent_ui/fluent_ui.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/app_harness.dart';
import 'support/widget_harness.dart';

Future<AppHarness> _workspace(WidgetTester tester, double width) async {
  final h = await widgetHarness(tester, width: width);
  final book = (await tester.runAsync(() async {
    final summary = await h.app.library.createBook('侧栏底部验收');
    final book = await h.app.library.openBook(summary);
    await h.app.editor.open(
      inBook: book,
      inVolume: book.volumes.first,
      inChapter: book.allChapters.single,
    );
    return book;
  }))!;
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentTheme(AppThemeData.light),
      home: EditorPage(app: h.app, book: book),
    ),
  );
  await finishIo(tester, until: () => editorReady(tester));
  return h;
}

void main() {
  for (final width in [1280.0, 1100.0, 900.0]) {
    testWidgets('$width 返回和设置只属于展开目录底部，收起后一起隐藏', (tester) async {
      final h = await _workspace(tester, width);
      if (width < 1000) {
        await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
        await tester.pumpAndSettle();
      }
      final pane = tester.getRect(
        find.byKey(const ValueKey('chapter-pane-frame')),
      );
      final back = tester.getRect(find.byKey(const ValueKey('back-to-shelf')));
      final settings = tester.getRect(
        find.byKey(const ValueKey('settings-button')),
      );
      expect(back.left, greaterThanOrEqualTo(pane.left));
      expect(back.right, lessThanOrEqualTo(pane.right));
      expect(back.bottom, lessThanOrEqualTo(pane.bottom));
      expect(back.top, greaterThanOrEqualTo(pane.bottom - 52));
      expect(settings.right, lessThanOrEqualTo(pane.right));
      expect(settings.left, greaterThanOrEqualTo(pane.left));
      expect(settings.bottom, lessThanOrEqualTo(pane.bottom));
      expect(settings.top, greaterThanOrEqualTo(pane.bottom - 52));
      expect(back.center.dx, lessThan(pane.center.dx));
      expect(settings.center.dx, greaterThan(pane.center.dx));
      if (width < 1000) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('back-to-shelf')), findsNothing);
      expect(find.byKey(const ValueKey('settings-button')), findsNothing);
      expect(find.byKey(const ValueKey('chapter-body')), findsOneWidget);
      await finishWidget(tester, h);
    });
  }

  testWidgets('窄窗加号新建后 Escape 关闭目录并聚焦新章标题', (tester) async {
    final h = await _workspace(tester, 900);
    final volume = h.app.editor.book!.volumes.first;
    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('toggle-volume-${volume.id}')));
    await finishIo(tester);
    await tester.tap(find.byKey(ValueKey('add-chapter-${volume.id}')));
    await finishIo(
      tester,
      until: () =>
          volume.chapters.length == 2 &&
          h.app.editor.chapter?.id == volume.chapters.last.id &&
          editorReady(tester),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chapter-pane-frame')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chapter-pane-frame')), findsNothing);
    expect(find.byKey(const ValueKey('settings-button')), findsNothing);
    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('chapter-title')),
    );
    expect(title.focusNode!.hasFocus, isTrue);
    expect(h.app.editor.chapter!.id, volume.chapters.last.id);
    await finishWidget(tester, h);
  });

  testWidgets('窄目录展开时平台返回先关闭目录而不离开作品', (tester) async {
    final h = await _workspace(tester, 900);
    final chapterId = h.app.editor.chapter!.id;
    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await finishIo(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-pane-frame')), findsNothing);
    expect(h.app.editor.chapter!.id, chapterId);
    await finishWidget(tester, h);
  });

  for (final control in [
    'toggle-sidebar',
    'back-to-shelf',
    'settings-button',
  ]) {
    testWidgets('真实标题组词点击 $control 不转移焦点或提交草稿', (tester) async {
      final h = await _workspace(tester, 1280);
      final index = h.app.paths.bookFile(h.app.editor.book!.id);
      final before = index.readAsBytesSync();
      await tester.tap(find.byKey(const ValueKey('chapter-title')));
      const composing = TextEditingValue(
        text: ' 侧栏组词 ',
        composing: TextRange(start: 1, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(control)));
      await finishIo(tester);
      await tester.pumpAndSettle();
      expect(h.app.editor.title.value, composing);
      expect(index.readAsBytesSync(), before);
      expect(find.byKey(const ValueKey('chapter-pane-frame')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '侧栏上屏',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();
      await finishWidget(tester, h);
    });
  }
}
