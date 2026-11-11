import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';

import 'support/widget_harness.dart';

void main() {
  testWidgets(
    'editor navigation is upper-left, collapse then back; no title label',
    (tester) async {
      final h = await widgetHarness(tester);
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('唯一书名');
        return h.app.library.openBook(summary);
      }))!;
      await tester.pumpWidget(
        FluentApp(
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      final collapse = find.byKey(const ValueKey('toggle-sidebar'));
      final back = find.byKey(const ValueKey('back-to-shelf'));
      expect(tester.getRect(back).top, lessThan(60));
      expect(
        tester.getRect(collapse).right,
        lessThanOrEqualTo(tester.getRect(back).left),
      );
      expect(find.text('唯一书名'), findsOneWidget);
      expect(find.text('章节标题'), findsNothing);
      expect(find.byKey(const ValueKey('editor-save-status')), findsOneWidget);
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(back.hitTestable(), findsOneWidget);
      expect(collapse.hitTestable(), findsOneWidget);
      await finishWidget(tester, h);
    },
  );

  testWidgets('catalog rows are compact and add-chapter shares volume header', (
    tester,
  ) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('目录');
      return h.app.library.openBook(summary);
    }))!;
    await tester.pumpWidget(
      FluentApp(
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final v = book.volumes.first;
    final c = v.chapters.first;
    if (find.byKey(ValueKey('chapter-row-${c.id}')).evaluate().isEmpty) {
      await tester.tap(find.byKey(ValueKey('toggle-volume-${v.id}')));
      await tester.pumpAndSettle();
    }
    final row = find.byKey(ValueKey('chapter-row-${c.id}'));
    expect(tester.getSize(row).height, inInclusiveRange(32, 36));
    final add = find.byKey(ValueKey('add-chapter-${v.id}'));
    final toggle = find.byKey(ValueKey('toggle-volume-${v.id}'));
    expect(
      (tester.getCenter(add).dy - tester.getCenter(toggle).dy).abs(),
      lessThan(2),
    );
    expect(find.byKey(const ValueKey('add-volume')), findsOneWidget);
    final header = find.ancestor(of: toggle, matching: find.byType(Row)).first;
    final volumeTitle = find
        .descendant(of: header, matching: find.byType(Text))
        .first;
    final chapterTexts = find.descendant(
      of: find.byKey(ValueKey('select-chapter-${c.id}')),
      matching: find.byType(Text),
    );
    final chapterTitle = chapterTexts.at(0);
    final count = chapterTexts.at(1);
    double glyphLeft(Finder target) {
      final text = tester.widget<Text>(target).data!;
      final paragraph = tester.renderObject<RenderParagraph>(target);
      final firstGlyph = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .first;
      return paragraph
          .localToGlobal(Offset(firstGlyph.left, firstGlyph.top))
          .dx;
    }

    expect(
      glyphLeft(chapterTitle) - glyphLeft(volumeTitle),
      inInclusiveRange(12, 16),
      reason: '测量真实字形，而不是被按钮居中样式占满的文字容器',
    );
    expect(
      (tester.getCenter(chapterTitle).dy - tester.getCenter(count).dy).abs(),
      lessThan(2),
    );
    expect(
      tester.getRect(chapterTitle).right,
      lessThan(tester.getRect(count).left),
    );
    expect(tester.widget<Text>(chapterTitle).maxLines, 1);
    await finishWidget(tester, h);
  });

  testWidgets('shelf keeps one view and search filters the visible grid', (
    tester,
  ) async {
    final h = await widgetHarness(tester);
    await tester.runAsync(() async {
      await h.app.library.createBook('Alpha');
      await h.app.library.createBook('Beta');
    });
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-grid-view')), findsNothing);
    expect(find.byKey(const ValueKey('shelf-list-view')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('shelf-search')), 'alp');
    await tester.pump();
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    // 排序下拉的 onChanged 会把焦点交回书架，随后回车打开当前选中作品。
    await tester.tap(find.text('最近编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按书名'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await finishIo(tester, until: () => editorReady(tester));
    expect(h.app.editor.book?.title, 'Alpha');
    await finishWidget(tester, h);
  });

  testWidgets(
    'new-book dashed tile exists on empty shelf and opens creation dialog',
    (tester) async {
      final h = await widgetHarness(tester);
      await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
      await tester.tap(find.byKey(const ValueKey('shelf-new-book-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-title-input')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await finishWidget(tester, h);
    },
  );
}
