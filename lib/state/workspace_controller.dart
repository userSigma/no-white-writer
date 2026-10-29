import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'editor_controller.dart';
import 'library_controller.dart';

enum MoveMode { none, volumes, chapters }

/// 写作工作区的导航与目录操作边界；所有 UI 目录写入都经过这里。
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.book,
    required this.library,
    required this.editor,
    this.exportBusy,
  });
  final BookIndex book;
  final LibraryController library;
  final EditorController editor;
  final bool Function()? exportBusy;
  bool get _exporting => library.exporting || (exportBusy?.call() ?? false);
  bool busy = false;
  bool dragging = false;
  MoveMode moveMode = MoveMode.none;
  bool get editingLocked =>
      busy || dragging || editor.structuralBusy || _exporting;
  bool get moving => moveMode != MoveMode.none;
  String? error;
  bool _disposed = false;
  ChapterMeta? get chapter =>
      editor.book?.id == book.id ? editor.chapter : null;
  Volume? get volume => editor.book?.id == book.id ? editor.volume : null;

  Future<bool> initialize({ChapterMeta? preferredChapter}) =>
      _exclusive(() async {
        final String? preferred =
            preferredChapter?.id ?? library.lastChapterId(book.id);
        final ChapterMeta? target = preferred == null
            ? null
            : book.chapterById(preferred);
        final ChapterMeta? first = book.allChapters.firstOrNull;
        if (target != null || first != null) return _select(target ?? first!);
        if (!await editor.close()) return _saveFailed();
        await library.rememberChapter(book.id, null);
        return true;
      });

  Future<bool> select(Volume volume, ChapterMeta chapter) =>
      _exclusive(() async {
        if (!volume.chapters.any((ChapterMeta c) => c.id == chapter.id) ||
            !book.volumes.any((Volume v) => v.id == volume.id)) {
          error = '目标章节已不存在，请从目录中重新选择。';
          return false;
        }
        return _select(chapter);
      });

  Future<bool> _select(ChapterMeta target) async {
    final Volume? targetVolume = book.volumeOfChapter(target.id);
    if (targetVolume == null) return false;
    if (chapter?.id != target.id) {
      if (!await editor.open(
        inBook: book,
        inVolume: targetVolume,
        inChapter: target,
      )) {
        return _saveFailed();
      }
    }
    await library.rememberChapter(book.id, target.id);
    return true;
  }

  // Catalog commands keep mutation and editor-navigation policy out of widgets.
  Future<bool> appendVolume(String title) =>
      change(() => library.structure.appendVolume(book, title: title));

  Future<bool> appendChapter(Volume volume) {
    ChapterMeta? added;
    return change(() async {
      added = await library.structure.appendChapter(book, volume);
    }, selectAfter: () => added?.id);
  }

  Future<bool> renameVolume(Volume volume, String title) =>
      change(() => library.structure.renameVolume(book, volume, title));

  Future<bool> renameChapter(ChapterMeta target, String title) =>
      change(() async {
        if (chapter?.id == target.id) {
          editor.title.text = title;
          if (!await editor.flush()) {
            throw StateError(editor.errorMessage ?? '章节标题尚未保存');
          }
        } else {
          await library.structure.renameChapter(book, target, title);
        }
      });

  Future<bool> deleteVolume(Volume volume) =>
      change(() => library.structure.deleteVolume(book, volume));

  Future<bool> deleteChapter(Volume volume, ChapterMeta chapter) =>
      change(() => library.structure.deleteChapter(book, volume, chapter));

  Future<bool> setVolumeNumberingMode(
    Volume volume,
    VolumeNumberingMode mode,
  ) => change(
    () => library.structure.setVolumeNumberingMode(book, volume, mode),
  );

  Future<void> setVolumeExpanded(String volumeId, bool expanded) =>
      library.setVolumeExpanded(book, volumeId, expanded);

  /// 操作之前先落盘；删除当前目标必须先解除绑定，杜绝防抖/失焦复活文件。
  Future<bool> change(
    Future<void> Function() mutation, {
    String? Function()? selectAfter,
  }) {
    if (dragging || moving) return Future<bool>.value(false);
    return _exclusive(() => _performChange(mutation, selectAfter: selectAfter));
  }

  Future<bool> _performChange(
    Future<void> Function() mutation, {
    String? Function()? selectAfter,
  }) async {
    final List<ChapterMeta> before = book.allChapters.toList();
    final String? previousId = chapter?.id;
    final int previousIndex = before.indexWhere(
      (ChapterMeta c) => c.id == previousId,
    );
    if (!await editor.runStructure(book, mutation)) return _saveFailed();
    final String? explicitId = selectAfter?.call();
    final ChapterMeta? explicit = explicitId == null
        ? null
        : book.chapterById(explicitId);
    if (explicit != null) return _select(explicit);
    if (chapter != null) return true;
    // 优先原目录中的后章，然后前章；不依赖删除后已改变的数组下标。
    final Iterable<ChapterMeta> candidates = previousIndex >= 0
        ? <ChapterMeta>[
            ...before.skip(previousIndex + 1),
            ...before.take(previousIndex).toList().reversed,
          ]
        : before;
    for (final ChapterMeta candidate in candidates) {
      final ChapterMeta? surviving = book.chapterById(candidate.id);
      if (surviving != null) return _select(surviving);
    }
    final ChapterMeta? first = book.allChapters.firstOrNull;
    if (first != null) return _select(first);
    await library.rememberChapter(book.id, null);
    return true;
  }

  Future<bool> enterMove(bool volumes) => _exclusive(() async {
    if (!await editor.runStructure(book, () async {})) return _saveFailed();
    moveMode = volumes ? MoveMode.volumes : MoveMode.chapters;
    return true;
  });

  bool beginDrag() {
    if (editingLocked || !moving || editor.isComposing) return false;
    dragging = true;
    notifyListeners();
    return true;
  }

  void endDrag() {
    if (!dragging) return;
    dragging = false;
    if (!_disposed) notifyListeners();
  }

  void exitMove() {
    if (busy || dragging) return;
    moveMode = MoveMode.none;
    notifyListeners();
  }

  Future<bool> dropChapter(String chapterId, String targetId, int index) {
    if (moveMode != MoveMode.chapters) return Future<bool>.value(false);
    dragging = false;
    return _exclusive(
      () => _performChange(
        () =>
            library.structure.relocateChapter(book, chapterId, targetId, index),
      ),
    );
  }

  Future<bool> dropVolume(String volumeId, int index) {
    if (moveMode != MoveMode.volumes) return Future<bool>.value(false);
    dragging = false;
    return _exclusive(
      () => _performChange(
        () => library.structure.reorderVolume(book, volumeId, index),
      ),
    );
  }

  Future<bool> close() => _exclusive(() async {
    if (!await editor.close()) return _saveFailed();
    return true;
  });

  bool _saveFailed() {
    error = editor.noticeMessage ?? editor.errorMessage ?? '草稿尚未成功保存，已取消本次操作。';
    return false;
  }

  Future<bool> _exclusive(Future<bool> Function() action) async {
    if (editingLocked || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      return await action();
    } catch (failure) {
      error = '操作失败，未能完成：$failure';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
