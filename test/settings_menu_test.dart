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

import 'support/app_harness.dart';
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
    await tester.tap(find.text('20'));
    await finishIo(tester);
    expect(h.app.settings.settings.fontSize, 20);

    await tester.tap(find.byKey(const ValueKey('settings-line-height')));
    await finishIo(tester);
    await tester.tap(find.text('2.0'));
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

  testWidgets('导出目录草稿未保存时关闭浮窗需要确认，继续编辑保留草稿，丢弃后才关闭', (tester) async {
    final h = await widgetHarness(tester);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    final box = find.byKey(const ValueKey('settings-export-path'));
    await tester.enterText(box, 'D:/草稿目录');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    expect(find.text('导出目录尚未保存'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await finishIo(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    expect(tester.widget<TextBox>(box).controller!.text, 'D:/草稿目录');
    expect(h.app.settings.settings.exportDirectory, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);
    await tester.tap(find.text('丢弃修改'));
    await finishIo(tester);
    expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
    expect(h.app.settings.settings.exportDirectory, isNull);
    await finishWidget(tester, h);
  });

  testWidgets('设置保存失败时浮窗保留草稿并显示重试，重试成功后清除错误', (tester) async {
    final writer = _SettingsWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    await tester.enterText(
      find.byKey(const ValueKey('settings-export-path')),
      'E:/保存失败',
    );
    await tester.pump();
    writer.fail = true;
    await tester.tap(find.text('保存'));
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
    expect(h.app.settings.settings.exportDirectory, isNull);
    writer.fail = false;
    await tester.ensureVisible(find.text('重试保存'));
    await tester.pump();
    await tester.tap(find.text('重试保存'));
    await finishIo(tester);
    expect(find.textContaining('设置保存失败'), findsNothing);
    expect(h.app.settings.settings.exportDirectory, 'E:/保存失败');
    final persisted = await tester.runAsync(h.app.settingsStore.load);
    expect(persisted!.exportDirectory, 'E:/保存失败');
    expect(find.text('导出目录已保存'), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('导出目录输入法组词中不能保存或关闭浮窗，组词结束后恢复', (tester) async {
    final writer = _SettingsWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    final box = find.byKey(const ValueKey('settings-export-path'));
    await tester.tap(box);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'zhu',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(writer.writes, isEmpty);
    expect(h.app.settings.settings.exportDirectory, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    expect(find.text('导出目录尚未保存'), findsNothing);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '主',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await finishIo(tester);
    expect(find.text('导出目录已保存'), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('目录真实组词时点击外部不得清除 composing 或弹出丢弃确认', (tester) async {
    final writer = _SettingsWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.pumpWidget(FluentApp(home: ShelfPage(app: h.app)));
    await _openSettings(tester);
    final field = find.byKey(const ValueKey('settings-export-path'));
    await tester.tap(field);
    const draft = TextEditingValue(
      text: '目录组词',
      composing: TextRange(start: 0, end: 4),
      selection: TextSelection.collapsed(offset: 4),
    );
    tester.testTextInput.updateEditingValue(draft);
    await tester.pump();
    final writesBefore = writer.writes.length;
    await tester.tapAt(const Offset(12, 100));
    await finishIo(tester);
    expect(tester.widget<TextBox>(field).controller!.value, draft);
    expect(find.text('导出目录尚未保存'), findsNothing);
    expect(find.byKey(const ValueKey('settings-menu')), findsOneWidget);
    expect(writer.writes.length, writesBefore);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '已上屏目录',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
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
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
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
