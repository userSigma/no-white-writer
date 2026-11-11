import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/ui/shelf_page.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';
import 'package:no_white_writer/ui/settings_menu.dart';

import 'support/app_harness.dart';
import 'support/fake_platform.dart';
import 'support/pointer.dart';
import 'support/widget_harness.dart';

class _SettingsWriter extends AtomicFileWriter {
  bool fail = false;
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  final List<String> writes = [];
  @override
  Future<void> writeAtomically(File target, String content) async {
    if (target.path.endsWith('settings.json')) {
      writes.add(content);
      if (hold && writes.length == 1) {
        entered.complete();
        await release.future;
      }
      if (fail) throw const FileSystemException('settings write fault');
    }
    await super.writeAtomically(target, content);
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-button')));
  await finishIo(
    tester,
    until: () =>
        find.byKey(const ValueKey('settings-menu')).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('设置防抖错误可见但不成为未处理异常，显式 flush 抛错且重试后才清除', () async {
    final writer = _SettingsWriter()..fail = true;
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    final errors = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      h.app.settings.setThemeMode('dark');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      done.complete();
    }, (error, stack) => errors.add(error));
    await done.future;
    try {
      expect(errors, isEmpty);
      expect(h.app.settings.saveError, contains('settings write fault'));
      await expectLater(
        h.app.settings.flush(),
        throwsA(isA<FileSystemException>()),
      );
      expect(h.app.settings.saveError, isNotNull);
    } finally {
      writer.fail = false;
    }
    await h.app.settings.flush();
    expect(h.app.settings.saveError, isNull);
    expect((await h.app.settingsStore.load()).themeMode, 'dark');
  });

  test('相同在途设置共用保存，新快照串行且不被之后的内存改动污染', () async {
    final writer = _SettingsWriter()..hold = true;
    final h = await createHarness(writer: writer);
    addTearDown(h.dispose);
    h.app.settings.setFontSize(18);
    final first = h.app.settings.flush();
    await writer.entered.future;
    final same = h.app.settings.flush();
    h.app.settings.setFontSize(20);
    final second = h.app.settings.flush();
    h.app.settings.setFontSize(26);
    // No third flush yet: the queued middle snapshot must stay at 20.
    try {
      expect(writer.writes.length, 1);
    } finally {
      writer.release.complete();
    }
    await Future.wait([first, same, second]);
    expect(writer.writes.length, 2);
    expect(jsonDecode(writer.writes[0])['fontSize'], 18);
    expect(jsonDecode(writer.writes[1])['fontSize'], 20);
    await h.app.settings.flush();
    expect((await h.app.settingsStore.load()).fontSize, 26);
  });

  for (final width in [1280.0, 900.0]) {
    for (final editor in [false, true]) {
      testWidgets('真实设置入口打开设置浮窗而非页面 $width editor=$editor', (tester) async {
        final h = await widgetHarness(tester, width: width);
        Widget home = ShelfPage(app: h.app);
        if (editor) {
          final book = (await tester.runAsync(() async {
            final summary = await h.app.library.createBook('设置入口');
            return h.app.library.openBook(summary);
          }))!;
          home = EditorPage(app: h.app, book: book);
        }
        await tester.pumpWidget(FluentApp(home: home));
        if (editor) {
          await finishIo(tester, until: () => editorReady(tester));
          if (width < 1000) {
            expect(find.byKey(const ValueKey('settings-button')), findsNothing);
            await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
            await tester.pumpAndSettle();
          }
        }
        await _openSettings(tester);
        expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
        await finishWidget(tester, h);
      });
    }
  }

