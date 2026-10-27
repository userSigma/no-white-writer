import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart'
    show
        SliverConstraints,
        SliverGridLayout,
        SliverGridRegularTileLayout,
        axisDirectionIsReversed;
import 'package:flutter/services.dart';

import '../app_context.dart';
import '../core/models.dart';
import '../state/export_controller.dart';
import '../state/library_controller.dart';
import 'book_details_dialog.dart';
import 'context_menu.dart';
import 'editor_page.dart';
import 'export_notice.dart';
import 'format.dart';
import 'settings_menu.dart';
import 'theme/tokens.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.app,
    this.autoOpenSettings = false,
  });
  final AppContext app;

  /// Dev entry point: show the real settings menu on first frame.
  final bool autoOpenSettings;
  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final _focus = FocusNode(debugLabel: 'shelf');
  final Map<String, GlobalKey> _cards = {};
  final _settingsKey = GlobalKey<SettingsMenuButtonState>();
  int _selected = 0;
  bool _opening = false, _creating = false, _managing = false;
  @override
  void initState() {
    super.initState();
    widget.app.library.addListener(_changed);
    widget.app.exporter.addListener(_changed);
    widget.app.library.ensureLoaded();
    if (widget.autoOpenSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_settingsKey.currentState?.open());
      });
    }
    if (widget.app.recovered.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notice('上次异常退出', '已恢复 ${widget.app.recovered.length} 个章节。');
        }
      });
    }
  }

  @override
  void dispose() {
    widget.app.library.removeListener(_changed);
    widget.app.exporter.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _selected = _selected.clamp(
          0,
          math.max(0, widget.app.library.books.length - 1),
        );
      });
    }
  }

  void _notice(String title, String message) => displayInfoBar(
    context,
    builder: (context, close) => InfoBar(
      title: Text(title),
      content: Text(message),
      severity: InfoBarSeverity.warning,
      onClose: close,
    ),
  );
  Future<void> _openBook(BookSummary summary) async {
    if (_opening || _managing || widget.app.exporter.busy) return;
    _opening = true;
    try {
      final book = await widget.app.library.openBook(summary);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          pageBuilder: (context, _, _) =>
              EditorPage(app: widget.app, book: book),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (error) {
      if (mounted) _notice('打开作品失败', '$error');
    } finally {
      _opening = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _createBook() async {
    if (_creating || _opening || _managing || widget.app.exporter.busy) return;
    _creating = true;
    try {
      final created = await showDialog<BookSummary>(
        context: context,
        builder: (context) => BookDetailsDialog<BookSummary>(
          creating: true,
          onSave: (title, notes) =>
              widget.app.library.createBook(title, notes: notes),
        ),
      );
      if (created != null && mounted) await _openBook(created);
    } finally {
      _creating = false;
    }
  }

  Future<void> _editBook(BookSummary summary) async {
    if (_managing || _opening || _creating || widget.app.exporter.busy) return;
    _managing = true;
    try {
      // 不触碰 editor 或上一本书的绑定，始终使用稳定 ID 对应的独立索引。
      final book = await widget.app.library.readBookDetails(summary);
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (context) => BookDetailsDialog<bool>(
          initialTitle: book.title,
          initialNotes: book.notes,
          onSave: (title, notes) async {
            await widget.app.library.updateBookDetails(book, title, notes);
            return true;
          },
        ),
      );
    } catch (error) {
      if (mounted) _notice('编辑信息失败', '$error');
    } finally {
      _managing = false;
    }
  }

  Future<void> _deleteBook(BookSummary summary) async {
    if (_managing || _opening || _creating || widget.app.exporter.busy) return;
    _managing = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => ContentDialog(
          title: Text('删除《${summary.title}》？'),
          content: const Text('作品会移到数据目录的 trash 里，不会立刻从磁盘上消失。'),
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
      );
      if (ok == true) await widget.app.library.deleteBook(summary);
    } catch (error) {
      if (mounted) _notice('删除失败，作品已保留', '$error');
    } finally {
      _managing = false;
    }
  }

  Future<void> _exportBook(String bookId) async {
    final exporter = widget.app.exporter;
    if (exporter.busy) {
      _notice('正在导出', '请等当前导出完成后再试。');
      return;
    }
    try {
      final file = await exporter.export(ExportTarget.book(bookId));
      if (!mounted) return;
      if (file == null) {
        await showExportNotice(
          context,
          title: '导出本书',
          message: exporter.message ?? '暂无章节可导出',
        );
        return;
      }
      final dir = file.parent.path;
      await showExportNotice(
        context,
        title: '导出本书完成',
        message: '已导出为纯文本文件。',
        filePath: file.path,
        openDirectory: (_) async {
          if (!await widget.app.platform.revealInFileManager(dir)) {
            throw StateError('系统没有打开该文件夹');
          }
        },
      );
    } catch (error) {
      if (!mounted) return;
      await showExportNotice(
        context,
        title: '导出本书失败',
        message: '$error',
        onRetry: () {
          if (mounted) _exportBook(bookId);
        },
      );
    }
  }

  Future<void> _menu(BookSummary summary, Offset position) async {
    if (_opening || _creating || _managing || widget.app.exporter.busy) return;
    final bookId = summary.id;
    final action = await showContextMenu(context, position, const [
      MenuAction('open', '打开'),
      MenuAction('edit', '编辑信息'),
      MenuAction('export', '导出本书'),
      MenuAction('delete', '删除'),
    ]);
    if (!mounted) return;
    switch (action) {
      case 'open':
        await _openBook(summary);
      case 'edit':
        await _editBook(summary);
      case 'export':
        await _exportBook(bookId);
      case 'delete':
        await _deleteBook(summary);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final books = widget.app.library.books;
    if (books.isEmpty || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected =
            (_selected +
                    (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1))
                .clamp(0, books.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
        (event.logicalKey == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed)) {
      final summary = books[_selected];
      final box =
          _cards[summary.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) _menu(summary, box.localToGlobal(const Offset(20, 20)));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _openBook(books[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.app.library;
    return Container(
      color: paperOrInk(context),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
              child: Row(
                children: [
                  Text(
                    '不白写作',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: bodyTextColor(context),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    library.loading
                        ? '正在打开书架…'
                        : '${library.books.length} 本 · ${library.sort == LibrarySort.recent ? '最近编辑在前' : '按书名排序'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: bodyTextColor(context),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 124,
                    child: ComboBox<LibrarySort>(
                      value: library.sort,
                      items: const [
                        ComboBoxItem(
                          value: LibrarySort.recent,
                          child: Text('最近编辑'),
                        ),
                        ComboBoxItem(
                          value: LibrarySort.title,
                          child: Text('按书名'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) library.setSort(value);
                        _focus.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SettingsMenuButton(
                    key: _settingsKey,
                    app: widget.app,
                    enabled: !widget.app.exporter.busy,
                    beforeOpen: () async {
                      _focus.requestFocus();
                      return true;
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: widget.app.exporter.busy ? null : _createBook,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.add),
                        SizedBox(width: 6),
                        Text('新建'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              style: DividerThemeData(
                horizontalMargin: const EdgeInsetsDirectional.symmetric(
                  horizontal: 28,
                ),
                thickness: 1,
                decoration: BoxDecoration(color: hairlineColor(context)),
              ),
            ),
            Expanded(
              child: library.loading
                  ? const Center(child: ProgressRing())
                  : library.books.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.library, size: 46),
                          const SizedBox(height: 14),
                          const Text('书架还空着'),
                          const SizedBox(height: 6),
                          const Text('新建一本，开始写第一段。'),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: widget.app.exporter.busy
                                ? null
                                : _createBook,
                            child: const Text('新建作品'),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = math.max(
                          1,
                          math.min(1600, constraints.maxWidth) - 56,
                        );
                        final columns = ((width + 20) / 240).floor().clamp(
                          1,
                          8,
                        );
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                          gridDelegate: _FixedCardGridDelegate(
                            crossAxisCount: columns,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 26,
                            mainAxisExtent: 300,
                          ),
                          itemCount: library.books.length,
                          itemBuilder: (context, index) {
                            final summary = library.books[index];
                            return _BookCard(
                              key: _cards.putIfAbsent(
                                summary.id,
                                GlobalKey.new,
                              ),
                              summary: summary,
                              stats: library.statsLine(summary),
                              selected: index == _selected,
                              onTap: () => _openBook(summary),
                              onMenu: (position) {
                                setState(() => _selected = index);
                                _menu(summary, position);
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FixedCardGridDelegate extends SliverGridDelegate {
  const _FixedCardGridDelegate({
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.mainAxisExtent,
  });
  final int crossAxisCount;
  final double crossAxisSpacing, mainAxisSpacing, mainAxisExtent;
  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      SliverGridRegularTileLayout(
        crossAxisCount: crossAxisCount,
        mainAxisStride: mainAxisExtent + mainAxisSpacing,
        crossAxisStride:
            math.min(220, constraints.crossAxisExtent) + crossAxisSpacing,
        childMainAxisExtent: mainAxisExtent,
        childCrossAxisExtent: math.min(220, constraints.crossAxisExtent),
        reverseCrossAxis: axisDirectionIsReversed(
          constraints.crossAxisDirection,
        ),
      );
  @override
  bool shouldRelayout(covariant _FixedCardGridDelegate old) =>
      crossAxisCount != old.crossAxisCount ||
      crossAxisSpacing != old.crossAxisSpacing ||
      mainAxisSpacing != old.mainAxisSpacing ||
      mainAxisExtent != old.mainAxisExtent;
}

class _BookCard extends StatefulWidget {
  const _BookCard({
    super.key,
    required this.summary,
    required this.stats,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });
  final BookSummary summary;
  final String stats;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final fg = bodyTextColor(context);
    final light = FluentTheme.of(context).brightness == Brightness.light;
    final card = light ? const Color(0xFFFCFAF5) : const Color(0xFF1E1F22);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            boxShadow: [
              if (hover)
                BoxShadow(
                  color: const Color(0x00000000)
                      .withValues(alpha: light ? 0.10 : 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.selected
                          ? accentColor(context)
                          : hairlineColor(context),
                      width: widget.selected ? 1.6 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 15,
                        decoration: BoxDecoration(
                          gradient: spineGradient(widget.summary.coverSeed),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 16, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.summary.title,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '不白写作',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 4,
                                  color: mutedTextColor(context)
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 26,
                    child: Builder(
                      builder: (buttonContext) => Tooltip(
                        message: '作品菜单',
                        child: IconButton(
                          key: ValueKey('book-menu-${widget.summary.id}'),
                          icon: const Icon(FluentIcons.more, size: 14),
                          onPressed: () {
                            final box =
                                buttonContext.findRenderObject()! as RenderBox;
                            widget.onMenu(
                              box.localToGlobal(Offset(0, box.size.height)),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.stats,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
              ),
              const SizedBox(height: 2),
              Text(
                relativeTime(widget.summary.updatedAt),
                style: TextStyle(fontSize: 11, color: mutedTextColor(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
