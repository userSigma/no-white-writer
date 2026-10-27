import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/export_controller.dart';
import 'package:no_white_writer/state/workspace_controller.dart';

import 'support/app_harness.dart';
import 'support/widget_harness.dart';

class _FailIndexWriter extends AtomicFileWriter {
  bool fail = false;
  @override
  Future<void> writeAtomically(File target, String content) async {
    if (fail && target.path.endsWith('book.json')) {
      throw const FileSystemException('emergency exit index fault');
    }
    return super.writeAtomically(target, content);
  }
}

void main() {
  testWidgets('保存失败退出仍保留独立的内存正文导出逃生', (tester) async {
    final writer = _FailIndexWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.runAsync(() async {
      final summary = await h.app.library.createBook('逃生测试');
      final book = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: book.allChapters.first,
      );
    });
    h.app.settings.settings.exportDirectory = '${h.root.path}/exports';
    h.app.editor.text.text = '逃生草稿';
    writer.fail = true;
    try {
      await tester.pumpWidget(
        NoWhiteWriterApp(app: h.app, home: const SizedBox()),
      );
      AppExitResponse? response;
      tester.binding.handleRequestAppExit().then((value) => response = value);
      await finishIo(
        tester,
        until: () => find.text('导出到文档后退出').evaluate().isNotEmpty,
      );
      expect(response, isNull);
      await tester.tap(find.text('导出到文档后退出'));
      await finishIo(tester, until: () => response != null);
      expect(response, AppExitResponse.exit);
      final content = await tester.runAsync(() async {
        final file =
            (await Directory('${h.root.path}/exports')
                    .list(recursive: true, followLinks: false)
                    .toList())
                .whereType<File>()
                .single;
        return file.readAsString();
      });
      expect(content, '逃生草稿\n');
    } finally {
      writer.fail = false;
    }
    await finishWidget(tester, h);
  });
  for (final field in ['title', 'body']) {
    testWidgets('原生退出不强制落盘或清理 $field 的输入法候选', (tester) async {
      final h = await widgetHarness(tester);
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('退出候选');
        final book = await h.app.library.openBook(summary);
        await h.app.editor.open(
          inBook: book,
          inVolume: book.volumes.first,
          inChapter: book.allChapters.first,
        );
        return book;
      }))!;
      final before = (await tester.runAsync(
        () => h.app.paths.bookFile(book.id).readAsBytes(),
      ))!;
      final input = field == 'title' ? h.app.editor.title : h.app.editor.text;
      input.value = const TextEditingValue(
        text: '候选',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.pumpWidget(
        NoWhiteWriterApp(app: h.app, home: const SizedBox()),
      );
      AppExitResponse? response;
      tester.binding.handleRequestAppExit().then((value) => response = value);
      await finishIo(tester, until: () => response != null);
      expect(response, AppExitResponse.cancel);
      expect(input.value.composing, const TextRange(start: 0, end: 2));
      expect(
        await tester.runAsync(
          () => h.app.paths.bookFile(book.id).readAsBytes(),
        ),
        before,
      );
      input.clearComposing();
      await finishWidget(tester, h);
    });

    testWidgets('生命周期隐藏和暂停不强制保存 $field 的组词候选', (tester) async {
      final h = await widgetHarness(tester);
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('失焦候选');
        final book = await h.app.library.openBook(summary);
        await h.app.editor.open(
          inBook: book,
          inVolume: book.volumes.first,
          inChapter: book.allChapters.first,
        );
        return book;
      }))!;
      final index = h.app.paths.bookFile(book.id);
      final body = h.app.paths.chapterFile(
        book.id,
        book.volumes.first.id,
        book.allChapters.first.id,
      );
      final beforeIndex = index.readAsBytesSync();
      final beforeBody = body.readAsBytesSync();
      final input = field == 'title' ? h.app.editor.title : h.app.editor.text;
      const candidate = TextEditingValue(
        text: ' 组词候选 ',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 1, end: 5),
      );
      input.value = candidate;
      await tester.pumpWidget(
        NoWhiteWriterApp(app: h.app, home: const SizedBox()),
      );
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await finishIo(tester);
        expect(input.value, candidate);
        expect(index.readAsBytesSync(), beforeIndex);
        expect(body.readAsBytesSync(), beforeBody);
        expect(h.app.editor.isDirty, isTrue);
      } finally {
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        input.clearComposing();
      }
      await finishWidget(tester, h);
    });
  }

  for (final action in ['create', 'menu', 'settings']) {
    testWidgets('在途导出时书架 $action 不可操作，完成后恢复', (tester) async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final h = await widgetHarness(
        tester,
        exportReadBytes: (file) async {
          if (file.path.endsWith('.txt')) {
            entered.complete();
            await release.future;
          }
          return file.readAsBytes();
        },
      );
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('书架忙碌测试');
        return h.app.library.openBook(summary);
      }))!;
      await tester.pumpWidget(NoWhiteWriterApp(app: h.app));
      await tester.pumpAndSettle();
      var done = false;
      h.app.exporter
          .export(ExportTarget.book(book.id))
          .then((_) => done = true);
      try {
        await finishIo(tester, until: () => entered.isCompleted);
        expect(entered.isCompleted, isTrue);
        if (action == 'create') {
          final button = find.ancestor(
            of: find.text('新建'),
            matching: find.byType(FilledButton),
          );
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
        } else if (action == 'settings') {
          final button = find.descendant(
            of: find.byTooltip('设置'),
            matching: find.byType(IconButton),
          );
          expect(tester.widget<IconButton>(button).onPressed, isNull);
        } else {
          await tester.tap(find.byKey(ValueKey('book-menu-${book.id}')));
          await tester.pumpAndSettle();
          expect(find.text('编辑信息'), findsNothing);
        }
      } finally {
        release.complete();
        await finishIo(tester, until: () => done);
      }
      if (action == 'create') {
        final button = find.ancestor(
          of: find.text('新建'),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      }
      await finishWidget(tester, h);
    });
  }

  testWidgets('原生退出请求不能截断在途导出', (tester) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final h = await widgetHarness(
      tester,
      exportReadBytes: (file) async {
        if (file.path.endsWith('.txt')) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
        return file.readAsBytes();
      },
    );
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('退出测试');
      final book = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: book.allChapters.first,
      );
      return book;
    }))!;
    await tester.pumpWidget(
      NoWhiteWriterApp(app: h.app, home: const SizedBox()),
    );
    Object? output;
    var done = false;
    h.app.exporter
        .export(ExportTarget.book(book.id))
        .then<void>(
          (file) {
            output = file;
            done = true;
          },
          onError: (Object error) {
            output = error;
            done = true;
          },
        );
    try {
      await finishIo(tester, until: () => entered.isCompleted);
      expect(entered.isCompleted, isTrue);
      AppExitResponse? response;
      tester.binding.handleRequestAppExit().then((value) => response = value);
      await finishIo(tester, until: () => response != null);
      expect(response, AppExitResponse.cancel);
      expect(h.app.exporter.busy, isTrue);
      expect(find.text('正在导出，请完成后再关闭。'), findsOneWidget);
      expect(done, isFalse);
    } finally {
      release.complete();
      await finishIo(tester, until: () => done);
    }
    expect(output, isA<File>());
    await finishWidget(tester, h);
  });

  testWidgets('退出先询问 UI 草稿守卫，拒绝后不强行保存或销毁输入', (tester) async {
    final h = await widgetHarness(tester);
    var called = 0;
    final token = h.app.registerUiGuard(() async {
      called++;
      return false;
    });
    await tester.pumpWidget(
      NoWhiteWriterApp(app: h.app, home: const SizedBox()),
    );
    AppExitResponse? response;
    tester.binding.handleRequestAppExit().then((value) => response = value);
    await finishIo(tester, until: () => response != null);
    expect(called, 1);
    expect(response, AppExitResponse.cancel);
    h.app.removeUiGuard(token);
    response = null;
    tester.binding.handleRequestAppExit().then((value) => response = value);
    await finishIo(tester, until: () => response != null);
    expect(response, AppExitResponse.exit);
    expect(called, 1);
    await finishWidget(tester, h);
  });

  for (final operation in ['change', 'drag']) {
    test('在途导出拒绝工作区 $operation，不事后补执行', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final h = await createHarness(
        exportReadBytes: (file) async {
          if (file.path.endsWith('.txt')) {
            entered.complete();
            await release.future;
          }
          return file.readAsBytes();
        },
      );
      addTearDown(h.dispose);
      final summary = await h.app.library.createBook('工作区');
      final book = await h.app.library.openBook(summary);
      final w = WorkspaceController(
        book: book,
        library: h.app.library,
        editor: h.app.editor,
      );
      addTearDown(w.dispose);
      expect(await w.initialize(), isTrue);
      final pending = h.app.exporter.export(ExportTarget.book(book.id));
      await entered.future;
      Future<bool>? mutation;
      var ran = false;
      try {
        if (operation == 'drag') {
          w.moveMode = MoveMode.chapters;
          expect(w.beginDrag(), isFalse);
        } else {
          mutation = w.change(() async {
            ran = true;
          });
          expect(w.busy, isFalse);
        }
      } finally {
        w.endDrag();
        release.complete();
        await pending;
        if (mutation != null) expect(await mutation, isFalse);
      }
      expect(ran, isFalse);
    });
  }
}
