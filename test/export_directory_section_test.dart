import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
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

Future<BuildContext> _mount(
  WidgetTester tester,
  ExportDirectoryDraft draft,
  AppPaths paths,
) async {
  late BuildContext sectionContext;
  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (context) {
          sectionContext = context;
          return ExportDirectorySection(draft: draft, paths: paths);
        },
      ),
    ),
  );
  return sectionContext;
}

void main() {
  testWidgets('目录分区独立挂载，路径只读且取消选择保留设置', (tester) async {
    final h = await widgetHarness(tester);
    String? initial;
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      paths: h.app.paths,
      selectDirectory: ({initialDirectory}) async {
        initial = initialDirectory;
        return null;
      },
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    final context = await _mount(tester, draft, h.app.paths);
    final field = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings-export-path')),
    );
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, h.app.paths.exportRoot(null));
    expect(find.text('保存'), findsNothing);
    await tester.runAsync(() => draft.change(context));
    expect(initial, h.app.paths.exportRoot(null));
    expect(h.app.settings.settings.exportDirectory, isNull);
    expect(draft.path.text, h.app.paths.exportRoot(null));
    expect(await tester.runAsync(() => draft.prepareClose(context)), isTrue);
    expect(find.byType(ContentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立目录选择保存失败保留已选路径，重试提交同一选择', (tester) async {
    final writer = _DirectoryWriter()..fail = true;
    final h = await widgetHarness(tester, writer: writer);
    addTearDown(() => writer.fail = false);
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      paths: h.app.paths,
      selectDirectory: ({initialDirectory}) async => 'picked-target',
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    final context = await _mount(tester, draft, h.app.paths);
    await tester.runAsync(() => draft.change(context));
    expect(draft.path.text, h.app.paths.exportRoot('picked-target'));
    expect(h.app.settings.settings.exportDirectory, 'picked-target');
    expect(h.app.settings.saveError, contains('directory draft fault'));
    expect(await tester.runAsync(() => draft.prepareClose(context)), isFalse);
    writer.fail = false;
    await tester.runAsync(() => draft.retry(context));
    expect(h.app.settings.saveError, isNull);
    expect(h.app.settings.settings.exportDirectory, 'picked-target');
    final persisted = await tester.runAsync(h.app.settingsStore.load);
    expect(persisted!.exportDirectory, 'picked-target');
  });

  testWidgets('目录保存未完成时拦截关闭；保存结束后可正常关闭', (tester) async {
    final writer = _DirectoryWriter()..hold = true;
    final h = await widgetHarness(tester, writer: writer);
    addTearDown(() {
      if (!writer.release.isCompleted) writer.release.complete();
    });
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      paths: h.app.paths,
      selectDirectory: ({initialDirectory}) async => 'in-flight',
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    final context = await _mount(tester, draft, h.app.paths);
    var finished = false;
    unawaited(draft.change(context).then((_) => finished = true));
    try {
      await finishIo(tester, until: () => writer.entered.isCompleted);
      expect(draft.working, isTrue);
      expect(await draft.prepareClose(context), isFalse);
      expect(finished, isFalse);
    } finally {
      writer.release.complete();
    }
    await finishIo(tester, until: () => finished);
    expect(draft.working, isFalse);
    expect(await tester.runAsync(() => draft.prepareClose(context)), isTrue);
  });

  testWidgets('原生选择未完成时保留父会话，取消后恢复操作并支持恢复默认', (tester) async {
    final h = await widgetHarness(tester);
    final selection = Completer<String?>();
    final draft = ExportDirectoryDraft(
      settings: h.app.settings,
      paths: h.app.paths,
      selectDirectory: ({initialDirectory}) => selection.future,
      revealDirectory: (_) async => true,
      notice: (_, _) {},
    );
    addTearDown(draft.dispose);
    final context = await _mount(tester, draft, h.app.paths);
    final picking = draft.change(context);
    await tester.pump();
    expect(draft.working, isTrue);
    expect(await draft.prepareClose(context), isFalse);
    expect(
      tester
          .widget<Button>(
            find.byKey(const ValueKey('settings-change-export-path')),
          )
          .onPressed,
      isNull,
    );
    selection.complete(null);
    await picking;
    await tester.pump();
    expect(draft.working, isFalse);
    expect(find.byKey(const ValueKey('settings-export-path')), findsOneWidget);
    h.app.settings.setExportDirectory('external-target');
    await tester.runAsync(h.app.settings.flush);
    expect(draft.path.text, h.app.paths.exportRoot('external-target'));
    await tester.runAsync(() => draft.change(context, useDefault: true));
    expect(h.app.settings.settings.exportDirectory, isNull);
    expect(draft.path.text, h.app.paths.exportRoot(null));
    expect(
      (await tester.runAsync(h.app.settingsStore.load))!.exportDirectory,
      isNull,
    );
    expect(await tester.runAsync(() => draft.prepareClose(context)), isTrue);
  });
}
