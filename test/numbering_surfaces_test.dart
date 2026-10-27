import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/state/export_controller.dart';
import 'package:no_white_writer/ui/editor_page.dart';

import 'support/app_harness.dart';
import 'support/fake_platform.dart';
import 'support/widget_harness.dart';

void main() {
  test('导出名称复用显示编号而正文和原名保持不变，同名不覆盖', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final s = await h.app.library.createBook('编号导出'),
        b = await h.app.library.openBook(s),
        v = b.volumes.first,
        c = v.chapters.first;
    await h.app.editor.open(inBook: b, inVolume: v, inChapter: c);
    h.app.editor.title.text = '第 2 章 原章名';
    h.app.editor.text.text = '只导出正文\n';
    await h.app.editor.flush();
    await h.app.editor.runStructure(
      b,
      () => h.app.library.setNumbering(
        b,
        v,
        const ChapterNumbering(
          enabled: true,
          prefix: '',
          suffix: '',
          padding: 3,
          start: 7,
          step: 2,
        ),
      ),
    );
    final one = (await h.app.exporter.export(
          ExportTarget.chapter(b.id, v.id, c.id),
        ))!,
        two = (await h.app.exporter.export(
          ExportTarget.chapter(b.id, v.id, c.id),
        ))!;
    expect(one.uri.pathSegments.last, '007 第 2 章 原章名.txt');
    expect(two.path, isNot(one.path));
    expect(await one.readAsString(), '只导出正文\n');
    expect(c.title, '第 2 章 原章名');
    expect(h.app.editor.title.text, c.title);
    await h.app.editor.runStructure(
      b,
      () => h.app.library.setNumbering(b, v, const ChapterNumbering()),
    );
    final off = (await h.app.exporter.export(
      ExportTarget.chapter(b.id, v.id, c.id),
    ))!;
    expect(off.uri.pathSegments.last, '第 2 章 原章名.txt');
  });
  testWidgets('窗口标题随规则及原始标题草稿更新且不写入前缀', (tester) async {
    final h = await widgetHarness(tester);
    final b = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('窗口名');
      final b = await h.app.library.openBook(s);
      await h.app.library.setNumbering(
        b,
        b.volumes.first,
        const ChapterNumbering(enabled: true),
      );
      return b;
    }))!;
    await tester.pumpWidget(
      NoWhiteWriterApp(
        app: h.app,
        home: EditorPage(app: h.app, book: b),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final platform = h.app.platform as FakePlatformServices;
    expect(platform.lastTitle, '不白写作 — 窗口名 · 第1章 未命名章节');
    h.app.editor.title.text = '作者新名';
    await tester.pump();
    expect(platform.lastTitle, '不白写作 — 窗口名 · 第1章 作者新名');
    expect(h.app.editor.title.text, '作者新名');
    await finishWidget(tester, h);
  });
}
