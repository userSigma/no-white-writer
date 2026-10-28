import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../app_context.dart';
import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../core/text/composing.dart';
import '../state/settings_controller.dart';
import 'theme/tokens.dart';

/// 设置入口按钮：点击打开「设置浮窗」（ContentDialog）。
///
/// 书架页与编辑器侧栏共用同一按钮与浮窗；dev 验收入口通过 [open]
/// 打开的是同一个浮窗，而不是单独页面。
class SettingsMenuButton extends StatefulWidget {
  const SettingsMenuButton({
    super.key,
    required this.app,
    this.enabled = true,
    this.beforeOpen,
  });
  final AppContext app;
  final bool enabled;
  final Future<bool> Function()? beforeOpen;
  @override
  State<SettingsMenuButton> createState() => SettingsMenuButtonState();
}

class SettingsMenuButtonState extends State<SettingsMenuButton> {
  bool _opening = false;

  /// Opens the settings dialog; the dev entry point uses this so the
  /// acceptance shortcut shows the real dialog instead of a separate page.
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
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _SettingsDialog(app: widget.app),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: t(context, 'settings.title'),
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
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppContext app;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _path;
  late final Object _guard;
  bool _working = false;
  bool _closing = false;
  bool _confirming = false;
  bool _manageOpen = false;
  String? _message;
  bool _messageError = false;
  AppContext get app => widget.app;
  bool get _composing => isComposingValue(_path.value);
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
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Esc 关闭浮窗（确认框打开时交还给确认框自己）。
  ///
  /// 走焦点系统而不是全局键盘钩子：ComboBox 弹层打开时它内部先消费
  /// Esc 只关弹层，未消费的 Esc 才冒泡到这里关闭浮窗。
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape || _confirming) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    unawaited(requestClose());
    return KeyEventResult.handled;
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
          title: Text(t(context, 'settings.exportDir.confirm.title')),
          content: Text(t(context, 'settings.exportDir.confirm.body')),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, 'settings.exportDir.confirm.keep')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, 'settings.exportDir.confirm.discard')),
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
      if (!mounted) return false;
      _notice(t(context, 'settings.saveError', {'error': '$error'}), error: true);
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
      if (!mounted) return;
      _notice(t(context, 'settings.exportDir.saved'));
    } catch (error) {
      // Restore only the confirmed preference; keep the failed input for retry.
      // 失败详情交给浮窗内的红字（settings-save-error）与「重试保存」按钮，
      // 不再额外弹 InfoBar，避免通知层遮住重试按钮。
      app.settings.settings.exportDirectory = previous;
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openDirectory(String path) async {
    if (_working || _composing) return;
    setState(() => _working = true);
    try {
      final opened = await app.platform.revealInFileManager(path);
      if (!mounted) return;
      if (!opened) {
        _notice(t(context, 'settings.openDir.failed'), error: true);
      } else {
        _notice(t(context, 'settings.openDir.opened'));
      }
    } catch (error) {
      _notice('$error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _setLanguage(String code) {
    if (app.i18n.setLanguage(code)) {
      app.settings.setLanguage(code);
    }
  }

  Future<void> _createCustomTheme() async {
    if (app.settings.settings.customThemes.length >=
        SettingsController.customThemeLimit) {
      _notice(
        t(context, 'settings.theme.limitReached', {
          'limit': '${SettingsController.customThemeLimit}',
        }),
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
      _notice(
        t(context, 'settings.theme.limitReached', {
          'limit': '${SettingsController.customThemeLimit}',
        }),
        error: true,
      );
      return;
    }
    app.settings.setThemeMode('custom:${created.id}');
    _notice(t(context, 'settings.theme.created', {'name': created.name}));
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
      _notice(t(context, 'settings.theme.rename.failed'), error: true);
    }
  }

  Future<void> _deleteCustomTheme(CustomTheme theme) async {
    _confirming = true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(t(context, 'settings.theme.delete', {'name': theme.name})),
        content: Text(t(context, 'settings.theme.delete.confirm.body')),
        actions: <Widget>[
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'common.delete')),
          ),
        ],
      ),
    );
    _confirming = false;
    if (ok != true || !mounted) return;
    app.settings.deleteCustomTheme(theme.id);
  }

  // ---- 布局辅助 ----------------------------------------------------------

  Widget _row(String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: bodyTextColor(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: control),
      ],
    ),
  );

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(height: 1, color: hairlineColor(context)),
  );

  ComboBox<double> _combo({
    required double? value,
    required List<double> values,
    required String Function(double) label,
    required ValueChanged<double?> onChanged,
    Key? comboKey,
  }) => ComboBox<double>(
    key: comboKey,
    value: value,
    items: <ComboBoxItem<double>>[
      for (final double v in values)
        ComboBoxItem<double>(value: v, child: Text(label(v))),
    ],
    onChanged: _working || _composing ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final settings = app.settings.settings;
    final packs = app.i18n.packs;
    final themeEntries = <(String, String)>[
      ('system', t(context, 'settings.theme.system')),
      ('light', t(context, 'settings.theme.light')),
      ('dark', t(context, 'settings.theme.dark')),
      for (final CustomTheme theme in settings.customThemes)
        ('custom:${theme.id}', theme.name),
    ];
    final fontSizes = <double>[for (var v = 14; v <= 28; v++) v.toDouble()];
    final lineHeights = <double>[for (var s = 0; s <= 10; s++) (14 + s) / 10];
    final error = app.settings.saveError;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(requestClose());
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: ContentDialog(
        key: const ValueKey('settings-menu'),
        title: Text(
          t(context, 'settings.title'),
          style: const TextStyle(
            color: AppColors.cinnabar,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _row(
                  t(context, 'settings.language'),
                  ComboBox<String>(
                    key: const ValueKey('settings-language'),
                    value: packs.any((p) => p.code == app.i18n.currentCode)
                        ? app.i18n.currentCode
                        : null,
                    items: <ComboBoxItem<String>>[
                      for (final pack in packs)
                        ComboBoxItem<String>(
                          value: pack.code,
                          child: Text('${pack.name} (${pack.code})'),
                        ),
                    ],
                    onChanged: _working
                        ? null
                        : (code) {
                            if (code != null) _setLanguage(code);
                          },
                  ),
                ),
                _row(
                  t(context, 'settings.theme'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ComboBox<String>(
                        key: const ValueKey('settings-theme'),
                        value: themeEntries
                            .any((e) => e.$1 == settings.themeMode)
                            ? settings.themeMode
                            : null,
                        items: <ComboBoxItem<String>>[
                          for (final entry in themeEntries)
                            ComboBoxItem<String>(
                              value: entry.$1,
                              child: Text(entry.$2),
                            ),
                        ],
                        onChanged: _working || _composing
                            ? null
                            : (mode) {
                                if (mode != null) {
                                  app.settings.setThemeMode(mode);
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Button(
                            onPressed:
                                _working || _composing ||
                                    settings.customThemes.length >=
                                        SettingsController.customThemeLimit
                                ? null
                                : () => unawaited(_createCustomTheme()),
                            child: Text(
                              t(context, 'settings.theme.newCustom'),
                            ),
                          ),
                          if (settings.customThemes.isNotEmpty)
                            Button(
                              onPressed: _working || _composing
                                  ? null
                                  : () =>
                                        setState(() => _manageOpen = !_manageOpen),
                              child: Text(
                                t(context, 'settings.theme.manage'),
                              ),
                            ),
                        ],
                      ),
                      if (_manageOpen) ...<Widget>[
                        const SizedBox(height: 8),
                        for (final CustomTheme theme in settings.customThemes)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: <Widget>[
                                Expanded(child: Text(theme.name)),
                                Button(
                                  key: ValueKey(
                                    'custom-theme-rename-${theme.id}',
                                  ),
                                  onPressed: _working || _composing
                                      ? null
                                      : () =>
                                            unawaited(_renameCustomTheme(theme)),
                                  child: Text(t(context, 'common.rename')),
                                ),
                                const SizedBox(width: 8),
                                Button(
                                  key: ValueKey(
                                    'custom-theme-delete-${theme.id}',
                                  ),
                                  onPressed: _working || _composing
                                      ? null
                                      : () =>
                                            unawaited(_deleteCustomTheme(theme)),
                                  child: Text(t(context, 'common.delete')),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                _divider(),
                _row(
                  t(context, 'settings.fontSize'),
                  _combo(
                    comboKey: const ValueKey('settings-font-size'),
                    value: fontSizes.contains(settings.fontSize)
                        ? settings.fontSize
                        : null,
                    values: fontSizes,
                    label: (v) => v.toInt().toString(),
                    onChanged: (value) {
                      if (value != null) app.settings.setFontSize(value);
                    },
                  ),
                ),
                _row(
                  t(context, 'settings.lineHeight'),
                  _combo(
                    comboKey: const ValueKey('settings-line-height'),
                    value: lineHeights.contains(settings.lineHeight)
                        ? settings.lineHeight
                        : null,
                    values: lineHeights,
                    label: (v) => v.toStringAsFixed(1),
                    onChanged: (value) {
                      if (value != null) app.settings.setLineHeight(value);
                    },
                  ),
                ),
                _row(
                  t(context, 'settings.autoIndent'),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ToggleSwitch(
                      key: const ValueKey('settings-auto-indent'),
                      checked: settings.autoIndent,
                      onChanged: _working || _composing
                          ? null
                          : app.settings.setAutoIndent,
                    ),
                  ),
                ),
                _row(
                  t(context, 'settings.blankLine'),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ToggleSwitch(
                      key: const ValueKey('settings-blank-line'),
                      checked: settings.blankLineBetween,
                      onChanged: _working || _composing
                          ? null
                          : app.settings.setBlankLineBetween,
                    ),
                  ),
                ),
                _divider(),
                _row(
                  t(context, 'settings.exportDir'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextBox(
                        key: const ValueKey('settings-export-path'),
                        controller: _path,
                        enabled: !_working,
                        placeholder: t(context, 'settings.exportDir.hint'),
                        onEditingComplete: () {},
                        onSubmitted: (_) {
                          if (!_composing) unawaited(_savePath());
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Button(
                            onPressed: _working || _composing
                                ? null
                                : () => unawaited(_savePath()),
                            child: Text(t(context, 'common.save')),
                          ),
                          Button(
                            onPressed: _working || _composing
                                ? null
                                : () => unawaited(_savePath(useDefault: true)),
                            child: Text(
                              t(context, 'settings.exportDir.reset'),
                            ),
                          ),
                          Button(
                            onPressed: _working || _composing
                                ? null
                                : () {
                                    if (_dirty) {
                                      _notice(
                                        t(
                                          context,
                                          'settings.exportDir.pending',
                                        ),
                                        error: true,
                                      );
                                      return;
                                    }
                                    unawaited(
                                      _openDirectory(
                                        app.paths.exportRoot(
                                          settings.exportDirectory,
                                        ),
                                      ),
                                    );
                                  },
                            child: Text(
                              t(context, 'settings.exportDir.open'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _row(
                  '',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Button(
                        onPressed: _working
                            ? null
                            : () =>
                                  unawaited(_openDirectory(app.paths.dataRootPath)),
                        child: Text(t(context, 'settings.dataDir')),
                      ),
                      Button(
                        onPressed: _working
                            ? null
                            : () =>
                                  unawaited(_openDirectory(app.paths.logsDir)),
                        child: Text(t(context, 'settings.logsDir')),
                      ),
                    ],
                  ),
                ),
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t(context, 'settings.about.version'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t(context, 'settings.about.desc'),
                        style: TextStyle(
                          fontSize: 12,
                          color: mutedTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    t(context, 'settings.saveError', {'error': error}),
                    key: const ValueKey('settings-save-error'),
                    style: TextStyle(
                      fontSize: 12,
                      color: FluentTheme.of(context).accentColor.darkest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Button(
                    onPressed: _working || _composing
                        ? null
                        : () async {
                            if (_dirty) {
                              await _savePath();
                              return;
                            }
                            try {
                              await app.settings.flush();
                              if (!context.mounted) return;
                              _notice(t(context, 'settings.saved'));
                            } catch (error) {
                              if (!context.mounted) return;
                              _notice(
                                t(context, 'settings.saveError', {
                                  'error': '$error',
                                }),
                                error: true,
                              );
                            }
                          },
                    child: Text(t(context, 'settings.retrySave')),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InfoBar(
                      key: const ValueKey('settings-notice'),
                      title: Text(_message!),
                      severity: _messageError
                          ? InfoBarSeverity.error
                          : InfoBarSeverity.success,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: _working || _composing || _confirming
                ? null
                : () => unawaited(requestClose()),
            child: Text(t(context, 'common.close')),
          ),
        ],
        ),
      ),
    );
  }

  @override
  void dispose() {
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

String _colorHex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

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
      title: Text(t(context, 'settings.theme.create.title')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextBox(
                controller: _name,
                placeholder: t(context, 'settings.theme.name.hint'),
              ),
              const SizedBox(height: 14),
              _ColorField(
                label: t(context, 'settings.theme.background'),
                selected: _background,
                palette: _backgroundPresets,
                onSelected: _selectBackground,
              ),
              const SizedBox(height: 14),
              _ColorField(
                label: t(context, 'settings.theme.accent'),
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
          child: Text(t(context, 'common.cancel')),
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
          child: Text(t(context, 'settings.theme.create.confirm')),
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
    final Color labelColor = bodyTextColor(context);
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
                  child: c == widget.selected
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
            placeholder: t(context, 'settings.theme.hex.hint'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (invalid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t(context, 'settings.theme.hex.invalid'),
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
                  t(context, 'settings.theme.preview.body'),
                  style: TextStyle(color: preview.bodyText, fontSize: 13),
                ),
                Text(
                  t(context, 'settings.theme.preview.muted'),
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
      title: Text(t(context, 'settings.theme.rename.title')),
      content: TextBox(controller: _controller, autofocus: true),
      actions: <Widget>[
        Button(
          onPressed: Navigator.of(context).pop,
          child: Text(t(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(t(context, 'common.confirm')),
        ),
      ],
    );
  }
}
