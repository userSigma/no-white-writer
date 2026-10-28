import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/ui/chapter_pane.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

const _frameKey = ValueKey('sidebar-frame');
const _hostKey = ValueKey('chapter-pane-host');

Future<BookIndex> _openBook(WidgetTester tester, dynamic h) async {
  return (await tester.runAsync(() async {
    final summary = await h.app.library.createBook('动画');
    return h.app.library.openBook(summary);
  }))!;
}

Future<void> _pumpEditor(
  WidgetTester tester,
  dynamic h,
  BookIndex book, {
  Size size = const Size(1280, 820),
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentTheme(AppThemeData.light),
      home: EditorPage(app: h.app, book: book),
    ),
  );
  await finishIo(tester, until: () => editorReady(tester));
}

double _paneWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(_frameKey, skipOffstage: false)).width;

/// 等待真实 IO 完成但只推进 1ms 一帧，避免顺手把 200ms 过渡跑完。
Future<void> _waitIo(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 500 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue, reason: '等待条件成立');
}

void main() {
  testWidgets('折叠与展开是真实过渡：中间帧宽度介于两端，可反向，终态精确', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);

    expect(_paneWidth(tester), 280);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final double middle = _paneWidth(tester);
    expect(middle, greaterThan(0));
    expect(middle, lessThan(280));

    // 反向：展开中再次点击，不得继续塌陷到 0。
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => !h.app.settings.settings.sidebarCollapsed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final double reversed = _paneWidth(tester);
    expect(reversed, greaterThan(middle));

    await tester.pump(const Duration(milliseconds: 400));
    expect(_paneWidth(tester), 280);
    expect(h.app.settings.settings.sidebarCollapsed, isFalse);

    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(_paneWidth(tester), 0);
    expect(h.app.settings.settings.sidebarCollapsed, isTrue);
    // 不是 84px 窄轨。
    expect(find.byKey(_frameKey, skipOffstage: false), findsOneWidget);
    await finishWidget(tester, h);
  });

  testWidgets('减少动画时折叠立即到位，不播放中间帧', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    expect(_paneWidth(tester), 280);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await finishIo(
      tester,
      until: () => h.app.settings.settings.sidebarCollapsed,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(_paneWidth(tester), 0);
    await finishWidget(tester, h);
  });

  testWidgets('底部固定 footer：左返回、右设置，顶栏不再有返回／设置／导出', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);

    expect(find.byKey(const ValueKey('back-to-shelf')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-button')), findsOneWidget);
    expect(find.text('导出本章'), findsNothing);
    expect(find.byKey(const ValueKey('open-chapter-pane')), findsNothing);

    final Rect back = tester.getRect(
      find.byKey(const ValueKey('back-to-shelf')),
    );
    final Rect gear = tester.getRect(
      find.byKey(const ValueKey('settings-button')),
    );
    final Rect pane = tester.getRect(
      find.byKey(const ValueKey('sidebar-frame')),
    );
    expect(back.left, greaterThanOrEqualTo(pane.left));
    expect(back.center.dx, lessThan(pane.center.dx));
    expect(back.bottom, inInclusiveRange(pane.bottom - 56, pane.bottom));
    expect(gear.right, lessThanOrEqualTo(pane.right));
    expect(gear.center.dx, greaterThan(pane.center.dx));
    expect(gear.bottom, inInclusiveRange(pane.bottom - 56, pane.bottom));

    // 已确认 B：整个目录完全收起，footer 也必须一起隐藏。
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('back-to-shelf')), findsNothing);
    expect(find.byKey(const ValueKey('settings-button')), findsNothing);
    await finishWidget(tester, h);
  });

  testWidgets('窄窗目录是同一实例的浮层：打开、Escape 关闭、草稿不丢', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book, size: const Size(900, 700));
    expect(find.byKey(const ValueKey('open-chapter-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('toggle-sidebar')), findsNothing);
    expect(find.byKey(_hostKey, skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    final Finder pane = find.byType(ChapterPane, skipOffstage: false);
    expect(pane, findsOneWidget);
    final Rect box = tester.getRect(pane);
    expect(box.width, lessThanOrEqualTo(900));
    expect(box.height, lessThanOrEqualTo(700));

    // 无内联编辑时，普通 Escape 关闭浮层。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('chapter-pane-barrier')).evaluate().isEmpty,
    );
    expect(find.byKey(const ValueKey('chapter-pane-barrier')), findsNothing);
    expect(book.volumes.first.title, '未命名卷');

    // 重新打开：真实内联卷名草稿点遮罩关闭时先提交，不丢字。
    await tester.tap(find.byKey(const ValueKey('open-chapter-pane')));
    await tester.pumpAndSettle();
    final volume = book.volumes.first;
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('volume-name-${volume.id}'));
    expect(input, findsOneWidget);
    await tester.enterText(input, '窄窗卷名');
    // 浮层居中 440x420：点 (40,300) 落在遮罩上而不是浮层内。
    await tester.tapAt(const Offset(40, 300));
    await finishIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('chapter-pane-barrier')).evaluate().isEmpty,
    );
    expect(book.volumes.first.title, '窄窗卷名');
    expect(find.byKey(const ValueKey('chapter-pane-barrier')), findsNothing);
    await finishWidget(tester, h);
  });

  testWidgets('宽窄往返不复制目录实例，也不自动改变折叠偏好', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    expect(find.byType(ChapterPane, skipOffstage: false), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    expect(find.byType(ChapterPane, skipOffstage: false), findsOneWidget);
    expect(h.app.settings.settings.sidebarCollapsed, isFalse);

    await tester.binding.setSurfaceSize(const Size(1280, 820));
    await tester.pumpAndSettle();
    expect(find.byType(ChapterPane, skipOffstage: false), findsOneWidget);
    expect(_paneWidth(tester), 280);
    await finishWidget(tester, h);
  });

  testWidgets('1100 宽侧栏 240，80ms 中间帧，200ms 帧到位', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book, size: const Size(1100, 820));
    expect(_paneWidth(tester), 240);

    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final double at80 = _paneWidth(tester);
    expect(at80, greaterThan(0));
    expect(at80, lessThan(240));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_paneWidth(tester), 0);
    await finishWidget(tester, h);
  });

  testWidgets('折叠后隐藏目录不可 Tab 到达，也不挡住正文点击', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pumpAndSettle();
    expect(_paneWidth(tester), 0);
    expect(
      tester
          .widget<Offstage>(
            find
                .ancestor(
                  of: find.byKey(_hostKey, skipOffstage: false),
                  matching: find.byType(Offstage),
                )
                .first,
          )
          .offstage,
      isTrue,
    );
    // 折叠区域的点击落在正文层，不会打开目录。
    await tester.tapAt(const Offset(60, 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('chapter-pane-barrier')), findsNothing);
    expect(h.app.settings.settings.sidebarCollapsed, isTrue);
    // Tab 焦点不会进入隐藏目录。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final BuildContext? focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null) {
      bool inside = false;
      focus.visitAncestorElements((Element e) {
        if (e.widget.key == _hostKey) inside = true;
        return !inside;
      });
      expect(inside, isFalse, reason: '隐藏目录不得获得键盘焦点');
    }
    await finishWidget(tester, h);
  });

  testWidgets('折叠偏好落盘，重读为已折叠', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pumpAndSettle();
    expect(_paneWidth(tester), 0);
    await finishWidget(tester, h);

    // 用同一数据目录重新读设置，模拟重启后读盘。
    final loaded = (await tester.runAsync(h.app.settingsStore.load))!;
    expect(loaded.sidebarCollapsed, isTrue);
  });

  testWidgets('以已折叠偏好启动时第一帧就在 0，不播放收起动画', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    h.app.settings.setSidebarCollapsed(true);
    // 先落盘，避免测试拆卸时还有在途写入占用临时目录。
    await tester.runAsync(h.app.settings.flush);
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: EditorPage(app: h.app, book: book),
      ),
    );
    await tester.pump();
    expect(_paneWidth(tester), 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_paneWidth(tester), 0);
    // 首帧观察完再等待初始选择与 remember IO 结束，不能提前删除夹具根。
    await finishIo(tester, until: () => editorReady(tester));
    await finishWidget(tester, h);
  });

  testWidgets('响应式往返保留内联卷名草稿，不重建输入', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    final volume = book.volumes.first;
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('volume-name-${volume.id}'));
    await tester.enterText(input, '宽窄之间的草稿');

    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    await tester.pump();
    final input2 = find.byKey(ValueKey('volume-name-${volume.id}'));
    expect(input2, findsOneWidget);
    expect(tester.widget<TextBox>(input2).controller!.text, '宽窄之间的草稿');
    // 提交草稿后收尾，避免拆卸时仍有在途写盘。
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(tester);
    await finishWidget(tester, h);
  });

  testWidgets('标题或正文组词中折叠被拒绝，结束后可折叠', (tester) async {
    final h = await widgetHarness(tester);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    h.app.editor.title.value = const TextEditingValue(
      text: '组词中的标题',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump();
    expect(h.app.editor.isComposing, isTrue);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(h.app.settings.settings.sidebarCollapsed, isFalse);
    expect(_paneWidth(tester), 280);

    h.app.editor.title.value = const TextEditingValue(
      text: '组词中的标题',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    expect(h.app.editor.isComposing, isFalse);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pumpAndSettle();
    expect(_paneWidth(tester), 0);
    await finishWidget(tester, h);
  });

  testWidgets('内联草稿保存失败时折叠被拒，草稿仍在且可重试', (tester) async {
    final writer = _FailBookWriter();
    final h = await widgetHarness(tester, writer: writer);
    final book = await _openBook(tester, h);
    await _pumpEditor(tester, h, book);
    final volume = book.volumes.first;
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('volume-name-${volume.id}'));
    await tester.enterText(input, '写盘失败也要留住');
    writer.failing = true;
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await finishIo(tester);
    expect(h.app.settings.settings.sidebarCollapsed, isFalse);
    expect(find.byKey(ValueKey('volume-name-${volume.id}')), findsOneWidget);
    expect(
      tester
          .widget<TextBox>(find.byKey(ValueKey('volume-name-${volume.id}')))
          .controller!
          .text,
      '写盘失败也要留住',
    );

    writer.failing = false;
    // 用户修好写盘后，先让内联名字真正提交，再折叠。
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await finishIo(tester);
    expect(find.byKey(ValueKey('volume-name-${volume.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await _waitIo(tester, () => h.app.settings.settings.sidebarCollapsed);
    await tester.pumpAndSettle();
    expect(_paneWidth(tester), 0);
    await finishWidget(tester, h);
  });
}

class _FailBookWriter extends AtomicFileWriter {
  bool failing = false;

  @override
  Future<void> writeAtomically(File file, String text) async {
    if (failing && file.path.endsWith('book.json')) {
      throw const FileSystemException('模拟写盘失败');
    }
    await super.writeAtomically(file, text);
  }
}
