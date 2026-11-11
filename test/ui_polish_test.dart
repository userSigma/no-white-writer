import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

double menuOpacity(WidgetTester tester, Finder button) {
  final opacity = find.ancestor(
    of: button,
    matching: find.byType(AnimatedOpacity),
  );
  expect(opacity, findsOneWidget, reason: '操作通过稳定挂载的渐显容器呈现');
  return tester.widget<AnimatedOpacity>(opacity).opacity;
}

void main() {
  test('内置棕红强调色不改变纯白纯黑与自定义主题', () {
    expect(AppColors.cinnabar, const Color(0xFF8C3A2B));
    expect(AppThemeData.light.background, Colors.white);
    expect(AppThemeData.dark.background, Colors.black);
    for (final brightness in Brightness.values) {
      final theme = buildFluentTheme(AppThemeData.builtinFor(brightness));
      expect(theme.accentColor.normal, const Color(0xFF8C3A2B));
    }
    final custom = AppThemeData.fromCustom(
      CustomTheme(
        id: 'mint',
        name: '薄荷',
        background: 0xFFF0FFF7,
        accent: 0xFF246B53,
      ),
    );
    expect(
      buildFluentTheme(custom).accentColor.normal,
      const Color(0xFF246B53),
    );
  });

  test('内置强调按钮各可用状态保持可读对比度', () {
    for (final brightness in Brightness.values) {
      final appTheme = AppThemeData.builtinFor(brightness);
      final theme = buildFluentTheme(appTheme);
      for (final states in <Set<WidgetState>>[
        {},
        {WidgetState.hovered},
        {WidgetState.pressed},
        {WidgetState.focused},
      ]) {
        final background = Color.alphaBlend(
          FilledButton.backgroundColor(theme, states),
          appTheme.background,
        );
        final foreground = Color.alphaBlend(
          FilledButton.foregroundColor(theme, states),
          background,
        );
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        final contrast = a > b
            ? (a + 0.05) / (b + 0.05)
            : (b + 0.05) / (a + 0.05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '$brightness $states',
        );
      }
    }
  });

  testWidgets('书架只显示一个作品主标题、累计字数和3:4封面', (tester) async {
    final h = await widgetHarness(tester);
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('封面唯一标题'),
    ))!;
    summary.wordCount = 1234;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await finishIo(tester);
    expect(find.text('全部作品'), findsOneWidget);
    expect(find.text('共 1 部作品 · 累计 1234 字'), findsOneWidget);
    expect(find.text('封面唯一标题'), findsOneWidget);
    expect(find.textContaining('最近编辑在前'), findsNothing);
    final cover = find.byKey(ValueKey('book-cover-${summary.id}'));
    final size = tester.getSize(cover);
    expect(size.width / size.height, closeTo(3 / 4, 0.001));
    final decoration =
        tester.widget<Container>(cover).decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.width, 1);
    expect(border.top.color, isNot(AppColors.cinnabar));
    expect(decoration.boxShadow, isNotEmpty, reason: '常态保留轻微封面阴影');
    await finishWidget(tester, h);
  });

  testWidgets('作品菜单28px、悬停淡入，离开后仍可Tab进入', (tester) async {
    final h = await widgetHarness(tester);
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('菜单作品'),
    ))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    final button = find.byKey(ValueKey('book-menu-${summary.id}'));
    expect(tester.getSize(button), const Size(28, 28));
    expect(menuOpacity(tester, button), 0);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1200, 10));
    await pointer.moveTo(tester.getCenter(find.text('菜单作品')));
    await tester.pumpAndSettle();
    expect(menuOpacity(tester, button), 1);
    await pointer.moveTo(const Offset(1200, 10));
    await tester.pumpAndSettle();
    expect(menuOpacity(tester, button), 0);
    for (var i = 0; i < 30 && menuOpacity(tester, button) == 0; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(menuOpacity(tester, button), 1, reason: '键盘焦点进入后显示菜单');
    await pointer.removePointer();
    await finishWidget(tester, h);
  });

  testWidgets('窄屏书架保留可见28px作品菜单', (tester) async {
    final h = await widgetHarness(tester, width: 900);
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('窄屏菜单'),
    ))!;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await tester.pumpAndSettle();
    final button = find.byKey(ValueKey('book-menu-${summary.id}'));
    expect(tester.getSize(button), const Size(28, 28));
    expect(menuOpacity(tester, button), 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('卷章菜单28px且按各自行悬停渐显', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('目录菜单');
      return h.app.library.openBook(summary);
    }))!;
    await tester.pumpWidget(
      FluentApp(
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final volume = book.volumes.first;
    final chapter = volume.chapters.first;
    if (find.byKey(ValueKey('chapter-row-${chapter.id}')).evaluate().isEmpty) {
      await tester.tap(find.byKey(ValueKey('toggle-volume-${volume.id}')));
      await tester.pumpAndSettle();
    }
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1200, 10));
    for (final (key, target) in [
      ('volume-menu-${volume.id}', 'toggle-volume-${volume.id}'),
      ('chapter-menu-${chapter.id}', 'select-chapter-${chapter.id}'),
    ]) {
      final button = find.byKey(ValueKey(key));
      expect(tester.getSize(button), const Size(28, 28));
      expect(menuOpacity(tester, button), 0);
      await pointer.moveTo(tester.getCenter(find.byKey(ValueKey(target))));
      await tester.pumpAndSettle();
      expect(menuOpacity(tester, button), 1);
      await pointer.moveTo(const Offset(1200, 10));
      await tester.pumpAndSettle();
      expect(menuOpacity(tester, button), 0);
    }
    await pointer.removePointer();
    await finishWidget(tester, h);
  });

  testWidgets('设置下拉撑满靠左、显示单位、完成为次级按钮', (tester) async {
    final h = await widgetHarness(tester);
    h.app.settings.setFontSize(18);
    h.app.settings.setLineHeight(1.9);
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await finishIo(tester);
    final gear = find.byKey(const ValueKey('settings-button'));
    expect(tester.widget(gear), isA<Button>());
    // 排序按钮位于同一标题工具栏；以新建按钮高度作为可点击入口基准。
    final create = find.ancestor(
      of: find.text('新建'),
      matching: find.byType(FilledButton),
    );
    expect(
      tester.getSize(gear).height,
      closeTo(tester.getSize(create).height, 1),
    );
    await tester.tap(gear);
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('settings-menu')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    for (final key in ['settings-language', 'settings-theme']) {
      expect(
        tester.widget<ComboBox<String>>(find.byKey(ValueKey(key))).isExpanded,
        isTrue,
      );
    }
    for (final key in ['settings-font-size', 'settings-line-height']) {
      expect(
        tester.widget<ComboBox<double>>(find.byKey(ValueKey(key))).isExpanded,
        isTrue,
      );
    }
    for (final key in [
      'settings-language',
      'settings-theme',
      'settings-font-size',
      'settings-line-height',
    ]) {
      final combo = find.byKey(ValueKey(key));
      final bounds = tester.renderObject<RenderBox>(combo);
      final label = find
          .descendant(of: combo, matching: find.byType(Text))
          .first;
      final text = tester.widget<Text>(label).data!;
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final glyphs = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final glyphLeft = bounds
          .globalToLocal(
            paragraph.localToGlobal(
              Offset(glyphs.first.left, glyphs.first.top),
            ),
          )
          .dx;
      expect(glyphLeft, inInclusiveRange(8, 20), reason: '$key 文字靠左而非居中');
      final chevron = tester.getRect(
        find.descendant(of: combo, matching: find.byType(Icon)).last,
      );
      final chevronRight = bounds.globalToLocal(chevron.bottomRight).dx;
      expect(
        bounds.size.width - chevronRight,
        inInclusiveRange(8, 20),
        reason: '$key 箭头保持靠右',
      );
    }
    expect(find.text('18 px'), findsOneWidget);
    expect(find.text('1.9 倍'), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('settings-done'))),
      isA<Button>(),
    );
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });
}
