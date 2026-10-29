import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/chapter_numbering.dart';
import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../state/workspace_controller.dart';
import 'chapter_volume_name_editor.dart';
import 'theme/tokens.dart';

class ChapterMoveItem {
  const ChapterMoveItem(this.bookId, this.volumeId, [this.chapterId]);
  final String bookId, volumeId;
  final String? chapterId;
}

/// Owns catalog move focus, keyboard/drop policy, drag lock and edge scrolling.
class ChapterDragInteraction {
  ChapterDragInteraction({
    required this.workspace,
    required this.nameEditor,
    required this.viewportContext,
  });
  final WorkspaceController workspace;
  final ChapterVolumeNameEditor nameEditor;
  final BuildContext Function() viewportContext;
  WorkspaceController get w => workspace;
  BookIndex get book => w.book;
  final focus = FocusNode(debugLabel: 'catalog-move');
  final scroll = ScrollController();
  Timer? _edgeTimer;
  Offset? _dragPosition;
  bool _disposed = false;

  Future<void> enterMove(bool volumes) async {
    if (await nameEditor.submit() && await w.enterMove(volumes) && !_disposed) {
      focus.requestFocus();
    }
  }

  KeyEventResult onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        w.moving &&
        !nameEditor.composing) {
      w.exitMove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void dispose() {
    _disposed = true;
    stopDrag();
    scroll.dispose();
    focus.dispose();
  }

  bool accepts(ChapterMoveItem item, bool chapters) =>
      item.bookId == book.id &&
      book.volumes.any(
        (v) =>
            v.id == item.volumeId &&
            (item.chapterId == null ||
                v.chapters.any((c) => c.id == item.chapterId)),
      ) &&
      !w.busy &&
      nameEditor.editingId == null &&
      (chapters
          ? w.moveMode == MoveMode.chapters && item.chapterId != null
          : w.moveMode == MoveMode.volumes && item.chapterId == null);

  Widget target(
    BuildContext context,
    Volume volume,
    int? index,
    Widget child,
  ) => DragTarget<ChapterMoveItem>(
    onWillAcceptWithDetails: (d) => accepts(d.data, true),
    onAcceptWithDetails: (d) {
      if (!accepts(d.data, true)) {
        stopDrag();
        return;
      }
      stopDrag();
      unawaited(
        w.dropChapter(
          d.data.chapterId!,
          volume.id,
          index ?? volume.chapters.length,
        ),
      );
    },
    builder: (context, candidates, rejected) => Container(
      key: index == null ? ValueKey('chapter-drop-volume-${volume.id}') : null,
      decoration: BoxDecoration(
        border: candidates.isEmpty
            ? null
            : Border.all(color: accentColor(context), width: 3),
      ),
      child: child,
    ),
  );

  Widget gap(BuildContext context, Volume? volume, int index) {
    final chapters = volume != null;
    return DragTarget<ChapterMoveItem>(
      onWillAcceptWithDetails: (d) => accepts(d.data, chapters),
      onAcceptWithDetails: (d) {
        if (!accepts(d.data, chapters)) {
          stopDrag();
          return;
        }
        stopDrag();
        if (chapters) {
          unawaited(w.dropChapter(d.data.chapterId!, volume.id, index));
        } else {
          unawaited(w.dropVolume(d.data.volumeId, index));
        }
      },
      builder: (context, candidates, rejected) => Container(
        key: ValueKey(
          chapters ? 'chapter-gap-${volume.id}-$index' : 'volume-gap-$index',
        ),
        height: 20,
        alignment: Alignment.center,
        child: Container(
          height: candidates.isEmpty ? 1 : 4,
          color: candidates.isEmpty
              ? hairlineColor(context)
              : accentColor(context),
        ),
      ),
    );
  }

  void startDrag() {
    if (!w.beginDrag()) return;
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (_disposed ||
          !w.dragging ||
          !scroll.hasClients ||
          _dragPosition == null) {
        return;
      }
      final box = viewportContext().findRenderObject();
      if (box is! RenderBox) return;
      final y = box.globalToLocal(_dragPosition!).dy;
      final delta = y < 60
          ? -18.0
          : y > box.size.height - 60
          ? 18.0
          : 0.0;
      if (delta != 0) {
        scroll.jumpTo(
          (scroll.offset + delta).clamp(0.0, scroll.position.maxScrollExtent),
        );
      }
    });
  }

  void stopDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _dragPosition = null;
    w.endDrag();
  }

  Widget grip(BuildContext context, Volume volume, ChapterMeta? chapter) {
    final key = chapter == null
        ? 'volume-grip-${volume.id}'
        : 'chapter-grip-${chapter.id}';
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || w.editingLocked) {
          return KeyEventResult.ignored;
        }
        final up = event.logicalKey == LogicalKeyboardKey.arrowUp,
            down = event.logicalKey == LogicalKeyboardKey.arrowDown;
        if (!up && !down) return KeyEventResult.ignored;
        final delta = up ? -1 : 1;
        if (chapter == null) {
          final i = book.volumes.indexOf(volume), to = i + delta;
          if (to >= 0 && to < book.volumes.length) {
            unawaited(w.dropVolume(volume.id, to > i ? to + 1 : to));
          }
        } else if (HardwareKeyboard.instance.isControlPressed) {
          final i = book.volumes.indexOf(volume) + delta;
          if (i >= 0 && i < book.volumes.length) {
            final target = book.volumes[i];
            unawaited(
              w.dropChapter(chapter.id, target.id, target.chapters.length),
            );
          }
        } else {
          final i = volume.chapters.indexOf(chapter), to = i + delta;
          if (to >= 0 && to < volume.chapters.length) {
            unawaited(
              w.dropChapter(chapter.id, volume.id, to > i ? to + 1 : to),
            );
          }
        }
        return KeyEventResult.handled;
      },
      child: Draggable<ChapterMoveItem>(
        data: ChapterMoveItem(book.id, volume.id, chapter?.id),
        maxSimultaneousDrags: w.editingLocked || w.editor.isComposing ? 0 : 1,
        feedback: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: paperOrInk(context),
            border: Border.all(color: hairlineColor(context)),
          ),
          child: Text(
            chapter == null
                ? displayVolumeTitle(
                    volume,
                    untitledLabel: t(context, 'common.untitledVolume'),
                  )
                : displayChapterTitle(
                    w.book,
                    volume,
                    chapter,
                    untitledLabel: t(context, 'common.untitledChapter'),
                  ),
            style: TextStyle(color: bodyTextColor(context), fontSize: 13),
          ),
        ),
        onDragStarted: startDrag,
        onDragUpdate: (d) => _dragPosition = d.globalPosition,
        onDragEnd: (_) => stopDrag(),
        child: Tooltip(
          message: t(context, 'sidebar.gripHint'),
          child: IconButton(
            key: ValueKey(key),
            icon: const Icon(FluentIcons.gripper_dots_vertical, size: 16),
            onPressed: w.editingLocked ? null : () {},
          ),
        ),
      ),
    );
  }
}
