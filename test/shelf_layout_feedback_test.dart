import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/ui/format.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/page_harness.dart';
import 'support/widget_harness.dart';

Future<List<Color>> pixels(
  WidgetTester tester,
  GlobalKey boundaryKey,
  List<Offset> points, {
  double scale = 1,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return points.map((point) {
        final local = boundary.globalToLocal(point);
        final x = (local.dx * scale).floor();
        final y = (local.dy * scale).floor();
        final index = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(index + 3),
          bytes.getUint8(index),
          bytes.getUint8(index + 1),
          bytes.getUint8(index + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void contained(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

void main() {
  for (final width in [900.0, 1280.0, 1600.0]) {
    testWidgets('操作与搜索同在全部作品行，搜索独立居中 ($width)', (tester) async {
      final h = await widgetHarness(tester, width: width);
      await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
      await tester.pumpAndSettle();
      final caption = find.byKey(const ValueKey('window-title-bar'));
      final title = tester.getRect(find.text('全部作品'));
      final search = tester.getRect(find.byKey(const ValueKey('shelf-search')));
      expect(search.width, closeTo(320, .01));
      expect(
        search.center.dx,
        closeTo(width / 2, .01),
        reason: '搜索框自身居中，不再与右侧按钮拼成一组',
      );
      expect(title.center.dy, closeTo(search.center.dy, 2));
      expect(title.right, lessThan(search.left - 8), reason: '标题与搜索框同排且不重叠');
      for (final target in [
        find.text('最近编辑'),
        find.byKey(const ValueKey('settings-button')),
        find.text('新建'),
      ]) {
        expect(find.descendant(of: caption, matching: target), findsNothing);
        final rect = tester.getRect(target);
        expect(
          rect.center.dy,
          closeTo(search.center.dy, 2),
          reason: '操作与搜索框在同一行垂直居中',
        );
        expect(rect.left, greaterThan(search.right), reason: '操作与搜索框不重叠');
      }
      expect(find.byKey(const ValueKey('shelf-grid-view')), findsNothing);
      expect(find.byKey(const ValueKey('shelf-list-view')), findsNothing);
      expect(find.byKey(const ValueKey('shelf-book-grid')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishWidget(tester, h);
    });
  }

  testWidgets('书架只保留一种样式，搜索过滤后回车打开可见作品', (tester) async {
    final h = await widgetHarness(tester, width: 1280);
    await tester.runAsync(() async {
      await h.app.library.createBook('Alpha');
      await h.app.library.createBook('Beta');
    });
    await tester.pumpWidget(FluentApp(home: shelfPage(app: h.app)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-book-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-book-list')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('shelf-search')), 'alp');
    await tester.pump();
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Alpha'), findsWidgets);
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

  testWidgets('统计时间与菜单收进原3:4书框，新建外框完全等大', (tester) async {
    final h = await widgetHarness(tester);
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('保留书框尺寸'),
    ))!;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    final cover = find.byKey(ValueKey('book-cover-${summary.id}'));
    final coverRect = tester.getRect(cover);
    expect(coverRect.size.width, 220);
    expect(coverRect.size.height, closeTo(220 * 4 / 3, .001));
    final stats = find.text(h.app.library.statsLine(summary));
    final date = find.text(relativeTime(summary.updatedAt));
    final menu = find.byKey(ValueKey('book-menu-${summary.id}'));
    for (final child in [stats, date, menu]) {
      contained(coverRect, tester.getRect(child));
    }
    expect(tester.getTopLeft(stats).dy, greaterThan(coverRect.center.dy));
    expect(tester.getCenter(stats).dx, lessThan(tester.getCenter(menu).dx));
    expect(tester.getSize(menu), const Size(28, 28));
    expect(
      find.descendant(of: cover, matching: find.text('不白写作')),
      findsNothing,
    );
    final creation = tester.getRect(
      find.byKey(const ValueKey('shelf-new-book-tile')),
    );
    expect(creation.width, closeTo(coverRect.width, .001));
    expect(creation.height, closeTo(coverRect.height, .001));
    expect(creation.top, closeTo(coverRect.top, .001));
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  testWidgets('新建外框在空书架保持3:4，悬停有真实底色和提示且尺寸不变', (tester) async {
    final h = await widgetHarness(tester);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: NoWhiteWriterApp(app: h.app),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('shelf-new-book-tile'));
    final initialRect = tester.getRect(tile);
    expect(initialRect.width, 220);
    expect(initialRect.height, closeTo(220 * 4 / 3, .001));
    final probe = initialRect.topLeft + const Offset(10, 10);
    final before = (await pixels(tester, boundary, [probe])).single;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 100));
    await mouse.moveTo(initialRect.center);
    await tester.pumpAndSettle();
    final hovered = (await pixels(tester, boundary, [probe])).single;
    expect(hovered, isNot(before), reason: '不能只有透明背景而无悬停提示');
    expect(tester.getRect(tile), initialRect);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('创建新作品'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 100));
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect((await pixels(tester, boundary, [probe])).single, before);
    await finishWidget(tester, h);
  });

  testWidgets('新建卡片可Tab聚焦，呈现提示底色并用Enter打开创建表单', (tester) async {
    final h = await widgetHarness(tester);
    await tester.runAsync(() => h.app.library.createBook('已有作品'));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: NoWhiteWriterApp(app: h.app),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('shelf-new-book-tile'));
    final probe = tester.getTopLeft(tile) + const Offset(10, 10);
    final before = (await pixels(tester, boundary, [probe])).single;
    for (var i = 0; i < 30 && !Focus.of(tester.element(tile)).hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(Focus.of(tester.element(tile)).hasFocus, isTrue);
    // The focus frame starts AnimatedContainer; settle its ensuing paint frames.
    await tester.pumpAndSettle();
    expect((await pixels(tester, boundary, [probe])).single, isNot(before));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book-title-input')), findsOneWidget);
    expect(h.app.editor.book, isNull, reason: '不能误打开已有作品');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await finishWidget(tester, h);
  });

  testWidgets('深色书框内的选中统计仍满足正文对比度', (tester) async {
    final h = await widgetHarness(tester);
    h.app.settings.setThemeMode('dark');
    final summary = (await tester.runAsync(
      () => h.app.library.createBook('可读统计'),
    ))!;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    final cover = tester.widget<Container>(
      find.byKey(ValueKey('book-cover-${summary.id}')),
    );
    final background = (cover.decoration! as BoxDecoration).color!;
    final stats = tester.widget<Text>(
      find.text(h.app.library.statsLine(summary)),
    );
    final foreground = Color.alphaBlend(stats.style!.color!, background);
    final luminance = [
      foreground.computeLuminance(),
      background.computeLuminance(),
    ]..sort();
    expect(
      (luminance.last + .05) / (luminance.first + .05),
      greaterThanOrEqualTo(4.5),
    );
    await finishWidget(tester, h);
  });

  for (final mode in ['light', 'dark', 'custom']) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('标题栏底线穿过所有窗口按钮及悬停按下 ($mode/$scale)', (tester) async {
        final h = await widgetHarness(tester, width: 900, height: 600);
        if (mode == 'custom') {
          final theme = h.app.settings.addCustomTheme(
            background: 0xFFF6F1E7,
            accent: 0xFF356858,
            name: '纸与松',
          )!;
          h.app.settings.setThemeMode('custom:${theme.id}');
        } else {
          h.app.settings.setThemeMode(mode);
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: NoWhiteWriterApp(app: h.app),
          ),
        );
        await tester.pumpAndSettle();
        final bar = find.byKey(const ValueKey('window-title-bar'));
        final barRect = tester.getRect(bar);
        final line = hairlineColor(tester.element(bar));
        final y = ((barRect.bottom * scale).floor() - .5) / scale;
        final points = [
          Offset(
            tester.getCenter(find.byKey(const ValueKey('window-drag-area'))).dx,
            y,
          ),
          for (final id in ['minimize', 'maximize', 'close'])
            Offset(tester.getCenter(find.byKey(ValueKey('window-$id'))).dx, y),
        ];
        Future<void> expectLine(String state) async {
          final actual = await pixels(tester, boundary, points, scale: scale);
          for (var i = 0; i < actual.length; i++) {
            expect(actual[i], line, reason: '$state pixel $i');
          }
        }

        await expectLine('normal');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(5, 100));
        final close = tester.getCenter(
          find.byKey(const ValueKey('window-close')),
        );
        await mouse.moveTo(close);
        await tester.pumpAndSettle();
        await expectLine('hover');
        await mouse.down(close);
        await tester.pump(const Duration(milliseconds: 200));
        await expectLine('pressed');
        await mouse.moveTo(const Offset(5, 100));
        await mouse.up();
        await mouse.removePointer();
        await tester.pumpAndSettle();
        await finishWidget(tester, h);
      });
    }
  }
}
