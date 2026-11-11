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

import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../core/platform/platform_services.dart';
import '../core/storage/app_paths.dart';
import '../state/editor_controller.dart';
import '../state/export_controller.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../state/ui_operation_guards.dart';
import 'book_details_dialog.dart';
import 'context_menu.dart';
import 'editor_page.dart';
import 'export_notice.dart';
import 'format.dart';
import 'hover_actions.dart';
import 'menu_surface.dart';
import 'settings_menu.dart';
import 'theme/tokens.dart';
import 'window_title_bar.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.library,
    required this.editor,
    required this.exporter,
    required this.settings,
    required this.i18n,
    required this.platform,
    required this.paths,
    required this.uiGuards,
    this.autoOpenSettings = false,
    this.recoveredChapterCount = 0,
  });
  final LibraryController library;
  final EditorController editor;
  final ExportController exporter;
  final SettingsController settings;
  final I18nController i18n;
  final PlatformServices platform;
  final AppPaths paths;
  final UiOperationGuards uiGuards;

  /// Dev entry point: show the real settings menu on first frame.
  final bool autoOpenSettings;
  final int recoveredChapterCount;
  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final _focus = FocusNode(debugLabel: 'shelf');
  final _searchFocus = FocusNode(debugLabel: 'shelf-search');
  String _query = '';
  List<BookSummary> get _visibleBooks {
    final query = _query.trim().toLowerCase();
    return widget.library.books
        .where((book) => book.title.toLowerCase().contains(query))
        .toList();
  }

  final Map<String, GlobalKey> _cards = {};
  final _settingsKey = GlobalKey<SettingsMenuButtonState>();
  int _selected = 0;
  bool _opening = false, _creating = false, _managing = false;
  @override
  void initState() {
    super.initState();
    widget.library.addListener(_changed);
    widget.exporter.addListener(_changed);
    widget.library.ensureLoaded();
    if (widget.autoOpenSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_settingsKey.currentState?.open());
      });
    }
    if (widget.recoveredChapterCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notice('上次异常退出', '已恢复 ${widget.recoveredChapterCount} 个章节。');
        }
      });
    }
  }

  @override
  void dispose() {
    widget.library.removeListener(_changed);
    widget.exporter.removeListener(_changed);
    _focus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _selected = _selected.clamp(0, math.max(0, _visibleBooks.length - 1));
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
    if (_opening || _managing || widget.exporter.busy) return;
    _opening = true;
    try {
      final book = await widget.library.openBook(summary);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          pageBuilder: (context, _, _) => EditorPage(
            library: widget.library,
            editor: widget.editor,
            exporter: widget.exporter,
            settings: widget.settings,
            i18n: widget.i18n,
            platform: widget.platform,
            paths: widget.paths,
            uiGuards: widget.uiGuards,
            recoveredChapterCount: widget.recoveredChapterCount,
            book: book,
          ),
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
    if (_creating || _opening || _managing || widget.exporter.busy) return;
    _creating = true;
    try {
      final created = await showDialog<BookSummary>(
        context: context,
        builder: (context) => BookDetailsDialog<BookSummary>(
          creating: true,
          onSave: (title, notes) =>
              widget.library.createBook(title, notes: notes),
        ),
      );
      if (created != null && mounted) await _openBook(created);
    } finally {
      _creating = false;
    }
  }

  Future<void> _editBook(BookSummary summary) async {
    if (_managing || _opening || _creating || widget.exporter.busy) return;
    _managing = true;
    try {
      // 不触碰 editor 或上一本书的绑定，始终使用稳定 ID 对应的独立索引。
      final book = await widget.library.readBookDetails(summary);
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (context) => BookDetailsDialog<bool>(
          initialTitle: book.title,
          initialNotes: book.notes,
          onSave: (title, notes) async {
            await widget.library.updateBookDetails(book, title, notes);
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
    if (_managing || _opening || _creating || widget.exporter.busy) return;
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
      if (ok == true) await widget.library.deleteBook(summary);
    } catch (error) {
      if (mounted) _notice('删除失败，作品已保留', '$error');
    } finally {
      _managing = false;
    }
  }

  Future<void> _exportBook(String bookId) async {
    final exporter = widget.exporter;
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
          if (!await widget.platform.revealInFileManager(dir)) {
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
    if (_opening || _creating || _managing || widget.exporter.busy) return;
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
    final books = _visibleBooks;
    if (_searchFocus.hasFocus ||
        books.isEmpty ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
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

  Widget _newBookTile(BuildContext context) =>
      _NewBookTile(onPressed: widget.exporter.busy ? null : _createBook);

  Widget _shelfActions(LibraryController library) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 124,
        child: ComboBox<LibrarySort>(
          value: library.sort,
          items: const [
            ComboBoxItem(value: LibrarySort.recent, child: Text('最近编辑')),
            ComboBoxItem(value: LibrarySort.title, child: Text('按书名')),
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
        editor: widget.editor,
        exporter: widget.exporter,
        settings: widget.settings,
        i18n: widget.i18n,
        platform: widget.platform,
        paths: widget.paths,
        uiGuards: widget.uiGuards,
        secondary: true,
        enabled: !widget.exporter.busy,
        beforeOpen: () async {
          _focus.requestFocus();
          return true;
        },
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: widget.exporter.busy ? null : _createBook,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(FluentIcons.add), SizedBox(width: 6), Text('新建')],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final books = _visibleBooks;
    return Container(
      color: paperOrInk(context),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WindowTitleBar(
              platform: widget.platform,
              leading: const WindowBrand(),
              draggableLeading: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const maxSearch = 320.0;
                  final side = math.max(
                    0.0,
                    (constraints.maxWidth - maxSearch) / 2 - 16,
                  );
                  final searchWidth = math.min(
                    maxSearch,
                    math.max(120.0, constraints.maxWidth - 2 * side),
                  );
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: side,
                            child: Row(
                              children: [
                                Flexible(
                                  flex: 3,
                                  child: Text(
                                    '全部作品',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: bodyTextColor(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Flexible(
                                  flex: 2,
                                  child: Text(
                                    library.loading
                                        ? '正在打开书架…'
                                        : '共 ${library.books.length} 部作品 · 累计 ${library.books.fold<int>(0, (total, book) => total + book.wordCount)} 字',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: bodyTextColor(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _shelfActions(library),
                        ],
                      ),
                      SizedBox(
                        width: searchWidth,
                        child: TextBox(
                          key: const ValueKey('shelf-search'),
                          focusNode: _searchFocus,
                          placeholder: '搜索作品',
                          prefix: const Padding(
                            padding: EdgeInsets.only(left: 10),
                            child: Icon(FluentIcons.search, size: 14),
                          ),
                          onChanged: (value) => setState(() {
                            _query = value;
                            _selected = 0;
                          }),
                        ),
                      ),
                    ],
                  );
                },
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
                          key: const ValueKey('shelf-book-grid'),
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                          gridDelegate: _FixedCardGridDelegate(
                            crossAxisCount: columns,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 26,
                            mainAxisExtent: math.min(220, width) * 4 / 3,
                          ),
                          itemCount: books.length + 1,
                          itemBuilder: (context, index) {
                            if (index == books.length) {
                              return _newBookTile(context);
                            }
                            final summary = books[index];
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 10) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color;
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

class _NewBookTile extends StatefulWidget {
  const _NewBookTile({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  State<_NewBookTile> createState() => _NewBookTileState();
}

class _NewBookTileState extends State<_NewBookTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && (_hovered || _focused);
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = dark ? accentSoftColor(context) : accentColor(context);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Tooltip(
          message: '创建新作品',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: active
                  ? Color.lerp(paperOrInk(context), accent, dark ? .12 : .05)
                  : paperOrInk(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: CustomPaint(
              foregroundPainter: _DashedBorderPainter(
                active ? accent : hairlineColor(context),
              ),
              // Activate the focused tile before the shelf's ancestor Enter
              // shortcut can open the currently selected existing book.
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter):
                      ActivateIntent(),
                },
                child: Button(
                  key: const ValueKey('shelf-new-book-tile'),
                  style: borderlessRowStyle(
                    background: Colors.transparent,
                    foreground: active ? accent : mutedTextColor(context),
                  ),
                  onPressed: widget.onPressed,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.add, size: 28),
                      SizedBox(height: 12),
                      Text('新建作品'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    return HoverActionRegion(
      child: MouseRegion(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    key: ValueKey('book-cover-${widget.summary.id}'),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? Color.lerp(card, accentColor(context), 0.06)
                          : card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hairlineColor(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: light
                                ? (hover ? 0.10 : 0.04)
                                : (hover ? 0.35 : 0.18),
                          ),
                          blurRadius: hover ? 18 : 8,
                          offset: Offset(0, hover ? 8 : 3),
                        ),
                      ],
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.stats,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: widget.selected
                                                  ? (light
                                                        ? accentColor(context)
                                                        : Color.lerp(
                                                            accentColor(
                                                              context,
                                                            ),
                                                            fg,
                                                            .6,
                                                          ))
                                                  : mutedTextColor(context),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            relativeTime(
                                              widget.summary.updatedAt,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: mutedTextColor(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    HoverAction(
                                      child: SizedBox.square(
                                        dimension: 28,
                                        child: Builder(
                                          builder: (buttonContext) => Tooltip(
                                            message: '作品菜单',
                                            child: IconButton(
                                              key: ValueKey(
                                                'book-menu-${widget.summary.id}',
                                              ),
                                              icon: const Icon(
                                                FluentIcons.more,
                                                size: 14,
                                              ),
                                              onPressed: () {
                                                final box =
                                                    buttonContext
                                                            .findRenderObject()!
                                                        as RenderBox;
                                                widget.onMenu(
                                                  box.localToGlobal(
                                                    Offset(0, box.size.height),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
      ),
    );
  }
}
