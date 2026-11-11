import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';

import 'support/widget_harness.dart';

void main() {
  testWidgets('根编辑器返回书架保留启动恢复数量，不依赖 AppContext 或恢复记录', (tester) async {
    final h = await widgetHarness(tester);
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('恢复提示'),
    ))!;
    final book = (await tester.runAsync(
      () => h.app.library.openBook(summary),
    ))!;
    await tester.pumpWidget(
      FluentApp(
        home: EditorPage(
          library: h.app.library,
          editor: h.app.editor,
          exporter: h.app.exporter,
          settings: h.app.settings,
          i18n: h.app.i18n,
          platform: h.app.platform,
          paths: h.app.paths,
          uiGuards: h.app.uiGuards,
          recoveredChapterCount: 2,
          book: book,
        ),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    await tester.tap(find.byKey(const ValueKey('back-to-shelf')));
    await finishIo(
      tester,
      until: () => find.byType(ShelfPage).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<ShelfPage>(find.byType(ShelfPage)).recoveredChapterCount,
      2,
    );
    await tester.pump();
    expect(find.text('已恢复 2 个章节。'), findsOneWidget);
    // InfoBar 的 3 秒自动关闭计时也属于本次路由恢复提示，先排空再卸载。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
