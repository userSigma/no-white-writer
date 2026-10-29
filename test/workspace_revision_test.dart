import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/state/workspace_controller.dart';

import 'support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('默认卷折叠且仅设置持久化，选章新建不自动展开', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('偏好');
    final book = await h.app.library.openBook(summary);
    final v = book.volumes.first;
    expect(v.title, '未命名卷');
    expect(h.app.library.expandedVolumesOf(book), isEmpty);
    final workspace = WorkspaceController(
      book: book,
      library: h.app.library,
      editor: h.app.editor,
    );
    addTearDown(workspace.dispose);
    await workspace.initialize();
    expect(h.app.library.expandedVolumesOf(book), isEmpty);
    h.app.settings.setSidebarCollapsed(true);
    await h.app.library.setVolumeExpanded(book, v.id, true);
    await h.app.settings.flush();
    final saved = await h.app.settingsStore.load();
    expect(saved.toJson()['sidebarCollapsed'], isTrue);
    expect(saved.expandedVolumes[book.id], [v.id]);
    await h.app.library.setVolumeExpanded(book, v.id, false);
    await workspace.change(() async {
      await h.app.library.structure.appendChapter(book, v);
    });
    expect(h.app.library.expandedVolumesOf(book), isEmpty);
    expect(
      (await h.app.settingsStore.load()).expandedVolumes[book.id],
      isEmpty,
    );
  });

  test('移动模式先保存、互斥，拖动/写盘锁定，重复操作拒绝', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('移动');
    final book = await h.app.library.openBook(summary);
    final source = book.volumes.first;
    final chapter = source.chapters.first;
    final target = await h.app.library.structure.appendVolume(book);
    final w = WorkspaceController(
      book: book,
      library: h.app.library,
      editor: h.app.editor,
    );
    addTearDown(w.dispose);
    await w.initialize();
    h.app.editor.text.text = '进入前草稿';
    expect(await w.enterMove(false), isTrue);
    expect(
      await h.app.chapterStore.readText(book.id, source.id, chapter.id),
      '进入前草稿',
    );
    expect(w.beginDrag(), isTrue);
    expect(w.editingLocked, isTrue);
    bool conflict = false;
    expect(
      await w.change(() async {
        conflict = true;
      }),
      isFalse,
    );
    expect(conflict, isFalse);
    expect(await w.select(source, chapter), isFalse, reason: '拖动期间不能切章');
    expect(await w.close(), isFalse, reason: '拖动期间不能解除绑定');
    expect(await w.dropChapter(chapter.id, target.id, 0), isTrue);
    expect(w.chapter?.id, chapter.id);
    expect(w.volume?.id, target.id);
    expect(h.app.library.expandedVolumesOf(book), isEmpty);
    w.exitMove();
    expect(w.editingLocked, isFalse);
  });
}
