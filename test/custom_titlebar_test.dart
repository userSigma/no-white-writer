import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/core/platform/platform_services.dart';

import 'support/fake_platform.dart';

import 'support/widget_harness.dart';

void main() {
  testWidgets('窗口命令与拖动分离，外部状态及全屏实时更新', (tester) async {
    final h = await widgetHarness(tester, width: 900);
    final platform = h.app.platform as FakePlatformServices;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    final drag = find.byKey(const ValueKey('window-drag-area'));
    await tester.drag(drag, const Offset(50, 10));
    await tester.pumpAndSettle();
    expect(platform.dragCalls, 1);
    await tester.tap(drag);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(drag);
    await tester.pumpAndSettle();
    expect(platform.maximizeCalls, 1);
    expect(find.byTooltip('还原'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('window-minimize')));
    await tester.tap(find.byKey(const ValueKey('window-maximize')));
    await tester.pumpAndSettle();
    expect(platform.minimizeCalls, 1);
    expect(platform.maximizeCalls, 2);
    expect(platform.dragCalls, 1);
    platform.windowState.value = const DesktopWindowState(maximized: true);
    await tester.pump();
    expect(find.byTooltip('还原'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('settings-menu')).evaluate().isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('window-close')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-done')));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('settings-menu')).evaluate().isEmpty,
    );
    expect(platform.dragCalls, 1);
    platform.windowState.value = const DesktopWindowState(fullScreen: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('window-title-bar')), findsNothing);
    expect(find.byKey(const ValueKey('window-close')), findsNothing);
    platform.windowState.value = const DesktopWindowState();
    await tester.pump();
    expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  testWidgets('不支持桌面窗口的平台不呈现窗口按钮', (tester) async {
    final h = await widgetHarness(tester);
    (h.app.platform as FakePlatformServices).supportsCustomTitleBar = false;
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-close')), findsNothing);
    expect(find.byKey(const ValueKey('settings-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });
  testWidgets('书架品牌顶栏独立，作品操作归位内容标题行', (tester) async {
    final h = await widgetHarness(tester, width: 900, height: 600);
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await finishIo(
      tester,
      until: () => find.text('全部作品').evaluate().isNotEmpty,
    );
    final bar = find.byKey(const ValueKey('window-title-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).height, 36);
    expect(
      tester
          .widget<FluentApp>(find.byType(FluentApp))
          .debugShowCheckedModeBanner,
      isFalse,
      reason: '调试标记不能覆盖右上角自绘窗口按钮',
    );
    for (final key in [
      'window-brand',
      'window-minimize',
      'window-maximize',
      'window-close',
    ]) {
      final target = find.byKey(ValueKey(key));
      expect(target, findsOneWidget);
      expect(tester.getCenter(target).dy, closeTo(tester.getCenter(bar).dy, 1));
    }
    for (final target in [
      find.text('新建'),
      find.text('最近编辑'),
      find.byKey(const ValueKey('settings-button')),
    ]) {
      expect(find.descendant(of: bar, matching: target), findsNothing);
      expect(
        tester.getCenter(target).dy,
        closeTo(tester.getCenter(find.text('全部作品')).dy, 1),
      );
    }
    expect(find.text('全部作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  for (final width in [900.0, 1280.0]) {
    testWidgets('写作顶栏合并导航与保存状态，目录切换后不复制 ($width)', (tester) async {
      final h = await widgetHarness(tester, width: width);
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('合并顶栏');
        return h.app.library.openBook(summary);
      }))!;
      await tester.pumpWidget(
        NoWhiteWriterApp(
          app: h.app,
          home: EditorPage(app: h.app, book: book),
        ),
      );
      await finishIo(tester, until: () => editorReady(tester));
      final bar = find.byKey(const ValueKey('window-title-bar'));
      expect(bar, findsOneWidget);
      final toggle = find.byKey(
        ValueKey(width >= 1000 ? 'toggle-sidebar' : 'open-chapter-pane'),
      );
      final back = find.byKey(const ValueKey('back-to-shelf'));
      expect(tester.getCenter(toggle).dx, lessThan(tester.getCenter(back).dx));
      for (final target in [
        toggle,
        back,
        find.byKey(const ValueKey('editor-save-status')),
      ]) {
        expect(find.descendant(of: bar, matching: target), findsOneWidget);
      }
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('window-title-bar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('window-close')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-pane-host'), skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finishWidget(tester, h);
    });
  }
}
