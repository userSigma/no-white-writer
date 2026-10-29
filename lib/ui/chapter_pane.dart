import 'package:fluent_ui/fluent_ui.dart';

import '../core/chapter_numbering.dart';
import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../core/text/word_count.dart';
import '../state/export_controller.dart';
import '../state/workspace_controller.dart';
import 'menu_surface.dart';
import 'chapter_catalog_menus.dart';
import 'chapter_drag_interaction.dart';
import 'chapter_volume_name_editor.dart';

export 'chapter_volume_name_editor.dart' show ChapterPaneDraft;
import 'theme/tokens.dart';

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

class _ChapterPaneState extends State<ChapterPane> {
  WorkspaceController get w => widget.workspace;
  BookIndex get book => w.book;
  late ChapterVolumeNameEditor _nameEditor;
  late ChapterDragInteraction _drag;
  String? get _editingId => _nameEditor.editingId;
  String? get _nameError => _nameEditor.error;
  bool get _savingName => _nameEditor.saving;
  bool get _composing => _nameEditor.composing;
  ChapterCatalogMenus get _menus => ChapterCatalogMenus(
    context: context,
    workspace: w,
    nameEditor: _nameEditor,
    drag: _drag,
    exporter: widget.exporter,
    revealPath: widget.revealPath,
    onCreated: widget.onCreated,
  );

  void _createInteractions() {
    _nameEditor = ChapterVolumeNameEditor(
      workspace: w,
      draft: widget.draft,
      saveFailedLabel: () => t(context, 'volume.save.failed'),
    );
    _nameEditor.addListener(_nameChanged);
    _drag = ChapterDragInteraction(
      workspace: w,
      nameEditor: _nameEditor,
      viewportContext: () => context,
    );
  }

  void _nameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _createInteractions();
  }

  @override
  void didUpdateWidget(covariant ChapterPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workspace, widget.workspace)) {
      _drag.dispose();
      _nameEditor.dispose();
      _createInteractions();
    } else {
      _nameEditor.bindDraft(widget.draft);
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    _nameEditor.dispose();
    super.dispose();
  }

  Future<void> _toggle(Volume volume) async {
    if (_editingId != null || w.editingLocked) return;
    final open = !widget.expanded.contains(volume.id);
    setState(() {
      open ? widget.expanded.add(volume.id) : widget.expanded.remove(volume.id);
    });
    await w.setVolumeExpanded(volume.id, open);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _drag.focus,
    onKeyEvent: _drag.onKeyEvent,
    child: AnimatedBuilder(
      animation: Listenable.merge([w, w.editor]),
      builder: (context, _) => ListView(
        controller: _drag.scroll,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
        children: [
          GestureDetector(
            onSecondaryTapDown: (d) =>
                _menus.bookMenu(context, d.globalPosition),
            onLongPressStart: (d) => _menus.bookMenu(context, d.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
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
                  Builder(
                    builder: (buttonContext) => Tooltip(
                      message: t(context, 'sidebar.bookMenu'),
                      child: IconButton(
                        key: const ValueKey('book-menu-button'),
                        icon: const Icon(FluentIcons.more, size: 14),
                        onPressed: w.editingLocked || w.moving || _savingName
                            ? null
                            : () {
                                final box =
                                    buttonContext.findRenderObject()!
                                        as RenderBox;
                                _menus.bookMenu(
                                  context,
                                  box.localToGlobal(Offset(0, box.size.height)),
                                );
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              t(context, 'sidebar.stats', {
                'volumes': '${book.volumes.length}',
                'chapters': '${book.allChapters.length}',
                'words': formatWordCount(book.totalWordCount),
              }),
              style: TextStyle(fontSize: 10, color: mutedTextColor(context)),
            ),
          ),
          const SizedBox(height: 14),
          if (w.error != null || _nameError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoBar(
                title: Text(t(context, 'sidebar.errorTitle')),
                content: Text(_nameError ?? w.error!),
                severity: InfoBarSeverity.error,
              ),
            ),
          if (book.volumes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t(context, 'sidebar.empty')),
            ),
          if (w.moving) ...[
            Text(
              w.moveMode == MoveMode.volumes
                  ? t(context, 'sidebar.moveVolumeHint')
                  : t(context, 'sidebar.moveChapterHint'),
            ),
            Button(
              onPressed: w.editingLocked ? null : w.exitMove,
              child: Text(t(context, 'sidebar.finishMove')),
            ),
          ],
          if (w.moveMode == MoveMode.volumes) _drag.gap(context, null, 0),
          for (int i = 0; i < book.volumes.length; i++) ...[
            _volume(context, book.volumes[i]),
            if (w.moveMode == MoveMode.volumes) _drag.gap(context, null, i + 1),
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
                _menus.volumeMenu(context, volume, d.globalPosition),
            onLongPressStart: (d) =>
                _menus.volumeMenu(context, volume, d.globalPosition),
            child: _drag.target(
              context,
              volume,
              null,
              ColoredBox(
                color: FluentTheme.of(context)
                    .resources
                    .subtleFillColorSecondary,
                child: Row(
                  children: [
                    Tooltip(
                      message: open
                          ? t(context, 'sidebar.collapseVolume')
                          : t(context, 'sidebar.expandVolume'),
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
                          ? ChapterVolumeNameField(
                              editor: _nameEditor,
                              volumeId: volume.id,
                            )
                          : Text(
                              displayVolumeTitle(
                                volume,
                                untitledLabel: t(
                                  context,
                                  'common.untitledVolume',
                                ),
                              ),
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
                      _drag.grip(context, volume, null)
                    else
                      _menuButton(
                        'volume-menu-${volume.id}',
                        (p) => _menus.volumeMenu(context, volume, p),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            if (w.moveMode == MoveMode.chapters) _drag.gap(context, volume, 0),
            for (int i = 0; i < volume.chapters.length; i++) ...[
              _chapter(context, volume, volume.chapters[i]),
              if (w.moveMode == MoveMode.chapters)
                _drag.gap(context, volume, i + 1),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.center,
                child: Tooltip(
                  message: t(context, 'sidebar.newChapter'),
                  child: Semantics(
                    label: t(context, 'sidebar.newChapter'),
                    button: true,
                    child: IconButton(
                      key: ValueKey('add-chapter-${volume.id}'),
                      icon: const Icon(FluentIcons.add),
                      onPressed:
                          w.editingLocked || w.moving || _editingId != null
                          ? null
                          : () => _menus.appendChapter(volume),
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
          _menus.chapterMenu(context, volume, chapter, d.globalPosition),
      onLongPressStart: (d) =>
          _menus.chapterMenu(context, volume, chapter, d.globalPosition),
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
                        w.book,
                        volume,
                        chapter,
                        rawTitle: active ? w.editor.title.text : null,
                        untitledLabel: t(context, 'common.untitledChapter'),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color:
                            effectiveChapterNumbering(w.book, volume) == null &&
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
              _drag.grip(context, volume, chapter)
            else
              _menuButton(
                'chapter-menu-${chapter.id}',
                (p) => _menus.chapterMenu(context, volume, chapter, p),
              ),
          ],
        ),
      ),
    );
  }
}
