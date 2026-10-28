import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart'
    show InputDecoration, Material, MaterialType, TextField;

import '../app_context.dart';
import '../core/chapter_numbering.dart';
import '../core/models.dart';
import '../core/text/word_count.dart';
import '../state/editor_controller.dart';
import '../state/workspace_controller.dart';
import 'chapter_pane.dart';
import 'format.dart';
import 'settings_menu.dart';
import 'shelf_page.dart';
import 'sidebar_transition.dart';
import 'theme/tokens.dart';

/// 作品的唯一写作工作区：卷章管理、标题和正文不再分属两个页面。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.app,
    required this.book,
    this.volume,
    this.chapter,
  });
  final AppContext app;
  final BookIndex book;
  final Volume? volume;
  final ChapterMeta? chapter;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'chapter-body');
  final FocusNode _titleFocus = FocusNode(debugLabel: 'chapter-title');
  final _paneDraft = ChapterPaneDraft();
  late final Set<String> _expanded;
  late final WorkspaceController workspace;
  late final Object _uiGuard;
  bool _allowPop = false;
  bool _closing = false;
  bool _disposing = false;
  bool _paneOpen = false;
  bool _paneClosing = false;
  bool _pendingTitleFocus = false;
  EditorController get editor => widget.app.editor;

  @override
  void initState() {
    super.initState();
    _expanded = widget.app.library.expandedVolumesOf(widget.book);
    workspace = WorkspaceController(
      book: widget.book,
      library: widget.app.library,
      editor: editor,
      exportBusy: () => widget.app.exporter.busy,
    );
    _uiGuard = widget.app.registerUiGuard(() async {
      if (workspace.editingLocked || editor.isComposing) return false;
      return _paneDraft.flush();
    });
    widget.app.exporter.addListener(_onChanged);
    _paneDraft.addListener(_onChanged);
    workspace.addListener(_onChanged);
    editor.addListener(_onChanged);
    widget.app.settings.addListener(_onChanged);
    _bodyFocus.addListener(_bodyFocusChanged);
    _titleFocus.addListener(_titleFocusChanged);
    workspace.initialize(preferredChapter: widget.chapter);
  }

  void _bodyFocusChanged() {
    if (!_bodyFocus.hasFocus) _flushOnBlur();
  }

  void _titleFocusChanged() {
    if (!_titleFocus.hasFocus) _flushOnBlur();
  }

  void _flushOnBlur() {
    if (_disposing ||
        workspace.busy ||
        editor.loading ||
        editor.isComposing ||
        workspace.chapter == null) {
      return;
    }
    editor.flush();
  }

  void _onChanged() {
    _expanded
      ..clear()
      ..addAll(widget.app.library.expandedVolumesOf(widget.book));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposing = true;
    widget.app.removeUiGuard(_uiGuard);
    widget.app.exporter.removeListener(_onChanged);
    _paneDraft.removeListener(_onChanged);
    _paneDraft.dispose();
    workspace.removeListener(_onChanged);
    editor.removeListener(_onChanged);
    widget.app.settings.removeListener(_onChanged);
    _bodyFocus.removeListener(_bodyFocusChanged);
    _titleFocus.removeListener(_titleFocusChanged);
    _bodyFocus.dispose();
    _titleFocus.dispose();
    workspace.dispose();
    // 不在 dispose 强写：当前绑定可能刚被删除流程解除。
    super.dispose();
  }

  Future<void> _back() async {
    if (_closing || workspace.busy || editor.isComposing || _paneDraft.value) {
      return;
    }
    _closing = true;
    if (!await _paneDraft.flush()) {
      _closing = false;
      return;
    }
    final bool saved = await workspace.close();
    if (!mounted) return;
    if (!saved) {
      _closing = false;
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        navigator.pushReplacement<void, void>(
          PageRouteBuilder<void>(
            pageBuilder: (BuildContext context, _, _) =>
                ShelfPage(app: widget.app),
          ),
        );
      }
    });
  }

  void _created() {
    _pendingTitleFocus = true;
    if (_paneOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paneOpen || workspace.editingLocked) return;
      _pendingTitleFocus = false;
      _titleFocus.requestFocus();
      editor.title.selection = TextSelection(
        baseOffset: 0,
        extentOffset: editor.title.text.length,
      );
    });
  }

  /// 折叠、打开/关闭浮层、Escape、返回与设置共用同一道守卫：
  /// 组词、内联草稿和工作区锁都不允许换载体。
  bool get _carrierBlocked =>
      _paneClosing ||
      _paneDraft.value ||
      editor.isComposing ||
      workspace.editingLocked;

  Future<void> _toggleSidebar() async {
    if (_carrierBlocked) return;
    _paneClosing = true;
    try {
      final collapsed = widget.app.settings.settings.sidebarCollapsed;
      if (!collapsed && !await _paneDraft.flush()) return;
      if (mounted) widget.app.settings.setSidebarCollapsed(!collapsed);
    } finally {
      _paneClosing = false;
    }
  }

  /// 窄屏浮层的打开/关闭与折叠共用同一草稿守卫；失败保持可编辑载体。
  Future<void> _openPane() async {
    if (_paneOpen || _carrierBlocked) return;
    setState(() => _paneOpen = true);
  }

  Future<void> _closePane() async {
    if (!_paneOpen || _carrierBlocked) return;
    _paneClosing = true;
    try {
      if (!await _paneDraft.flush()) return;
      if (!mounted) return;
      setState(() => _paneOpen = false);
      if (_pendingTitleFocus) _created();
    } finally {
      _paneClosing = false;
    }
  }

  Future<void> _escape() async {
    if (_paneOpen) {
      await _closePane();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (bool didPop, Object? result) {
      if (!didPop) {
        if (_paneOpen) {
          _closePane();
        } else {
          _back();
        }
      }
    },
    child: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            editor.flush(),
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 1000;
          final bool collapsed = widget.app.settings.settings.sidebarCollapsed;
          return Container(
            color: paperOrInk(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _topBar(context, wide),
                Container(height: 1, color: hairlineColor(context)),
                Expanded(child: _body(context, constraints, wide, collapsed)),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _footer(BuildContext context) {
    final bool blocked = workspace.editingLocked || _paneDraft.value;
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: <Widget>[
            Tooltip(
              message: '返回作品列表',
              child: IconButton(
                key: const ValueKey('back-to-shelf'),
                icon: const Icon(FluentIcons.back),
                onPressed: blocked ? null : _back,
              ),
            ),
            const Spacer(),
            SettingsMenuButton(
              app: widget.app,
              enabled: !blocked,
              beforeOpen: () async => _paneDraft.flush(),
            ),
          ],
        ),
      ),
    );
  }

  /// 宽屏侧栏与窄屏浮层是同一个目录载体：只改位置／尺寸／可见性，
  /// 不复制 ChapterPane，也不重建滚动与内联输入。动画与正文左缘共用同一值。
  Widget _body(
    BuildContext context,
    BoxConstraints constraints,
    bool wide,
    bool collapsed,
  ) {
    final bool expanded = wide ? !collapsed : _paneOpen;
    final double fullWidth = constraints.maxWidth >= 1280 ? 280 : 240;
    final double overlayWidth = math.min(440, constraints.maxWidth - 32);
    final double overlayHeight = math.min(420, constraints.maxHeight - 32);
    return SidebarValueBuilder(
      expanded: expanded,
      builder: (BuildContext context, double value) {
        final bool hidden = value <= 0.0001;
        final bool overlay = !wide;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              left: overlay ? 0 : fullWidth * value + (hidden ? 0 : 1),
              top: 0,
              right: 0,
              bottom: 0,
              child: _writingArea(context),
            ),
            if (overlay && !hidden)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('chapter-pane-barrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _closePane,
                  child: ColoredBox(
                    color: const Color(0x33000000)
                        .withValues(alpha: 0.2 * value),
                  ),
                ),
              ),
            if (!overlay && !hidden)
              Positioned(
                left: fullWidth * value,
                top: 0,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: hairlineColor(context)),
              ),
            Positioned(
              left: overlay ? (constraints.maxWidth - overlayWidth) / 2 : 0,
              top: overlay ? (constraints.maxHeight - overlayHeight) / 2 : 0,
              width: overlay ? overlayWidth : fullWidth * value,
              height: overlay ? overlayHeight : null,
              bottom: overlay ? null : 0,
              child: SizedBox(
                key: const ValueKey('sidebar-frame'),
                child: Offstage(
                  offstage: hidden,
                  child: TickerMode(
                    enabled: !hidden,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: ExcludeFocus(
                        excluding: !expanded,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: overlay ? overlayWidth : fullWidth,
                            maxWidth: overlay ? overlayWidth : fullWidth,
                            child: Container(
                              key: const ValueKey('chapter-pane-frame'),
                              decoration: BoxDecoration(
                                color: paperOrInk(context),
                                border: overlay
                                    ? Border.all(color: hairlineColor(context))
                                    : null,
                                boxShadow: overlay && value > 0
                                    ? const <BoxShadow>[
                                        BoxShadow(
                                          color: Color(0x22000000),
                                          blurRadius: 18,
                                          offset: Offset(0, 6),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ChapterPane(
                                      key: const ValueKey('chapter-pane-host'),
                                      workspace: workspace,
                                      expanded: _expanded,
                                      onCreated: _created,
                                      draft: _paneDraft,
                                      exporter: widget.app.exporter,
                                      revealPath: widget
                                          .app
                                          .platform
                                          .revealInFileManager,
                                    ),
                                  ),
                                  Container(
                                    height: 1,
                                    color: hairlineColor(context),
                                  ),
                                  _footer(context),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _topBar(BuildContext context, bool wide) {
    final Color dot = switch (editor.state) {
      SaveState.clean => const Color(0xFF5C8A57),
      SaveState.saving => accentSoftColor(context),
      SaveState.dirty => const Color(0xFFC08A2E),
      SaveState.failed => const Color(0xFFC0392B),
      SaveState.blocked => mutedTextColor(context),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      child: Row(
        children: <Widget>[
          if (wide)
            Tooltip(
              message: widget.app.settings.settings.sidebarCollapsed
                  ? '展开目录侧栏'
                  : '收起目录侧栏',
              child: IconButton(
                key: const ValueKey('toggle-sidebar'),
                icon: const Icon(FluentIcons.side_panel),
                onPressed: workspace.editingLocked || _paneDraft.value
                    ? null
                    : _toggleSidebar,
              ),
            ),
          if (!wide)
            IconButton(
              key: const ValueKey('open-chapter-pane'),
              icon: const Icon(FluentIcons.list),
              onPressed: workspace.editingLocked ? null : _openPane,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: bodyTextColor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            workspace.busy
                ? '正在处理…'
                : saveStateLabel(editor.state.name, editor.lastSavedAt),
            style: TextStyle(fontSize: 11, color: mutedTextColor(context)),
          ),
          const SizedBox(width: 16),
          Text(
            formatWordCount(workspace.chapter == null ? 0 : editor.wordCount),
            style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
          ),
        ],
      ),
    );
  }

  Widget _writingArea(BuildContext context) {
    final bool readOnly =
        workspace.editingLocked ||
        editor.loading ||
        editor.state == SaveState.blocked;
    final String? failure = workspace.error ?? editor.errorMessage;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (failure != null)
            InfoBar(
              title: const Text('请留意'),
              content: Text(failure),
              severity: InfoBarSeverity.error,
              action: Button(
                onPressed: () => editor.flush(),
                child: const Text('重试保存'),
              ),
            ),
          if (editor.noticeMessage != null)
            InfoBar(
              title: Text(editor.noticeMessage!),
              severity: InfoBarSeverity.warning,
              onClose: editor.clearError,
            ),
          Expanded(
            child: workspace.chapter == null
                ? Center(
                    child: workspace.busy
                        ? const ProgressRing()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '还没有章节',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: bodyTextColor(context),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('在目录中新建卷和章节，然后开始写作。'),
                              const SizedBox(height: 16),
                              Button(
                                onPressed: _openPane,
                                child: const Text('打开目录管理'),
                              ),
                            ],
                          ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(36, 22, 36, 26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (chapterNumberLabel(
                              workspace.book,
                              workspace.volume!,
                              workspace.chapter!.id,
                            )
                                case final label?)
                              Text(
                                label,
                                key: const ValueKey('chapter-number'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: bodyTextColor(context),
                                ),
                              ),
                            Text(
                              '章节标题',
                              style: TextStyle(
                                fontSize: 11,
                                color: mutedTextColor(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              key: const ValueKey('chapter-title'),
                              controller: editor.title,
                              focusNode: _titleFocus,
                              onTapOutside: editor.isComposing ? (_) {} : null,
                              readOnly: readOnly,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: bodyTextColor(context),
                              ),
                              cursorColor: accentColor(context),
                              decoration: InputDecoration.collapsed(
                                hintText: '输入章节标题…',
                                hintStyle: TextStyle(
                                  color: mutedTextColor(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(height: 1, color: hairlineColor(context)),
                            const SizedBox(height: 22),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('chapter-body'),
                                controller: editor.text,
                                focusNode: _bodyFocus,
                                onTapOutside: editor.isComposing
                                    ? (_) {}
                                    : null,
                                readOnly: readOnly,
                                autofocus: true,
                                maxLines: null,
                                expands: true,
                                scrollPadding: const EdgeInsets.all(24),
                                style: TextStyle(
                                  fontFamily: 'LXGWWenKaiGB',
                                  fontSize:
                                      widget.app.settings.settings.fontSize,
                                  height:
                                      widget.app.settings.settings.lineHeight,
                                  color: bodyTextColor(context),
                                  letterSpacing: 0.2,
                                ),
                                cursorColor: accentColor(context),
                                cursorWidth: 1.4,
                                decoration: InputDecoration.collapsed(
                                  hintText: '从这里开始写…',
                                  hintStyle: TextStyle(
                                    color: bodyTextColor(context),
                                    fontFamily: 'LXGWWenKaiGB',
                                    fontSize:
                                        widget.app.settings.settings.fontSize,
                                    height:
                                        widget.app.settings.settings.lineHeight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
