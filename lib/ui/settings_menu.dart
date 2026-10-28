import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../app_context.dart';
import '../core/models.dart';
import '../state/settings_controller.dart';
import 'menu_surface.dart';
import 'theme/live_theme_scope.dart';
import 'theme/tokens.dart';

/// A reusable anchor: the shelf opens downward and the sidebar footer upward.
class SettingsMenuButton extends StatefulWidget {
  const SettingsMenuButton({
    super.key,
    required this.app,
    this.enabled = true,
    this.upward = false,
    this.beforeOpen,
  });
  final AppContext app;
  final bool enabled;
  final bool upward;
  final Future<bool> Function()? beforeOpen;
  @override
  State<SettingsMenuButton> createState() => SettingsMenuButtonState();
}

class SettingsMenuButtonState extends State<SettingsMenuButton> {
  final _flyout = FlyoutController();
  bool _opening = false;

  /// Opens the shared settings menu; the dev entry point uses this so the
  /// acceptance shortcut shows the real menu instead of a separate page.
  Future<void> open() => _open();

  Future<void> _open() async {
    if (_opening ||
        !widget.enabled ||
        widget.app.exporter.busy ||
        widget.app.editor.isComposing) {
      return;
    }
    _opening = true;
    try {
      if (widget.beforeOpen != null && !await widget.beforeOpen!()) return;
      if (!await widget.app.flushUiGuards() ||
          !await widget.app.editor.flush() ||
          !mounted) {
        return;
      }
      final key = GlobalKey<_SettingsMenuState>();
      final barrier = TapGestureRecognizer()
        ..onTap = () {
          unawaited(
            key.currentState?.requestClose() ?? Future<bool>.value(false),
          );
        };
      try {
        await _flyout.showFlyout<void>(
          dismissWithEsc: false,
          barrierRecognizer: barrier,
          placementMode: widget.upward
              ? FlyoutPlacementMode.topRight
              : FlyoutPlacementMode.bottomRight,
          builder: (_) => _SettingsMenu(key: key, app: widget.app),
        );
      } finally {
        barrier.dispose();
      }
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FlyoutTarget(
    controller: _flyout,
    child: Tooltip(
      message: '设置',
      child: IconButton(
        key: const ValueKey('settings-button'),
        icon: const Icon(FluentIcons.settings),
        onPressed:
            widget.enabled &&
                !widget.app.exporter.busy &&
                !widget.app.editor.isComposing
            ? _open
            : null,
      ),
    ),
  );
}

class _SettingsMenu extends StatefulWidget {
  const _SettingsMenu({super.key, required this.app});
  final AppContext app;
  @override
  State<_SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<_SettingsMenu> {
  late final TextEditingController _path;
  late final Object _guard;
  BuildContext? _subMenu;
  bool _editingPath = false;
  bool _working = false;
  bool _closing = false;
  bool _confirming = false;
  String? _message;
  bool _messageError = false;
  AppContext get app => widget.app;
  bool get _composing =>
      _path.value.composing.isValid && !_path.value.composing.isCollapsed;
  bool get _dirty =>
      _path.text.trim() != (app.settings.settings.exportDirectory ?? '');

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(
      text: app.settings.settings.exportDirectory ?? '',
    )..addListener(_refresh);
    app.settings.addListener(_refresh);
    _guard = app.registerUiGuard(_prepareClose);
    HardwareKeyboard.instance.addHandler(_key);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _key(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape || _confirming) {
      return false;
    }
    if (event is! KeyDownEvent) return true;
    final child = _subMenu;
    if (child != null && child.mounted) {
      final flyout = Flyout.of(child);
      final key = flyout.widget.menuKey;
      if (key != null && MenuInfoProvider.of(child).contains(key)) {
        flyout.close();
        _subMenu = null;
        return true;
      }
    }
    unawaited(requestClose());
    return true;
  }

  void _notice(String text, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = text;
        _messageError = error;
      });
    }
  }

  Future<bool> _prepareClose() async {
    if (_working || _composing || _confirming) return false;
    if (_dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('导出目录尚未保存'),
          content: const Text('丢弃这次目录修改，还是继续编辑？'),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('丢弃修改'),
            ),
          ],
        ),
      );
      _confirming = false;
      if (!mounted || discard != true) return false;
      _path.text = app.settings.settings.exportDirectory ?? '';
    }
    try {
      await app.settings.flush();
      return true;
    } catch (error) {
      _notice('设置保存失败：$error', error: true);
      return false;
    }
  }

  Future<bool> requestClose() async {
    if (_closing || !mounted) return false;
    _closing = true;
    try {
      if (!await _prepareClose() || !mounted) return false;
      Navigator.of(context).pop();
      return true;
    } finally {
      _closing = false;
    }
  }

  Future<void> _savePath({bool useDefault = false}) async {
    if (_working || _composing) return;
    setState(() {
      _working = true;
      _message = null;
    });
    final previous = app.settings.settings.exportDirectory;
    if (useDefault) _path.text = '';
    final String text = _path.text.trim();
    app.settings.setExportDirectory(text.isEmpty ? null : text);
    try {
      await app.settings.flush();
      _notice('导出目录已保存');
    } catch (error) {
      // Restore only the confirmed preference; keep the failed input for retry.
      app.settings.settings.exportDirectory = previous;
      _notice('设置保存失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openDirectory(String path) async {
    if (_working || _composing) return;
    setState(() => _working = true);
    try {
      if (!await app.platform.revealInFileManager(path)) {
        throw StateError('系统未能打开目录');
      }
      _notice('目录已打开');
    } catch (error) {
      _notice('打开目录失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createCustomTheme() async {
    if (app.settings.settings.customThemes.length >=
        SettingsController.customThemeLimit) {
      _notice(
        '自定义主题已达 ${SettingsController.customThemeLimit} 套上限，请先删除一套。',
        error: true,
      );
      return;
    }
    _confirming = true;
    final _CustomThemeDraft? draft = await showDialog<_CustomThemeDraft>(
      context: context,
      builder: (context) => const _CustomThemeDialog(),
    );
    _confirming = false;
    if (draft == null || !mounted) return;
    final CustomTheme? created = app.settings.addCustomTheme(
      background: draft.background,
      accent: draft.accent,
      name: draft.name,
    );
    if (created == null) {
      _notice('创建失败：自定义主题已达上限。', error: true);
      return;
    }
    app.settings.setThemeMode('custom:${created.id}');
    _notice('已创建并应用「${created.name}」');
  }

  Future<void> _renameCustomTheme(CustomTheme theme) async {
    _confirming = true;
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameThemeDialog(initial: theme.name),
    );
    _confirming = false;
    if (name == null || !mounted) return;
    if (!app.settings.renameCustomTheme(theme.id, name)) {
      _notice('重命名失败：名称不能为空。', error: true);
    }
  }

  Future<void> _deleteCustomTheme(CustomTheme theme) async {
    _confirming = true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text('删除「${theme.name}」？'),
        content: const Text('删除后不可恢复；若正在使用该主题，将回退为跟随系统。'),
        actions: <Widget>[
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (ok != true || !mounted) return;
    app.settings.deleteCustomTheme(theme.id);
  }

  MenuFlyoutSubItem _sub(
    String label,
    List<MenuFlyoutItemBase> Function() items,
  ) => MenuFlyoutSubItem(
    text: Text(label),
    items: (context) {
      _subMenu = context;
      return items();
    },
  );

  MenuFlyoutItem _action(
    String label,
    VoidCallback? action, {
    Widget? leading,
  }) => MenuFlyoutItem(
    text: Text(label),
    leading: leading,
    closeAfterClick: false,
    onPressed: action,
  );

  MenuFlyoutItemBuilder _content(Widget child) => MenuFlyoutItemBuilder(
    builder: (_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    ),
  );

  List<MenuFlyoutItemBase> _items(double width) {
    final settings = app.settings.settings;
    final result = <MenuFlyoutItemBase>[
      _content(
        Text(
          _editingPath ? '导出目录' : '设置',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: accentColor(context),
          ),
        ),
      ),
    ];
    if (_editingPath) {
      result.addAll([
        _content(
          SizedBox(
            width: width - 32,
            child: TextBox(
              key: const ValueKey('settings-export-path'),
              controller: _path,
              enabled: !_working,
              placeholder: '留空使用默认文档目录',
              onEditingComplete: () {},
              onSubmitted: (_) {
                if (!_composing) unawaited(_savePath());
              },
            ),
          ),
        ),
        _content(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: _working || _composing ? null : _savePath,
                child: const Text('保存'),
              ),
              Button(
                onPressed: _working || _composing
                    ? null
                    : () => _savePath(useDefault: true),
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ),
        _action(
          '打开导出目录',
          _working || _composing
              ? null
              : () {
                  if (_dirty) {
                    _notice('请先保存目录修改', error: true);
                    return;
                  }
                  unawaited(
                    _openDirectory(
                      app.paths.exportRoot(settings.exportDirectory),
                    ),
                  );
                },
        ),
        _action(
          '返回设置',
          _working || _composing
              ? null
              : () async {
                  if (await _prepareClose() && mounted) {
                    setState(() => _editingPath = false);
                  }
                },
        ),
      ]);
    } else {
      result.addAll([
        _sub('主题', () {
          final bool full =
              settings.customThemes.length >=
              SettingsController.customThemeLimit;
          return <MenuFlyoutItemBase>[
            for (final item in const [
              ('system', '跟随系统'),
              ('light', '浅色（纯白）'),
              ('dark', '深色（纯黑）'),
            ])
              RadioMenuFlyoutItem<String>(
                text: Text(item.$2),
                value: item.$1,
                groupValue: settings.themeMode,
                closeAfterClick: false,
                onChanged: app.settings.setThemeMode,
              ),
            const MenuFlyoutSeparator(),
            for (final CustomTheme theme in settings.customThemes)
              RadioMenuFlyoutItem<String>(
                text: Text(theme.name),
                value: 'custom:${theme.id}',
                groupValue: settings.themeMode,
                closeAfterClick: false,
                onChanged: app.settings.setThemeMode,
              ),
            MenuFlyoutItem(
              text: Text(
                full
                    ? '新建自定义主题（已达 ${SettingsController.customThemeLimit} 套上限）'
                    : '新建自定义主题…',
              ),
              closeAfterClick: false,
              onPressed: full ? null : () => unawaited(_createCustomTheme()),
            ),
            if (settings.customThemes.isNotEmpty)
              _sub(
                '管理自定义主题',
                () => <MenuFlyoutItemBase>[
                  for (final CustomTheme theme in settings.customThemes) ...<
                    MenuFlyoutItemBase
                  >[
                    _action(
                      '重命名「${theme.name}」…',
                      () => unawaited(_renameCustomTheme(theme)),
                    ),
                    _action(
                      '删除「${theme.name}」',
                      () => unawaited(_deleteCustomTheme(theme)),
                    ),
                  ],
                ],
              ),
          ];
        }),
        _sub(
          '字号',
          () => [
            for (var value = 14; value <= 28; value++)
              RadioMenuFlyoutItem<double>(
                text: Text('$value'),
                value: value.toDouble(),
                groupValue: settings.fontSize,
                closeAfterClick: false,
                onChanged: app.settings.setFontSize,
              ),
          ],
        ),
        _sub(
          '行距',
          () => [
            for (var step = 0; step <= 10; step++)
              RadioMenuFlyoutItem<double>(
                text: Text((1.4 + step / 10).toStringAsFixed(1)),
                value: (14 + step) / 10,
                groupValue: settings.lineHeight,
                closeAfterClick: false,
                onChanged: app.settings.setLineHeight,
              ),
          ],
        ),
        ToggleMenuFlyoutItem(
          text: const Text('自动首行缩进'),
          value: settings.autoIndent,
          closeAfterClick: false,
          onChanged: app.settings.setAutoIndent,
        ),
        ToggleMenuFlyoutItem(
          text: const Text('段间空行'),
          value: settings.blankLineBetween,
          closeAfterClick: false,
          onChanged: app.settings.setBlankLineBetween,
        ),
        _action('导出目录…', () => setState(() => _editingPath = true)),
        _action(
          '打开数据目录',
          _working ? null : () => _openDirectory(app.paths.dataRootPath),
        ),
        _action(
          '打开日志目录',
          _working ? null : () => _openDirectory(app.paths.logsDir),
        ),
        _sub(
          '关于',
          () => [
            _content(const Text('不白写作 0.4.0')),
            _content(const Text('本地纯文本写作，作品与设置保存在本机。')),
          ],
        ),
      ]);
    }
    final error = app.settings.saveError;
    if (error != null) {
      result.add(
        _content(
          Text('设置保存失败：$error', key: const ValueKey('settings-save-error')),
        ),
      );
      result.add(
        _action(
          '重试保存',
          _working || _composing
              ? null
              : () async {
                  if (_editingPath && _dirty) {
                    await _savePath();
                    return;
                  }
                  try {
                    await app.settings.flush();
                    _notice('设置已保存');
                  } catch (error) {
                    _notice('设置保存失败：$error', error: true);
                  }
                },
        ),
      );
    }
    if (_message != null) {
      result.add(
        _content(
          InfoBar(
            key: const ValueKey('settings-notice'),
            title: Text(_message!),
            severity: _messageError
                ? InfoBarSeverity.error
                : InfoBarSeverity.success,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.max(80.0, math.min(340.0, size.width - 32));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(requestClose());
      },
      child: DisableAcrylic(
        // 不给 MenuFlyout 传显式 color：fluent_ui 的
        // MenuFlyoutSubItem.show() 会把父级的 color 值捕获进闭包且不再
        // 刷新，显式色会让子菜单在主题切换后冻结成反色空壳（文字也因
        // 实时主题反色而不可见）。留空后根/子菜单表面都从 FluentTheme
        // 实时读 menuColor（= 主题背景，见 buildFluentTheme），随主题
        // 即时换色；DisableAcrylic 关掉 0.65 透明度的亚克力混合，表面
        // 实心等价于原 paperOrInk 视觉。
        child: MenuFlyout(
          key: const ValueKey('settings-menu'),
          shape: borderlessMenuShape,
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width,
            maxHeight: math.max(80, size.height - 32),
          ),
          items: _items(width),
        ),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    app.removeUiGuard(_guard);
    app.settings.removeListener(_refresh);
    _path.removeListener(_refresh);
    _path.dispose();
    super.dispose();
  }
}

/// 「新建自定义主题」对话框的返回值。
class _CustomThemeDraft {
  const _CustomThemeDraft(this.background, this.accent, this.name);
  final int background;
  final int accent;
  final String name;
}

Color? _parseHexColor(String input) {
  String s = input.trim().replaceFirst('#', '');
  if (s.length == 3) {
    s = s.split('').map((String c) => c + c).join();
  }
  if (s.length != 6) return null;
  final int? value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

String _colorHex(Color c) => c
    .toARGB32()
    .toRadixString(16)
    .padLeft(8, '0')
    .substring(2)
    .toUpperCase();

/// 新建自定义主题：背景色 + 提示颜色（色板 + HEX 输入）+ 可选命名 + 实时预览。
class _CustomThemeDialog extends StatefulWidget {
  const _CustomThemeDialog();

  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  static const List<Color> _backgroundPresets = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFFDF6EC),
    Color(0xFFF5F0E6),
    Color(0xFFEFE6D5),
    Color(0xFFF0F4EF),
    Color(0xFFEAF2F0),
    Color(0xFFE8E0D0),
    Color(0xFF1E1F22),
    Color(0xFF26272B),
    Color(0xFF2B2D31),
    Color(0xFF141414),
    Color(0xFF000000),
  ];

  static const List<Color> _accentPresets = <Color>[
    Color(0xFFA6402B),
    Color(0xFFC9795F),
    Color(0xFF8E3524),
    Color(0xFF5C8A57),
    Color(0xFF2F6E5A),
    Color(0xFF3A6EA5),
    Color(0xFF6B4FA0),
    Color(0xFFB07D2B),
    Color(0xFF9A3B57),
    Color(0xFF3B7C8F),
  ];

  late final TextEditingController _name;
  Color _background = AppColors.paper;
  Color _accent = AppColors.cinnabar;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _selectBackground(Color c) {
    if (c == _background) return;
    setState(() => _background = c);
  }

  void _selectAccent(Color c) {
    if (c == _accent) return;
    setState(() => _accent = c);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('新建自定义主题'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextBox(
                controller: _name,
                placeholder: '主题名称（留空自动编号，如「自定义主题1」）',
              ),
              const SizedBox(height: 14),
              _ColorField(
                label: '背景颜色',
                selected: _background,
                palette: _backgroundPresets,
                onSelected: _selectBackground,
              ),
              const SizedBox(height: 14),
              _ColorField(
                label: '提示颜色（强调色）',
                selected: _accent,
                palette: _accentPresets,
                onSelected: _selectAccent,
              ),
              const SizedBox(height: 14),
              _ThemePreview(background: _background, accent: _accent),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        Button(
          onPressed: Navigator.of(context).pop,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CustomThemeDraft(
                _background.toARGB32(),
                _accent.toARGB32(),
                _name.text,
              ),
            );
          },
          child: const Text('创建并应用'),
        ),
      ],
    );
  }
}

/// 一行颜色选择：预设色板 + HEX 输入。
///
/// 色板点击与 HEX 输入都经 [onSelected] 上报；HEX 文本由本组件持有，
/// 色板点击时同步重写，用户手动输入合法 HEX 时只上报、不动光标。
class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onSelected,
  });

  final String label;
  final Color selected;
  final List<Color> palette;
  final ValueChanged<Color> onSelected;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: _colorHex(widget.selected));
    _hex.addListener(_onHex);
  }

  void _onHex() {
    final Color? parsed = _parseHexColor(_hex.text);
    if (parsed != null) {
      widget.onSelected(parsed);
    }
  }

  @override
  void didUpdateWidget(covariant _ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 色板点击带来的外部换色：同步 HEX 文本。
    if (widget.selected != oldWidget.selected &&
        _colorHex(widget.selected) != _hex.text) {
      _hex.text = _colorHex(widget.selected);
    }
  }

  @override
  void dispose() {
    _hex.removeListener(_onHex);
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color stroke = hairlineColor(context);
    final Color labelColor = bodyTextColorLive(context);
    final bool invalid =
        _hex.text.trim().isNotEmpty && _parseHexColor(_hex.text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: TextStyle(fontSize: 12, color: labelColor)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final Color c in widget.palette)
              GestureDetector(
                onTap: () => widget.onSelected(c),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: stroke,
                      width: c == widget.selected ? 2 : 1,
                    ),
                  ),
                  child:
                      c == widget.selected
                          ? Center(
                            child: Text(
                              '✓',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: c.computeLuminance() >= 0.5
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          )
                          : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 140,
          child: TextBox(
            controller: _hex,
            placeholder: '如 0xFFA6402B 或 F5F0E6',
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (invalid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'HEX 无效：应为 6 位十六进制（可带 #）',
              style: TextStyle(
                fontSize: 11,
                color: FluentTheme.of(context).accentColor.darkest,
              ),
            ),
          ),
      ],
    );
  }
}

/// 用草稿主题模型推导派生色，预览正文/弱化文字/强调在背景上的观感。
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.background, required this.accent});

  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final AppThemeData preview = AppThemeData(
      id: '_preview',
      name: '',
      background: background,
      accent: accent,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: preview.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 12, height: 12, color: preview.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '正文预览 Aa',
                  style: TextStyle(color: preview.bodyText, fontSize: 13),
                ),
                Text(
                  '弱化文字预览',
                  style: TextStyle(color: preview.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: preview.accentSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// 重命名自定义主题。
class _RenameThemeDialog extends StatefulWidget {
  const _RenameThemeDialog({required this.initial});

  final String initial;

  @override
  State<_RenameThemeDialog> createState() => _RenameThemeDialogState();
}

class _RenameThemeDialogState extends State<_RenameThemeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('重命名自定义主题'),
      content: TextBox(controller: _controller, autofocus: true),
      actions: <Widget>[
        Button(
          onPressed: Navigator.of(context).pop,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