  testWidgets('桌面设置宽560且主题、目录操作同排，组间顺序与参考图一致', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    // ContentDialog itself includes a full-viewport Align; measure its painted
    // surface rather than mistaking that wrapper for the dialog bounds.
    final surface = find
        .descendant(
          of: find.byKey(const ValueKey('settings-menu')),
          matching: find.byType(Container),
        )
        .first;
    final box = tester.renderObject<RenderBox>(surface);
    // Fluent's default route scales its child even at the animation endpoint.
    // Compare logical geometry in the surface's coordinates, not scaled pixels.
    Rect rect(Finder finder) {
      final global = tester.getRect(finder);
      return Rect.fromPoints(
        box.globalToLocal(global.topLeft),
        box.globalToLocal(global.bottomRight),
      );
    }

    final bounds = Offset.zero & box.size;
    expect(bounds.width, closeTo(560, 1));
    expect(rect(find.text('语言')).left, closeTo(24, 1));
    for (final (control, action) in [
      ('settings-theme', 'settings-theme-manage'),
      ('settings-export-path', 'settings-change-export-path'),
    ]) {
      final input = rect(find.byKey(ValueKey(control)));
      final button = rect(find.byKey(ValueKey(action)));
      expect(button.top, closeTo(input.top, 1));
      expect(button.left - input.right, closeTo(8, 1));
      expect(bounds.right - button.right, closeTo(24, 1));
    }
    final open = tester.getRect(find.text('打开导出目录'));
    final reset = tester.getRect(find.text('恢复默认'));
    expect(open.center.dy, closeTo(reset.center.dy, 1));
    expect(open.left, lessThan(reset.left));
    expect(
      open.top,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey('settings-export-path')))
            .bottom,
      ),
    );
    var lastTop = double.negativeInfinity;
    for (final label in [
      '语言',
      '主题',
      '字号',
      '行距',
      '自动首行缩进',
      '段间空行',
      '导出目录',
      '系统目录',
      '不白写作 0.4.0',
    ]) {
      final top = tester.getTopLeft(find.text(label)).dy;
      expect(top, greaterThan(lastTop));
      lastTop = top;
    }
    expect(find.text('新建自定义主题…'), findsNothing);
    final close = rect(find.byKey(const ValueKey('settings-close')));
    final done = rect(find.byKey(const ValueKey('settings-done')));
    expect(close.right, closeTo(bounds.right - 24, 1));
    expect(close.top, lessThan(rect(find.text('语言')).top));
    expect(done.right, closeTo(bounds.right - 24, 1));
    expect(find.text('完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });

  for (final size in [const Size(360, 640), const Size(600, 480)]) {
    testWidgets('设置浮窗在小窗口$size内收缩、滚动且关闭控件固定可达', (tester) async {
      final h = await widgetHarness(
        tester,
        width: size.width,
        height: size.height,
      );
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: Align(
              alignment: Alignment.topLeft,
              child: SettingsMenuButton(app: h.app),
            ),
          ),
        ),
      );
      await _openSettings(tester);
      final surface = find
          .descendant(
            of: find.byKey(const ValueKey('settings-menu')),
            matching: find.byType(Container),
          )
          .first;
      final bounds = tester.getRect(surface);
      expect(bounds.width, lessThanOrEqualTo(560));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      if (size.width < 560) expect(bounds.width, greaterThan(280));
      final close = find.byKey(const ValueKey('settings-close'));
      final done = find.byKey(const ValueKey('settings-done'));
      expect(close.hitTestable(), findsOneWidget);
      expect(done.hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('不白写作 0.4.0'));
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(done);
      await finishIo(tester);
      expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
      await finishWidget(tester, h);
    });
  }

  testWidgets('主题管理区集中新建、重命名和删除且保持原有流程', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    expect(find.byKey(const ValueKey('settings-theme-create')), findsNothing);
    final manage = find.byKey(const ValueKey('settings-theme-manage'));
    await tester.tap(manage);
    await tester.pumpAndSettle();
    final create = find.byKey(const ValueKey('settings-theme-create'));
    expect(create, findsOneWidget);
    expect(
      tester.getTopLeft(create).dy,
      greaterThan(tester.getBottomLeft(manage).dy),
    );
    await tester.tap(create);
    await tester.pumpAndSettle();
    final createName = find
        .descendant(
          of: find.byType(ContentDialog).last,
          matching: find.byType(TextBox),
        )
        .first;
    await tester.enterText(createName, '布局主题');
    await tester.tap(find.text('创建并应用'));
    await finishIo(tester);
    final theme = h.app.settings.settings.customThemes.single;
    expect(theme.name, '布局主题');
    expect(h.app.settings.themeMode, 'custom:${theme.id}');
    final rename = find.byKey(ValueKey('custom-theme-rename-${theme.id}'));
    await tester.ensureVisible(rename);
    await tester.tap(rename);
    await tester.pumpAndSettle();
    final renameName = find
        .descendant(
          of: find.byType(ContentDialog).last,
          matching: find.byType(TextBox),
        )
        .first;
    await tester.enterText(renameName, '已重命名主题');
    await tester.tap(find.text('确定'));
    await finishIo(tester);
    expect(h.app.settings.settings.customThemes.single.name, '已重命名主题');
    final delete = find.byKey(ValueKey('custom-theme-delete-${theme.id}'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await finishIo(tester);
    expect(h.app.settings.settings.customThemes, isEmpty);
    expect(h.app.settings.themeMode, 'system');
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(create, findsNothing);
    await finishWidget(tester, h);
  });

  for (final closeKey in ['settings-close', 'settings-done']) {
    testWidgets('$closeKey 保存失败不关闭，重试成功后才关闭', (tester) async {
      final writer = _SettingsWriter();
      final h = await widgetHarness(tester, writer: writer);
      await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
      await _openSettings(tester);
      writer.fail = true;
      h.app.settings.setFontSize(22);
      try {
        await tester.tap(find.byKey(ValueKey(closeKey)));
        await finishIo(tester);
        expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
        expect(find.textContaining('设置保存失败'), findsWidgets);
      } finally {
        writer.fail = false;
      }
      await tester.tap(find.byKey(ValueKey(closeKey)));
      await finishIo(tester);
      expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
      expect((await tester.runAsync(h.app.settingsStore.load))!.fontSize, 22);
      await finishWidget(tester, h);
    });
  }

  testWidgets('验收入口自动弹出同一设置浮窗，不出现旧设置页面', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(
      FluentApp(home: ShelfPage(app: h.app, autoOpenSettings: true)),
    );
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('settings-menu')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    expect(find.text('不白写作 0.4.0'), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('设置浮窗改主题、字号、行距、缩进与空行，关闭后落盘并可重开读取', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await finishIo(tester);
    await tester.tap(find.text('深色（纯黑）'));
    await finishIo(tester);
    expect(h.app.settings.themeMode, 'dark');

    await tester.tap(find.byKey(const ValueKey('settings-font-size')));
    await finishIo(tester);
    await tester.tap(find.text('20 px'));
    await finishIo(tester);
    expect(h.app.settings.settings.fontSize, 20);

    await tester.tap(find.byKey(const ValueKey('settings-line-height')));
    await finishIo(tester);
    await tester.tap(find.text('2.0 倍'));
    await finishIo(tester);
    expect(h.app.settings.settings.lineHeight, 2.0);

    await tester.tap(find.byKey(const ValueKey('settings-auto-indent')));
    await finishIo(tester);
    expect(h.app.settings.settings.autoIndent, isTrue);

    await tester.tap(find.byKey(const ValueKey('settings-blank-line')));
    await finishIo(tester);
    expect(h.app.settings.settings.blankLineBetween, isTrue);

    // ComboBox 弹层关闭后，Esc 直接关闭设置浮窗。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
    await tester.runAsync(() => h.app.settings.flush());
    final saved = (await tester.runAsync(() => h.app.settingsStore.load()))!;
    expect(saved.themeMode, 'dark');
    expect(saved.fontSize, 20);
    expect(saved.lineHeight, 2.0);
    expect(saved.autoIndent, isTrue);
    expect(saved.blankLineBetween, isTrue);

    await _openSettings(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('ComboBox 弹层按 Esc 先关闭弹层，再按 Esc 才关闭设置浮窗', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await finishIo(tester);
    expect(find.text('浅色（纯白）'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    expect(find.text('浅色（纯白）'), findsNothing);
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
    await finishWidget(tester, h);
  });

  testWidgets('设置浮窗表面随主题实时换色，切换后内容仍可读', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
    await finishIo(tester);
    await _openSettings(tester);
    // 打开期间切换主题：浮窗所在 FluentTheme 的菜单色必须即时跟随。
    expect(
      FluentTheme.of(
        tester.element(find.byKey(const ValueKey('settings-menu'))),
      ).menuColor,
      AppColors.paper,
    );
    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await finishIo(tester);
    await tester.tap(find.text('深色（纯黑）'));
    await finishIo(tester);
    expect(h.app.settings.themeMode, 'dark');
    expect(
      FluentTheme.of(
        tester.element(find.byKey(const ValueKey('settings-menu'))),
      ).menuColor,
      AppColors.ink,
    );
    await finishWidget(tester, h);
  });

  testWidgets('导出目录只读，使用更改按钮且取消选择保持设置', (tester) async {
    final h = await widgetHarness(tester);
    final platform = h.app.platform as FakePlatformServices;
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    final box = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings-export-path')),
    );
    expect(box.readOnly, isTrue);
    expect(box.controller!.text, h.app.paths.exportRoot(null));
    expect(find.text('保存'), findsNothing);
    expect(find.text('系统目录'), findsOneWidget);
    for (final (label, control) in [
      ('主题', 'settings-theme'),
      ('导出目录', 'settings-export-path'),
    ]) {
      expect(
        (tester.getTopLeft(find.text(label)).dy -
                tester.getTopLeft(find.byKey(ValueKey(control))).dy)
            .abs(),
        lessThan(1),
        reason:
            '$label label must align with the first control, not its whole group',
      );
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-change-export-path')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-change-export-path')));
    await finishIo(tester);
    expect(platform.directoryInitialPath, h.app.paths.exportRoot(null));
    expect(h.app.settings.settings.exportDirectory, isNull);
    await finishWidget(tester, h);
  });

  testWidgets('设置保存失败时浮窗保留草稿并显示重试，重试成功后清除错误', (tester) async {
    final writer = _SettingsWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    (h.app.platform as FakePlatformServices).directoryToSelect = 'E:/保存失败';
    writer.fail = true;
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-change-export-path')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-change-export-path')));
    await finishIo(
      tester,
      until: () =>
          find
              .byKey(const ValueKey('settings-save-error'))
              .evaluate()
              .isNotEmpty ||
          find.textContaining('设置保存失败').evaluate().isNotEmpty,
    );
    expect(find.textContaining('设置保存失败'), findsWidgets);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('settings-export-path')))
          .controller!
          .text,
      'E:/保存失败',
    );
    expect(h.app.settings.settings.exportDirectory, 'E:/保存失败');
    writer.fail = false;
    await tester.ensureVisible(find.text('重试保存'));
    await tester.pump();
    await tester.tap(find.text('重试保存'));
    await finishIo(tester);
    expect(find.textContaining('设置保存失败'), findsNothing);
    expect(h.app.settings.settings.exportDirectory, 'E:/保存失败');
    final persisted = await tester.runAsync(h.app.settingsStore.load);
    expect(persisted!.exportDirectory, 'E:/保存失败');
    expect(find.text('设置已保存'), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('选择目录后立即保存且可恢复默认目录', (tester) async {
    final writer = _SettingsWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    (h.app.platform as FakePlatformServices).directoryToSelect = 'D:/新目录';
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-change-export-path')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-change-export-path')));
    await finishIo(tester);
    expect(h.app.settings.settings.exportDirectory, 'D:/新目录');
    expect(
      (await tester.runAsync(h.app.settingsStore.load))!.exportDirectory,
      'D:/新目录',
    );
    await tester.tap(find.text('恢复默认'));
    await finishIo(tester);
    expect(h.app.settings.settings.exportDirectory, isNull);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('settings-export-path')))
          .controller!
          .text,
      h.app.paths.exportRoot(null),
    );
    await finishWidget(tester, h);
  });

  testWidgets('目录选择期间阻止关闭，选择器异常保留原目录并显示错误', (tester) async {
    final h = await widgetHarness(tester);
    final platform = h.app.platform as FakePlatformServices;
    platform.directorySelection = Completer<String?>();
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    final change = find.byKey(const ValueKey('settings-change-export-path'));
    await tester.ensureVisible(change);
    await tester.tap(change);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('settings-close')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<Button>(find.byKey(const ValueKey('settings-done')))
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    platform.directorySelection!.complete(null);
    await finishIo(tester);
    platform.directoryError = StateError('picker fault');
    await tester.tap(change);
    await finishIo(tester);
    expect(find.textContaining('picker fault'), findsOneWidget);
    expect(h.app.settings.settings.exportDirectory, isNull);
    await finishWidget(tester, h);
  });

  testWidgets('编辑器中打开设置前先提交未保存的卷名草稿', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('草稿保护');
      return h.app.library.openBook(summary);
    }))!;
    await tester.pumpWidget(
      FluentApp(
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final volume = book.volumes.first;
    // Inline rename only mounts its TextBox while the row is in edit mode,
    // which is entered through the volume menu.
    await tapWithMouse(
      tester,
      find.byKey(ValueKey('volume-menu-${volume.id}')),
    );
    await finishIo(tester, until: () => find.text('重命名').evaluate().isNotEmpty);
    await tester.tap(find.text('重命名'));
    await finishIo(
      tester,
      until: () => find
          .byKey(ValueKey('volume-name-${volume.id}'))
          .evaluate()
          .isNotEmpty,
    );
    final input = find.byKey(ValueKey('volume-name-${volume.id}'));
    expect(input, findsOneWidget);
    await tester.enterText(input, '写了一半的卷名');
    await tester.pump();
    await _openSettings(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    final refreshed = (await tester.runAsync(
      () => h.app.library.readBookDetails(h.app.library.books.first),
    ))!;
    expect(refreshed.volumes.first.title, '写了一半的卷名');
    await finishWidget(tester, h);
  });

  test('设置页路由已从全部入口移除', () {
    final main = File('lib/main.dart').readAsStringSync();
    final shelf = File('lib/ui/shelf_page.dart').readAsStringSync();
    final editor = File('lib/ui/editor_page.dart').readAsStringSync();
    for (final source in [main, shelf, editor]) {
      expect(source.contains('SettingsPage'), isFalse);
      expect(source.contains('settings_page.dart'), isFalse);
    }
  });
}
