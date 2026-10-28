import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/chapter_numbering.dart';
import '../core/models.dart';
import '../core/text/composing.dart';
import '../core/text/word_count.dart';
import '../state/export_controller.dart';
import '../state/workspace_controller.dart';
import 'context_menu.dart';
import 'export_notice.dart';
import 'menu_surface.dart';
import 'theme/tokens.dart';
import 'volume_settings_dialog.dart';

/// 页面隐藏/导航前与内联卷名握手；value 为 IME 组合锁，不复制或清除草稿。
class ChapterPaneDraft extends ValueNotifier<bool> {
  ChapterPaneDraft() : super(false);
  Future<bool> Function()? _submit;
  Future<bool> flush() => _submit?.call() ?? Future<bool>.value(true);
}

/// 宽屏侧栏与窄屏浮层共用；纯交互，磁盘变更仅经 workspace 排他入口。
class ChapterPane extends StatefulWidget {
  const ChapterPane({
    super.key,
    required this.workspace,
    required this.expanded,
    this.onCreated,
    this.onSelected,
    this.draft,
    this.exporter,
    this.revealPath,
  });
  final WorkspaceController workspace;
  final Set<String> expanded;
  final VoidCallback? onCreated;
  final VoidCallback? onSelected;
  final ChapterPaneDraft? draft;

  /// 稳定 ID 导出入口；为空时菜单不提供导出项。
  final ExportController? exporter;

  /// 打开导出文件所在目录（由页面注入平台能力）。
  final Future<bool> Function(String path)? revealPath;
  @override
  State<ChapterPane> createState() => _ChapterPaneState();
}

class _MoveItem {
  const _MoveItem(this.bookId, this.volumeId, [this.chapterId]);
  final String bookId, volumeId;
  final String? chapterId;
}

