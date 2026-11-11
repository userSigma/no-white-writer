import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/ui/theme/app_font.dart';

import 'support/widget_harness.dart';

/// 取一段文本实际排版用的样式（DefaultTextStyle 合并之后的结果）。
TextStyle renderedStyle(WidgetTester tester, Finder finder) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    finder,
  );
  return paragraph.text.style!;
}

/// 取输入框里 [EditableText] 的最终样式。
TextStyle editableStyle(WidgetTester tester, String key) {
  final Finder finder = find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(finder).style;
}

void main() {
  testWidgets('界面文本调用系统默认字体，含回退族', (tester) async {
    final h = await widgetHarness(tester, width: 1280);
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();

    final TextStyle title = renderedStyle(tester, find.text('全部作品'));
    expect(title.fontFamily, kSystemUiFontFamily);
    expect(title.fontFamilyFallback, kSystemUiFontFallback);

    final TextStyle stats = renderedStyle(
      tester,
      find.textContaining('共 0 部作品'),
    );
    expect(stats.fontFamily, kSystemUiFontFamily);
    expect(stats.fontFamilyFallback, kSystemUiFontFallback);

    // fluent 控件自带 body 样式：只声明字号，字体族仍应来自界面默认。
    final TextStyle action = renderedStyle(tester, find.text('新建'));
    expect(action.fontFamily, kSystemUiFontFamily);
    expect(action.fontFamilyFallback, kSystemUiFontFallback);
    await finishWidget(tester, h);
  });

  testWidgets('编辑区正文保留内置文楷，不被界面默认字体覆盖', (tester) async {
    final h = await widgetHarness(tester, width: 1280);
    await tester.runAsync(() => h.app.library.createBook('字体样章'));
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    // 排序下拉把焦点交回书架，回车打开选中作品。
    await tester.tap(find.text('最近编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按书名'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await finishIo(tester, until: () => editorReady(tester));

    expect(editableStyle(tester, 'chapter-body').fontFamily, 'LXGWWenKaiGB');
    expect(
      editableStyle(tester, 'chapter-title').fontFamily,
      isNot('LXGWWenKaiGB'),
    );
    await finishWidget(tester, h);
  });

  test('显式声明字体族的样式不被界面默认覆盖', () {
    // Text 的合并顺序是「界面默认.merge(自身样式)」，自身样式优先。
    const TextStyle editorBody = TextStyle(fontFamily: 'LXGWWenKaiGB');
    expect(kSystemUiTextStyle.merge(editorBody).fontFamily, 'LXGWWenKaiGB');
    expect(kSystemUiFontFamily, isNot('LXGWWenKaiGB'));
    expect(kSystemUiFontFallback, isNot(contains('LXGWWenKaiGB')));
  });
}
