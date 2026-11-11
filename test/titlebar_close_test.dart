import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/state/export_controller.dart';

import 'support/fake_platform.dart';
import 'support/widget_harness.dart';

class _FailIndexWriter extends AtomicFileWriter {
  bool fail = false;
  @override
  Future<void> writeAtomically(File target, String content) async {
    if (fail && target.path.endsWith('book.json')) {
      throw const FileSystemException('caption close save fault');
    }
    return super.writeAtomically(target, content);
  }
}

void main() {
  final close = find.byKey(const ValueKey('window-close'));
  for (final field in ['title', 'body']) {
    testWidgets('自绘关闭保留 $field 输入法候选且不写磁盘', (tester) async {
      final h = await widgetHarness(tester);
      final book = (await tester.runAsync(() async {
        final summary = await h.app.library.createBook('关闭组词');
        final book = await h.app.library.openBook(summary);
        await h.app.editor.open(
          inBook: book,
          inVolume: book.volumes.first,
          inChapter: book.allChapters.first,
        );
        return book;
      }))!;
      final before = h.app.paths.bookFile(book.id).readAsBytesSync();
      final body = h.app.paths.chapterFile(
        book.id,
        book.volumes.first.id,
        book.allChapters.first.id,
      );
      final beforeBody = body.readAsBytesSync();
      final input = field == 'title' ? h.app.editor.title : h.app.editor.text;
      const candidate = TextEditingValue(
        text: '未完成候选',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      input.value = candidate;
      final platform = h.app.platform as FakePlatformServices;
      AppExitResponse? response;
      platform.onRequestClose = () async {
        response = await tester.binding.handleRequestAppExit();
      };
      await tester.pumpWidget(
        NoWhiteWriterApp(app: h.app, home: const SizedBox()),
      );
      await tester.pump();
      await tester.tap(close);
      await finishIo(tester, until: () => response != null);
      expect(response, AppExitResponse.cancel);
      expect(input.value, candidate);
      expect(h.app.paths.bookFile(book.id).readAsBytesSync(), before);
      expect(body.readAsBytesSync(), beforeBody);
      expect(platform.quitCalled, isFalse);
      input.clearComposing();
      await finishWidget(tester, h);
    });
  }

  testWidgets('自绘关闭经过界面草稿门禁，提交后保存再退出', (tester) async {
    final h = await widgetHarness(tester);
    final book = (await tester.runAsync(() async {
      final summary = await h.app.library.createBook('关闭草稿');
      final book = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: book.allChapters.first,
      );
      return book;
    }))!;
    var allow = false;
    final guard = h.app.registerUiGuard(() async => allow);
    final platform = h.app.platform as FakePlatformServices;
    AppExitResponse? response;
    platform.onRequestClose = () async {
      response = await tester.binding.handleRequestAppExit();
    };
    await tester.pumpWidget(
      NoWhiteWriterApp(app: h.app, home: const SizedBox()),
    );
    await tester.pump();
    await tester.tap(close);
    await finishIo(tester, until: () => response != null);
    expect(response, AppExitResponse.cancel);
    allow = true;
    response = null;
    h.app.editor.text.text = '关闭前必须保存的正文';
    await tester.tap(close);
    await finishIo(tester, until: () => response != null);
    expect(response, AppExitResponse.exit);
    expect(
      h.app.paths
          .chapterFile(
            book.id,
            book.volumes.first.id,
            book.allChapters.first.id,
          )
          .readAsStringSync(),
      '关闭前必须保存的正文',
    );
    expect(platform.quitCalled, isFalse);
    h.app.removeUiGuard(guard);
    await finishWidget(tester, h);
  });

  testWidgets('自绘关闭不能截断在途导出', (tester) async {
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
      final summary = await h.app.library.createBook('关闭导出');
      return h.app.library.openBook(summary);
    }))!;
    final platform = h.app.platform as FakePlatformServices;
    AppExitResponse? response;
    platform.onRequestClose = () async {
      response = await tester.binding.handleRequestAppExit();
    };
    await tester.pumpWidget(
      NoWhiteWriterApp(app: h.app, home: const SizedBox()),
    );
    await tester.pump();
    var done = false;
    h.app.exporter.export(ExportTarget.book(book.id)).then((_) => done = true);
    try {
      await finishIo(tester, until: () => entered.isCompleted);
      await tester.tap(close);
      await finishIo(tester, until: () => response != null);
      expect(response, AppExitResponse.cancel);
      expect(h.app.exporter.busy, isTrue);
      expect(platform.quitCalled, isFalse);
    } finally {
      release.complete();
      await finishIo(tester, until: () => done);
    }
    await finishWidget(tester, h);
  });

  testWidgets('保存失败时重复关闭只保留一个决策框，取消后可重试', (tester) async {
    final writer = _FailIndexWriter();
    final h = await widgetHarness(tester, writer: writer);
    await tester.runAsync(() async {
      final summary = await h.app.library.createBook('重复关闭');
      final book = await h.app.library.openBook(summary);
      await h.app.editor.open(
        inBook: book,
        inVolume: book.volumes.first,
        inChapter: book.allChapters.first,
      );
    });
    final platform = h.app.platform as FakePlatformServices;
    final responses = <AppExitResponse>[];
    platform.onRequestClose = () async {
      responses.add(await tester.binding.handleRequestAppExit());
    };
    await tester.pumpWidget(
      NoWhiteWriterApp(app: h.app, home: const SizedBox()),
    );
    h.app.editor.text.text = '不能丢失的草稿';
    writer.fail = true;
    try {
      await tester.tap(close);
      await finishIo(
        tester,
        until: () => find.text('取消退出').evaluate().isNotEmpty,
      );
      await tester.tap(close);
      await finishIo(tester);
      expect(find.text('这一章还没保存成功'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('window-close')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('取消退出'));
      await finishIo(tester, until: () => responses.length == 2);
      expect(responses, everyElement(AppExitResponse.cancel));
      expect(h.app.editor.text.text, '不能丢失的草稿');
      writer.fail = false;
      await tester.tap(close);
      await finishIo(tester, until: () => responses.length == 3);
      expect(responses.last, AppExitResponse.exit);
      expect(platform.quitCalled, isFalse);
    } finally {
      writer.fail = false;
    }
    await finishWidget(tester, h);
  });
}
