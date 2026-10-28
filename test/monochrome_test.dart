import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

void main() {
  test('只改纯白纯黑内容底色，其余 token 和 Fluent 配置恢复 0.2', () {
    expect(AppColors.paper, const Color(0xFFFFFFFF));
    expect(AppColors.ink, const Color(0xFF000000));
    expect(AppColors.textOnPaper, const Color(0xFF2B2A27));
    expect(AppColors.textOnInk, const Color(0xFFEDE8DF));
    expect(AppColors.cinnabar, const Color(0xFFA6402B));
    expect(AppColors.cinnabarSoft, const Color(0xFFC9795F));
    expect(AppColors.hairlineOnPaper, const Color(0xFFE3DACB));
    expect(AppColors.hairlineOnInk, const Color(0xFF2B2D31));
    expect(AppColors.mutedOnPaper, const Color(0xFF7A7267));
    expect(AppColors.mutedOnInk, const Color(0xFF9A948A));
    for (final b in Brightness.values) {
      final t = buildFluentTheme(AppThemeData.builtinFor(b));
      final bg = b == Brightness.light ? Colors.white : Colors.black;
      final original = FluentThemeData(
        brightness: b,
        scaffoldBackgroundColor: bg,
        accentColor: AccentColor.swatch(const {
          'normal': Color(0xFFA6402B),
          'light1': Color(0xFFC9795F),
          'light2': Color(0xFFD9A28D),
          'dark1': Color(0xFF8E3524),
          'dark2': Color(0xFF6E291C),
        }),
      );
      expect(t.scaffoldBackgroundColor, bg);
      // 菜单表面三字段必须与背景一致：FlyoutContent 在 color=null 时把
      // menuColor@0.65 叠在 acrylic 回退底上，同色合成实心背景，且随
      // FluentTheme 实时切换（子菜单主题冻结修复的前提）。
      expect(t.menuColor, bg);
      expect(t.acrylicBackgroundColor, bg);
      expect(t.acrylicFallbackColor, bg);
      expect(t.accentColor.normal, original.accentColor.normal);
      expect(
        t.resources.textFillColorPrimary,
        original.resources.textFillColorPrimary,
      );
      expect(
        t.resources.systemFillColorCritical,
        original.resources.systemFillColorCritical,
      );
      expect(t.selectionColor, original.selectionColor);
      expect(t.buttonTheme, original.buttonTheme);
    }
    expect(spineGradient(17).colors, [
      HSLColor.fromAHSL(1, 17, 0.34, 0.42).toColor(),
      HSLColor.fromAHSL(1, 43, 0.30, 0.28).toColor(),
    ]);
  });

  for (final b in Brightness.values) {
    testWidgets('设置浮窗保留 0.2 朱砂与 Fluent 通知，仅内容底色纯白纯黑：$b', (tester) async {
      final h = await widgetHarness(tester);
      h.app.settings.setThemeMode(b == Brightness.light ? 'light' : 'dark');
      await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
      await finishIo(tester);
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await finishIo(
        tester,
        until: () =>
            find.byKey(const ValueKey('settings-menu')).evaluate().isNotEmpty,
      );
      final bg = b == Brightness.light ? Colors.white : Colors.black;
      final context = tester.element(
        find.byKey(const ValueKey('settings-menu')),
      );
      expect(FluentTheme.of(context).scaffoldBackgroundColor, bg);
      expect(paperOrInk(context), bg);
      // 关于区随浮窗直接可见；主题选项在 ComboBox 弹层里展开。
      expect(find.text('不白写作 0.4.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-theme')));
      await finishIo(tester);
      // ComboBox 弹层同时渲染选中项与下拉项，标签会出现两处。
      expect(find.text('浅色（纯白）'), findsWidgets);
      expect(find.text('深色（纯黑）'), findsWidgets);
      final headings = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.color == const Color(0xFFA6402B));
      expect(headings, isNotEmpty, reason: '0.2 的设置标题为朱砂，而非强制黑白');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await finishIo(tester);
      await tester.tap(find.text('保存'));
      await finishIo(
        tester,
        until: () => find.text('导出目录已保存').evaluate().isNotEmpty,
      );
      expect(find.text('导出目录已保存'), findsOneWidget);
      expect(
        find.byType(InfoBar),
        findsOneWidget,
        reason: '沿用 0.2 的 Fluent 通知样式，不继续使用强制黑白浮层',
      );
      await finishWidget(tester, h);
    });
  }
  for (final b in Brightness.values) {
    testWidgets('真实书架与编辑器恢复彩色书脊、朱砂光标与保存状态：$b', (tester) async {
      final h = await widgetHarness(tester);
      final summary = (await tester.runAsync(
        () => h.app.library.createBook('样式回归'),
      ))!;
      h.app.settings.setThemeMode(b == Brightness.light ? 'light' : 'dark');
      await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
      await finishIo(tester);
      final gradients = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>();
      expect(
        gradients.any(
          (g) =>
              g.colors.first == spineGradient(summary.coverSeed).colors.first &&
              g.colors.last == spineGradient(summary.coverSeed).colors.last,
        ),
        isTrue,
      );
      await tester.tap(find.text('样式回归').first);
      await finishIo(tester, until: () => editorReady(tester));
      expect(find.byType(EditorPage), findsOneWidget);
      final pageContext = tester.element(find.byType(EditorPage));
      expect(
        paperOrInk(pageContext),
        b == Brightness.light ? Colors.white : Colors.black,
      );
      final body = tester.widget<TextField>(
        find.byKey(const ValueKey('chapter-body')),
      );
      expect(body.cursorColor, const Color(0xFFA6402B));
      expect(
        tester
            .widgetList<Container>(find.byType(Container))
            .any(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration as BoxDecoration).color ==
                      const Color(0xFF5C8A57),
            ),
        isTrue,
        reason: '恢复 0.2 已保存的绿色小圆点',
      );
      expect(tester.takeException(), isNull);
      await finishWidget(tester, h);
    });
  }

  testWidgets('卡片右键在指针旁打开菜单，编辑 stable ID 不进入正文', (tester) async {
    final h = await widgetHarness(tester);
    final first = (await tester.runAsync(
      () => h.app.library.createBook('A作品'),
    ))!;
    await tester.runAsync(() => h.app.library.createBook('Z作品'));
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    final position = tester.getCenter(find.text('A作品').first);
    await tester.tapAt(position, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('编辑信息'), findsOneWidget);
    final rect = tester.getRect(find.text('编辑信息'));
    expect((rect.topLeft - position).distance, lessThan(240));
    await tester.tap(find.text('编辑信息'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('book-title-input')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('book-title-input')), findsOneWidget);
    expect(find.byType(EditorPage), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('book-title-input')),
      'B新名称',
    );
    await tester.enterText(
      find.byKey(const ValueKey('book-notes-input')),
      '只改此书',
    );
    await tester.tap(find.text('保存'));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('book-title-input')).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => h.app.library.openBook(
        h.app.library.books.firstWhere((b) => b.id == first.id),
      ),
    );
    expect(saved!.title, 'B新名称');
    expect(saved.notes, '只改此书');
    expect(h.app.library.books.any((b) => b.title == 'Z作品'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
