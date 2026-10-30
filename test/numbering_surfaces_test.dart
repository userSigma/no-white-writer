import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/app.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/state/export_controller.dart';

import 'support/page_harness.dart';
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
    await h.app.editor.runStructure(b, () async {
      await h.app.library.structure.setVolumeNumberingMode(
        b,
        v,
        VolumeNumberingMode.independent,
      );
      await h.app.library.structure.setNumbering(
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
      );
    });
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
    // 切回跟随全局且全局关闭：导出文件名随之失去编号前缀。
    await h.app.editor.runStructure(
      b,
      () => h.app.library.structure.setVolumeNumberingMode(
        b,
        v,
        VolumeNumberingMode.followGlobal,
      ),
    );
    final off = (await h.app.exporter.export(
      ExportTarget.chapter(b.id, v.id, c.id),
    ))!;
    expect(off.uri.pathSegments.last, '第 2 章 原章名.txt');
    // 跟随全局 + 全局开启：文件名改用全局规则（跨卷连续序号）。
    await h.app.editor.runStructure(
      b,
      () => h.app.library.structure.setGlobalNumbering(
        b,
        const ChapterNumbering(enabled: true, prefix: '', suffix: '', start: 1),
      ),
    );
    final on = (await h.app.exporter.export(
      ExportTarget.chapter(b.id, v.id, c.id),
    ))!;
    expect(on.uri.pathSegments.last, '1 第 2 章 原章名.txt');
  });
  testWidgets('窗口标题随规则及原始标题草稿更新且不写入前缀', (tester) async {
    final h = await widgetHarness(tester);
    final b = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('窗口名');
      final b = await h.app.library.openBook(s);
      await h.app.library.structure.setVolumeNumberingMode(
        b,
        b.volumes.first,
        VolumeNumberingMode.independent,
      );
      return b;
    }))!;
    await tester.pumpWidget(
      NoWhiteWriterApp(
        app: h.app,
        home: editorPage(app: h.app, book: b),
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
  testWidgets('窗口标题在全局编号下跨卷连续', (tester) async {
    final h = await widgetHarness(tester);
    final b = (await tester.runAsync(() async {
      final s = await h.app.library.createBook('全局窗口');
      final b = await h.app.library.openBook(s);
      final v2 = await h.app.library.structure.appendVolume(b);
      await h.app.library.structure.appendChapter(b, v2);
      await h.app.library.structure.setGlobalNumbering(
        b,
        const ChapterNumbering(enabled: true),
      );
      return b;
    }))!;
    final secondVolume = b.volumes[1];
    await tester.pumpWidget(
      NoWhiteWriterApp(
        app: h.app,
        home: editorPage(
          app: h.app,
          book: b,
          volume: secondVolume,
          chapter: secondVolume.chapters.first,
        ),
      ),
    );
    await finishIo(tester, until: () => editorReady(tester));
    final platform = h.app.platform as FakePlatformServices;
    // 新书默认卷：第 1 章；新加的第二卷第 1 章占用全局第 2 号。
    expect(platform.lastTitle, '不白写作 — 全局窗口 · 第2章 未命名章节');
    await finishWidget(tester, h);
  });
}