class _ChapterPaneState extends State<ChapterPane> {
  WorkspaceController get w => widget.workspace;
  BookIndex get book => w.book;
  final _moveFocus = FocusNode(debugLabel: 'catalog-move');
  final _scroll = ScrollController();
  Timer? _edgeTimer;
  Offset? _dragPosition;
  final _name = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'volume-inline-name');
  String? _editingId;
  String? _nameError;
  bool _savingName = false, _blurPending = false;
  bool get _composing => isComposingValue(_name.value);
  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_blur);
    _name.addListener(_compositionChanged);
    widget.draft?._submit = _submitName;
  }

  void _blur() {
    if (!_nameFocus.hasFocus && _editingId != null && !_savingName) {
      _blurPending = true;
      _submitName();
    }
  }

  void _compositionChanged() {
    widget.draft?.value = _composing;
    if (_blurPending && !_composing && !_savingName && _editingId != null) {
      scheduleMicrotask(_submitName);
    }
  }

  @override
  void dispose() {
    if (widget.draft?._submit == _submitName) widget.draft?._submit = null;
    _edgeTimer?.cancel();
    _scroll.dispose();
    _moveFocus.dispose();
    _nameFocus.removeListener(_blur);
    _name.removeListener(_compositionChanged);
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<bool>? _pendingNameSave;
  Future<bool> _submitName() {
    if (_pendingNameSave != null) return _pendingNameSave!;
    late final Future<bool> request;
    request = _commitName().whenComplete(() {
      if (identical(_pendingNameSave, request)) _pendingNameSave = null;
    });
    _pendingNameSave = request;
    return request;
  }

  Future<bool> _commitName() async {
    if (_editingId == null) return true;
    if (_savingName || _composing) return false;
    _blurPending = false;
    final volume = book.volumes.where((v) => v.id == _editingId).firstOrNull;
    if (volume == null) {
      setState(() => _editingId = null);
      return true;
    }
    final value = _name.text.trim();
    if (value == volume.title) {
      setState(() => _editingId = null);
      return true;
    }
    setState(() => _savingName = true);
    final ok = await w.change(
      () => w.library.renameVolume(book, volume, value),
    );
    if (!mounted) return ok;
    setState(() {
      _savingName = false;
      if (ok) {
        _editingId = null;
        _nameError = null;
      } else {
        _nameError = w.error ?? '未保存，请重试';
      }
    });
    if (!ok) _nameFocus.requestFocus();
    return ok;
  }

  void _cancelName() {
    if (_composing || _savingName) return;
    setState(() {
      _editingId = null;
      _blurPending = false;
      _nameError = null;
    });
    _nameFocus.unfocus();
  }

  Future<void> _rename(Volume volume) async {
    if (w.editingLocked || w.moving || w.editor.isComposing || _composing) {
      return;
    }
    if (_editingId != null && !await _submitName()) return;
    if (!mounted) return;
    setState(() {
      _editingId = volume.id;
      _nameError = null;
      _name.value = TextEditingValue(
        text: volume.title,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: volume.title.length,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  Future<void> _toggle(Volume volume) async {
    if (_editingId != null || w.editingLocked) return;
    final open = !widget.expanded.contains(volume.id);
    setState(() {
      open ? widget.expanded.add(volume.id) : widget.expanded.remove(volume.id);
    });
    await w.library.setVolumeExpanded(book, volume.id, open);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _moveFocus,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          w.moving &&
          !_composing) {
        w.exitMove();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AnimatedBuilder(
      animation: Listenable.merge([w, w.editor]),
      builder: (context, _) => ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: bodyTextColor(context),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${book.volumes.length} 卷 · ${book.allChapters.length} 章 · ${formatWordCount(book.totalWordCount)}',
              style: TextStyle(fontSize: 10, color: mutedTextColor(context)),
            ),
          ),
          const SizedBox(height: 10),
          Button(
            onPressed: w.editingLocked || w.moving || _savingName
                ? null
                : () => _appendVolume(context),
            child: const Text('新建卷'),
          ),
          const SizedBox(height: 12),
          if (w.error != null || _nameError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoBar(
                title: const Text('操作未完成'),
                content: Text(_nameError ?? w.error!),
                severity: InfoBarSeverity.error,
              ),
            ),
          if (book.volumes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('还没有卷。先新建一卷，再开始写作。'),
            ),
          if (w.moving) ...[
            Text(
              w.moveMode == MoveMode.volumes
                  ? '卷移动：拖动握柄到卷间落点'
                  : '章节移动：拖动握柄到章间或卷标题',
            ),
            Button(
              onPressed: w.editingLocked ? null : w.exitMove,
              child: const Text('完成移动'),
            ),
          ],
          if (w.moveMode == MoveMode.volumes) _gap(null, 0),
          for (int i = 0; i < book.volumes.length; i++) ...[
            _volume(context, book.volumes[i]),
            if (w.moveMode == MoveMode.volumes) _gap(null, i + 1),
          ],
        ],
      ),
    ),
  );
  Widget _volume(BuildContext context, Volume volume) {
    final open = widget.expanded.contains(volume.id);
    return Container(
      key: ValueKey('volume-${volume.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onSecondaryTapDown: (d) =>
                _volumeMenu(context, volume, d.globalPosition),
            onLongPressStart: (d) =>
                _volumeMenu(context, volume, d.globalPosition),
            child: _target(
              volume,
              null,
              ColoredBox(
                color: FluentTheme.of(context)
                    .resources
                    .subtleFillColorSecondary,
                child: Row(
                  children: [
                    Tooltip(
                      message: open ? '折叠卷' : '展开卷',
                      child: IconButton(
                        key: ValueKey('toggle-volume-${volume.id}'),
                        icon: Icon(
                          open
                              ? FluentIcons.chevron_down
                              : FluentIcons.chevron_right,
                          size: 12,
                        ),
                        onPressed: w.editingLocked || _editingId != null
                            ? null
                            : () => _toggle(volume),
                      ),
                    ),
                    Expanded(
                      child: _editingId == volume.id
                          ? Focus(
                              onKeyEvent: (_, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.escape &&
                                    !_composing) {
                                  _cancelName();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextBox(
                                key: ValueKey('volume-name-${volume.id}'),
                                controller: _name,
                                focusNode: _nameFocus,
                                maxLines: 1,
                                enabled: !_savingName,
                                // Keep the platform's composing range intact until
                                // the IME itself commits it; submit only afterwards.
                                onEditingComplete: () {},
                                onSubmitted: (_) {
                                  if (!_composing) _submitName();
                                },
                              ),
                            )
                          : Text(
                              displayVolumeTitle(volume),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: volume.title.trim().isEmpty
                                    ? mutedTextColor(context)
                                    : null,
                              ),
                            ),
                    ),
                    if (w.moveMode == MoveMode.volumes)
                      _grip(volume, null)
                    else
                      _menuButton(
                        'volume-menu-${volume.id}',
                        (p) => _volumeMenu(context, volume, p),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            if (w.moveMode == MoveMode.chapters) _gap(volume, 0),
            for (int i = 0; i < volume.chapters.length; i++) ...[
              _chapter(context, volume, volume.chapters[i]),
              if (w.moveMode == MoveMode.chapters) _gap(volume, i + 1),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.center,
                child: Tooltip(
                  message: '新建章节',
                  child: Semantics(
                    label: '新建章节',
                    button: true,
                    child: IconButton(
                      key: ValueKey('add-chapter-${volume.id}'),
                      icon: const Icon(FluentIcons.add),
                      onPressed:
                          w.editingLocked || w.moving || _editingId != null
                          ? null
                          : () => _appendChapter(volume),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _menuButton(String key, ValueChanged<Offset> action) => Builder(
    builder: (context) => IconButton(
      key: ValueKey(key),
      icon: const Icon(FluentIcons.more, size: 14),
      onPressed:
          w.editingLocked || w.moving || w.editor.isComposing || _composing
          ? null
          : () {
              final box = context.findRenderObject()! as RenderBox;
              action(box.localToGlobal(Offset(0, box.size.height)));
            },
    ),
  );
  Widget _chapter(BuildContext context, Volume volume, ChapterMeta chapter) {
    final active = w.chapter?.id == chapter.id, fg = bodyTextColor(context);
    return GestureDetector(
      onSecondaryTapDown: (d) =>
          _chapterMenu(context, volume, chapter, d.globalPosition),
      onLongPressStart: (d) =>
          _chapterMenu(context, volume, chapter, d.globalPosition),
      child: Container(
        key: ValueKey('chapter-row-${chapter.id}'),
        color: active ? accentColor(context).withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            Expanded(
              child: Button(
                key: ValueKey('select-chapter-${chapter.id}'),
                style:
                    borderlessRowStyle(
                      background: Colors.transparent,
                      foreground: active ? accentColor(context) : fg,
                    ).copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.fromLTRB(18, 10, 10, 10),
                      ),
                    ),
                onPressed: w.editingLocked || _editingId != null
                    ? null
                    : () async {
                        await w.select(volume, chapter);
                      },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      displayChapterTitle(
                        volume,
                        chapter,
                        rawTitle: active ? w.editor.title.text : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color:
                            !volume.numbering.enabled &&
                                (active ? w.editor.title.text : chapter.title)
                                    .trim()
                                    .isEmpty
                            ? mutedTextColor(context)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatWordCount(
                        active ? w.editor.wordCount : chapter.wordCount,
                      ),
                      style: TextStyle(
                        fontSize: 10,
                        color: mutedTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (w.moveMode == MoveMode.chapters)
              _grip(volume, chapter)
            else
              _menuButton(
                'chapter-menu-${chapter.id}',
                (p) => _chapterMenu(context, volume, chapter, p),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterMove(bool volumes) async {
    if (await _submitName() && await w.enterMove(volumes) && mounted) {
      _moveFocus.requestFocus();
    }
  }

  bool _accepts(_MoveItem item, bool chapters) =>
      item.bookId == book.id &&
      !w.busy &&
      _editingId == null &&
      (chapters
          ? w.moveMode == MoveMode.chapters && item.chapterId != null
          : w.moveMode == MoveMode.volumes && item.chapterId == null);

  Widget _target(Volume volume, int? index, Widget child) =>
      DragTarget<_MoveItem>(
        onWillAcceptWithDetails: (d) => _accepts(d.data, true),
        onAcceptWithDetails: (d) {
          _stopDrag();
          unawaited(
            w.dropChapter(
              d.data.chapterId!,
              volume.id,
              index ?? volume.chapters.length,
            ),
          );
        },
        builder: (context, candidates, rejected) => Container(
          key: index == null
              ? ValueKey('chapter-drop-volume-${volume.id}')
              : null,
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border.all(color: accentColor(context), width: 3),
          ),
          child: child,
        ),
      );

  Widget _gap(Volume? volume, int index) {
    final chapters = volume != null;
    return DragTarget<_MoveItem>(
      onWillAcceptWithDetails: (d) => _accepts(d.data, chapters),
      onAcceptWithDetails: (d) {
        _stopDrag();
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

  void _startDrag() {
    if (!w.beginDrag()) return;
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted ||
          !w.dragging ||
          !_scroll.hasClients ||
          _dragPosition == null) {
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox) return;
      final y = box.globalToLocal(_dragPosition!).dy;
      final delta = y < 60
          ? -18.0
          : y > box.size.height - 60
          ? 18.0
          : 0.0;
      if (delta != 0) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _stopDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _dragPosition = null;
    w.endDrag();
  }

  Widget _grip(Volume volume, ChapterMeta? chapter) {
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
      child: Draggable<_MoveItem>(
        data: _MoveItem(book.id, volume.id, chapter?.id),
        maxSimultaneousDrags: w.editingLocked || w.editor.isComposing ? 0 : 1,
        feedback: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: paperOrInk(context),
            border: Border.all(color: hairlineColor(context)),
          ),
          child: Text(
            chapter == null
                ? displayVolumeTitle(volume)
                : displayChapterTitle(volume, chapter),
            style: TextStyle(color: bodyTextColor(context), fontSize: 13),
          ),
        ),
        onDragStarted: _startDrag,
        onDragUpdate: (d) => _dragPosition = d.globalPosition,
        onDragEnd: (_) => _stopDrag(),
        child: Tooltip(
          message: '拖动握柄移动；方向键排序，Ctrl+方向键跨卷',
          child: IconButton(
            key: ValueKey(key),
            icon: const Icon(FluentIcons.gripper_dots_vertical, size: 16),
            onPressed: w.editingLocked ? null : () {},
          ),
        ),
      ),
    );
  }

  Future<void> _appendVolume(BuildContext context) async {
    if (!await _submitName() || !context.mounted) return;
    await _ask(
      context,
      '新建卷',
      '卷名（留空为未命名卷）',
      onSave: (name) async {
        final ok = await w.change(
          () => w.library.appendVolume(book, title: name),
        );
        if (!ok) throw StateError(w.error ?? '新卷未保存，请重试');
      },
    );
  }

  Future<void> _appendChapter(Volume volume) async {
    if (!await _submitName()) return;
    ChapterMeta? added;
    final ok = await w.change(() async {
      added = await w.library.appendChapter(book, volume);
    }, selectAfter: () => added?.id);
    if (ok && mounted) widget.onCreated?.call();
  }

  Future<void> _volumeMenu(
    BuildContext context,
    Volume volume,
    Offset position,
  ) async {
    if (w.editingLocked || w.moving || w.editor.isComposing || _composing) {
      return;
    }
    final exporter = widget.exporter;
    final volumeId = volume.id;
    final action = await showContextMenu(context, position, [
      const MenuAction('rename', '重命名'),
      const MenuAction('add', '在本卷新建章'),
      const MenuAction('settings', '卷设置'),
      const MenuAction('move', '移动'),
      if (exporter != null) const MenuAction('export', '导出本卷'),
      const MenuAction('delete', '删除卷'),
    ]);
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await _rename(volume);
      case 'move':
        await _enterMove(true);
      case 'add':
        await _appendChapter(volume);
      case 'export':
        if (exporter == null) return;
        if (!await _submitName() || !mounted) return;
        await _export(() => ExportTarget.volume(w.book.id, volumeId), '导出本卷');
      case 'settings':
        if (!await _submitName() || !context.mounted) return;
        await showDialog<bool>(
          context: context,
          builder: (_) => VolumeSettingsDialog(workspace: w, volume: volume),
        );
      case 'delete':
        if (!await _submitName() || !context.mounted) return;
        if (await _confirm(
          context,
          '删除「${volume.title}」及其 ${volume.chapters.length} 章？',
        )) {
          await w.change(() => w.library.deleteVolume(book, volume));
        }
    }
  }

  Future<void> _chapterMenu(
    BuildContext context,
    Volume volume,
    ChapterMeta chapter,
    Offset position,
  ) async {
    if (w.editingLocked || w.moving || w.editor.isComposing || _composing) {
      return;
    }
    final exporter = widget.exporter;
    final chapterId = chapter.id;
    final action = await showContextMenu(context, position, [
      const MenuAction('rename', '重命名章'),
      const MenuAction('move', '移动'),
      if (exporter != null) const MenuAction('export', '导出本章'),
      const MenuAction('delete', '删除章'),
    ]);
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await _ask(
          context,
          '重命名章',
          '章名',
          initial: w.chapter?.id == chapter.id
              ? w.editor.title.text
              : chapter.title,
          onSave: (name) async {
            final ok = await w.change(() async {
              if (w.chapter?.id == chapter.id) {
                w.editor.title.text = name;
                if (!await w.editor.flush()) {
                  throw StateError(w.editor.errorMessage ?? '标题未保存');
                }
              } else {
                await w.library.renameChapter(book, chapter, name);
              }
            });
            if (!ok) throw StateError(w.error ?? '章名未保存，请重试');
          },
        );
      case 'move':
        await _enterMove(false);
      case 'export':
        if (exporter == null) return;
        if (!await _submitName() || !mounted) return;
        await _export(
          () => ExportTarget.chapter(w.book.id, volume.id, chapterId),
          '导出本章',
        );
      case 'delete':
        if (await _confirm(context, '删除「${chapter.title}」？')) {
          await w.change(() => w.library.deleteChapter(book, volume, chapter));
        }
    }
  }

  /// 以菜单打开时捕获的稳定 ID 导出；失败保留重试入口，不吃掉异常。
  Future<void> _export(ExportTarget Function() target, String label) async {
    final exporter = widget.exporter;
    if (exporter == null) return;
    if (exporter.busy) {
      await _showNotice(label, '正在导出，请稍候。');
      return;
    }
    try {
      final file = await exporter.export(target());
      if (!mounted) return;
      if (file == null) {
        await _showNotice(label, exporter.message ?? '暂无章节可导出');
        return;
      }
      final dir = file.parent.path;
      final reveal = widget.revealPath;
      await showExportNotice(
        context,
        title: '$label完成',
        message: '已导出为纯文本文件。',
        filePath: file.path,
        openDirectory: reveal == null
            ? null
            : (_) async {
                if (!await reveal(dir)) {
                  throw StateError('系统没有打开该文件夹');
                }
              },
      );
    } catch (error) {
      if (!mounted) return;
      await showExportNotice(
        context,
        title: '$label失败',
        message: '$error',
        onRetry: () {
          if (mounted) _export(target, label);
        },
      );
    }
  }

  Future<void> _showNotice(String title, String message) async {
    if (!mounted) return;
    await _confirmMessage(context, title, message);
  }
}

Future<String?> _ask(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  required Future<void> Function(String) onSave,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _NameDialog(title: title, hint: hint, initial: initial, onSave: onSave),
);
Future<void> _confirmMessage(
  BuildContext context,
  String title,
  String message,
) async => showDialog<void>(
  context: context,
  builder: (context) => ContentDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      FilledButton(
        key: const ValueKey('export-notice-close'),
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(title),
        content: const Text('会先保存当前草稿，正文移入 trash，不会直接永久删除。'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.onSave,
  });
  final String title, hint, initial;
  final Future<void> Function(String) onSave;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;
  bool get composing => isComposingValue(controller.value);
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (_saving || composing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(controller.text);
      if (mounted) Navigator.pop(context, controller.text);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    // FluentDialogRoute's default DismissAction calls pop directly and bypasses
    // PopScope. Consume Escape here while IME or the save is still in progress.
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          if (!_saving && !composing) Navigator.pop(context);
          return null;
        },
      ),
    },
    child: PopScope(
      canPop: !_saving && !composing,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 500),
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextBox(
              key: const ValueKey('name-input'),
              controller: controller,
              autofocus: true,
              enabled: !_saving,
              maxLines: 1,
              placeholder: widget.hint,
              onEditingComplete: () {},
              onSubmitted: (_) => submit(),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
        actions: [
          Button(
            onPressed: _saving || composing
                ? null
                : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving || composing ? null : submit,
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
