import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/ui/settings/export_directory_section.dart';

import 'support/widget_harness.dart';

class _DirectoryWriter extends AtomicFileWriter {
  bool fail = false;
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> writeAtomically(File target, String content) async {
    if (target.path.endsWith('settings.json')) {
      if (hold) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
      if (fail) throw const FileSystemException('directory draft fault');
    }
    await super.writeAtomically(target, content);
  }
}

void main() {
  testWidgets('目录分区独立挂载，IME 时保存与关闭均被守卫', (tester) async {
    final h = await widgetHarness(tester);
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    late BuildContext sectionContext;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            sectionContext = context;
            return ListenableBuilder(
              listenable: draft,
              builder: (_, _) =>
                  ExportDirectorySection(draft: draft, paths: h.app.paths),
            );
          },
        ),
      ),
    );
    draft.path.value = const TextEditingValue(
      text: '拼音候选',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    await tester.pump();
    final save = tester.widget<Button>(find.widgetWithText(Button, '保存'));
    expect(save.onPressed, isNull);
    expect(await draft.prepareClose(sectionContext), isFalse);
    await draft.save(sectionContext);
    expect(draft.path.value.composing, const TextRange(start: 0, end: 4));
    expect(h.app.settings.settings.exportDirectory, isNull);
    expect(find.byType(ContentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立目录草稿保存失败保留输入，重试提交同一草稿', (tester) async {
    final writer = _DirectoryWriter()..fail = true;
    final h = await widgetHarness(tester, writer: writer);
    addTearDown(() => writer.fail = false);
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    late BuildContext sectionContext;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            sectionContext = context;
            return ExportDirectorySection(draft: draft, paths: h.app.paths);
          },
        ),
      ),
    );
    draft.path.text = '  draft-target  ';
    await tester.runAsync(() => draft.save(sectionContext));
    expect(draft.path.text, '  draft-target  ');
    expect(draft.dirty, isTrue);
    expect(h.app.settings.settings.exportDirectory, isNull);
    expect(h.app.settings.saveError, contains('directory draft fault'));
    writer.fail = false;
    await tester.runAsync(() => draft.retry(sectionContext));
    expect(h.app.settings.saveError, isNull);
    expect(draft.dirty, isFalse);
    expect(h.app.settings.settings.exportDirectory, 'draft-target');
    final persisted = await tester.runAsync(h.app.settingsStore.load);
    expect(persisted!.exportDirectory, 'draft-target');
  });

  testWidgets('目录保存未完成时拒绝关闭；保存结束后可正常关闭', (tester) async {
    final writer = _DirectoryWriter()..hold = true;
    final h = await widgetHarness(tester, writer: writer);
    addTearDown(() {
      if (!writer.release.isCompleted) writer.release.complete();
    });
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    late BuildContext sectionContext;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            sectionContext = context;
            return ExportDirectorySection(draft: draft, paths: h.app.paths);
          },
        ),
      ),
    );
    draft.path.text = 'in-flight';
    var finished = false;
    unawaited(draft.save(sectionContext).then((_) => finished = true));
    try {
      await finishIo(tester, until: () => writer.entered.isCompleted);
      expect(draft.working, isTrue);
      expect(await draft.prepareClose(sectionContext), isFalse);
      expect(finished, isFalse);
    } finally {
      writer.release.complete();
    }
    await finishIo(tester, until: () => finished);
    expect(draft.working, isFalse);
    expect(
      await tester.runAsync(() => draft.prepareClose(sectionContext)),
      isTrue,
    );
  });

  testWidgets('目录丢弃确认只处理草稿，不关闭父级设置会话', (tester) async {
    final h = await widgetHarness(tester);
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    late BuildContext sectionContext;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            sectionContext = context;
            return ExportDirectorySection(draft: draft, paths: h.app.paths);
          },
        ),
      ),
    );
    draft.path.text = 'unsaved';
    bool? closed;
    unawaited(
      draft.prepareClose(sectionContext).then((value) => closed = value),
    );
    await tester.pumpAndSettle();
    expect(draft.confirming, isTrue);
    expect(await draft.prepareClose(sectionContext), isFalse);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(draft.path.text, 'unsaved');
    closed = null;
    unawaited(
      draft.prepareClose(sectionContext).then((value) => closed = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃修改'));
    await finishIo(tester, until: () => closed != null);
    expect(closed, isTrue);
    expect(draft.dirty, isFalse);
    expect(find.byKey(const ValueKey('settings-export-path')), findsOneWidget);
    expect(h.app.settings.settings.exportDirectory, isNull);
  });
}
