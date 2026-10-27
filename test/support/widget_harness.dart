import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';

import 'app_harness.dart';

Future<AppHarness> widgetHarness(
  WidgetTester tester, {
  double width = 1280,
  double height = 820,
  AtomicFileWriter writer = const AtomicFileWriter(),
  Future<List<int>> Function(File)? exportReadBytes,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = (await tester.runAsync(
    () => createHarness(writer: writer, exportReadBytes: exportReadBytes),
  ))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    bool finished = false;
    Object? failure;
    h.dispose().then<void>(
      (_) {
        finished = true;
      },
      onError: (Object error) {
        failure = error;
        finished = true;
      },
    );
    await finishIo(tester, until: () => finished);
    expect(finished, isTrue, reason: '临时资源清理结束');
    expect(failure, isNull);
  });
  return h;
}

Future<void> finishIo(WidgetTester tester, {bool Function()? until}) async {
  for (int i = 0; i < (until == null ? 80 : 500); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until?.call() ?? false) break;
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> finishWidget(WidgetTester tester, AppHarness h) async {
  bool done = false;
  () async {
    await h.app.editor.flush();
    await h.app.settings.flush();
    done = true;
  }();
  await finishIo(tester, until: () => done);
  expect(done, isTrue);
  await tester.pumpWidget(const SizedBox.shrink());
}

bool editorReady(WidgetTester tester) {
  final body = find.byKey(const ValueKey('chapter-body'));
  return body.evaluate().isNotEmpty && !tester.widget<TextField>(body).readOnly;
}
