import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/state/workspace_controller.dart';
import 'package:no_white_writer/ui/chapter_pane.dart';
import 'package:no_white_writer/ui/theme/tokens.dart';

import 'support/widget_harness.dart';

class _HeldWriter extends AtomicFileWriter {
  Completer<void>? hold;
  int heldWrites = 0;

  @override
  Future<void> writeAtomically(File file, String content) async {
    if (hold != null && file.path.endsWith('book.json')) {
      heldWrites++;
      await hold!.future;
    }
    await super.writeAtomically(file, content);
  }
}

void main() {
  testWidgets('内联提交握手复用同一个在途请求，不重复写盘', (tester) async {
    final writer = _HeldWriter();
    final h = await widgetHarness(tester, writer: writer);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('重复提交');
      return h.app.library.openBook(summary);
    }))!;
    final workspace = WorkspaceController(
      book: book,
      library: h.app.library,
      editor: h.app.editor,
    );
    final draft = ChapterPaneDraft();
    addTearDown(workspace.dispose);
    addTearDown(draft.dispose);
    final volume = book.volumes.first;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: ChapterPane(workspace: workspace, expanded: {}, draft: draft),
      ),
    );
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ValueKey('volume-name-${volume.id}')),
      '只写一次',
    );
    final hold = writer.hold = Completer<void>();
    final first = draft.flush();
    bool? saved;
    first.then((value) => saved = value);
    try {
      await finishIo(tester, until: () => writer.heldWrites > 0);
      expect(writer.heldWrites, 1);
      expect(draft.flush(), same(first));
      expect(draft.flush(), same(first));
      expect(workspace.busy, isTrue);
      expect(volume.title, '未命名卷');
    } finally {
      hold.complete();
    }
    await finishIo(tester, until: () => saved != null);
    expect(saved, isTrue);
    expect(writer.heldWrites, 1);
    expect(volume.title, '只写一次');
    writer.hold = null;
    await finishWidget(tester, h);
  });

  testWidgets('更换草稿握手对象后，新对象仍提交原内联草稿，旧对象解绑', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('草稿生命周期');
      return h.app.library.openBook(summary);
    }))!;
    final workspace = WorkspaceController(
      book: book,
      library: h.app.library,
      editor: h.app.editor,
    );
    final first = ChapterPaneDraft(), second = ChapterPaneDraft();
    addTearDown(workspace.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final volume = book.volumes.first;
    Widget pane(ChapterPaneDraft draft) => FluentApp(
      theme: buildFluentTheme(AppThemeData.light),
      home: ChapterPane(workspace: workspace, expanded: {}, draft: draft),
    );
    await tester.pumpWidget(pane(first));
    await tester.tap(find.byKey(ValueKey('volume-menu-${volume.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('volume-name-${volume.id}'));
    await tester.enterText(input, '更换后保留的稿');
    await tester.pumpWidget(pane(second));
    bool? oldSaved;
    first.flush().then((value) => oldSaved = value);
    await finishIo(tester, until: () => oldSaved != null);
    expect(oldSaved, isTrue);
    expect(volume.title, '未命名卷', reason: '旧握手必须解绑，不能提交仍挂载的草稿');
    bool? saved;
    second.flush().then((value) => saved = value);
    await finishIo(tester, until: () => saved != null);
    expect(saved, isTrue);
    expect(volume.title, '更换后保留的稿');
    expect(input, findsNothing);
    await finishWidget(tester, h);
  });

  testWidgets('拖动中来源已失效时不接受落点，取消后释放拖动锁', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('落点校验');
      final book = await h.app.library.openBook(summary);
      await h.app.library.structure.appendVolume(book, title: '空目标');
      return book;
    }))!;
    final workspace = WorkspaceController(
      book: book,
      library: h.app.library,
      editor: h.app.editor,
    );
    addTearDown(workspace.dispose);
    final source = book.volumes.first, target = book.volumes.last;
    final chapter = source.chapters.single;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(AppThemeData.light),
        home: ChapterPane(workspace: workspace, expanded: {source.id}),
      ),
    );
    bool? entered;
    workspace.enterMove(false).then((value) => entered = value);
    await finishIo(tester, until: () => entered != null);
    expect(entered, isTrue);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('chapter-grip-${chapter.id}'))),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(workspace.dragging, isTrue);
    source.chapters.remove(chapter);
    try {
      final drop = find.byKey(ValueKey('chapter-drop-volume-${target.id}'));
      await gesture.moveTo(tester.getCenter(drop));
      await tester.pump();
      final decoration =
          tester.widget<Container>(drop).decoration! as BoxDecoration;
      expect(decoration.border, isNull, reason: '同书ID不足以证明拖动来源仍然存在');
    } finally {
      source.chapters.add(chapter);
      await gesture.cancel();
      await tester.pumpAndSettle();
    }
    expect(workspace.dragging, isFalse);
    await finishWidget(tester, h);
  });
}
