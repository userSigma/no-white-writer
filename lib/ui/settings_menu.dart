import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/i18n/i18n.dart';
import '../core/platform/platform_services.dart';
import '../core/storage/app_paths.dart';
import '../state/editor_controller.dart';
import '../state/export_controller.dart';
import '../state/settings_controller.dart';
import '../state/ui_operation_guards.dart';
import 'settings/custom_theme_section.dart';
import 'settings/export_directory_section.dart';
import 'settings/settings_row.dart';
import 'theme/tokens.dart';

/// 书架与编辑器共用的设置入口，只接收实际使用的依赖。
class SettingsMenuButton extends StatefulWidget {
  const SettingsMenuButton({
    super.key,
    required this.settings,
    required this.i18n,
    required this.platform,
    required this.paths,
    required this.editor,
    required this.exporter,
    required this.uiGuards,
    this.enabled = true,
    this.beforeOpen,
    this.secondary = false,
  });
  final EditorController editor;
  final ExportController exporter;
  final SettingsController settings;
  final I18nController i18n;
  final PlatformServices platform;
  final AppPaths paths;
  final UiOperationGuards uiGuards;
  final bool enabled;
  final bool secondary;
  final Future<bool> Function()? beforeOpen;
  @override
  State<SettingsMenuButton> createState() => SettingsMenuButtonState();
}

class SettingsMenuButtonState extends State<SettingsMenuButton> {
  bool _opening = false;

  /// 开发验收入口也通过此方法打开真实浮窗。
  Future<void> open() async {
    if (_opening ||
        !widget.enabled ||
        widget.exporter.busy ||
        widget.editor.isComposing) {
      return;
    }
    _opening = true;
    try {
      if (widget.beforeOpen != null && !await widget.beforeOpen!()) return;
      if (!await widget.uiGuards.flush() ||
          !await widget.editor.flush() ||
          !mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _SettingsDialog(
          settings: widget.settings,
          i18n: widget.i18n,
          platform: widget.platform,
          paths: widget.paths,
          uiGuards: widget.uiGuards,
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed =
        widget.enabled && !widget.exporter.busy && !widget.editor.isComposing
        ? open
        : null;
    return Tooltip(
      message: t(context, 'settings.title'),
      child: widget.secondary
          ? Button(
              key: const ValueKey('settings-button'),
              onPressed: onPressed,
              child: const SizedBox(
                width: 16,
                height: 20,
                child: Center(child: Icon(FluentIcons.settings, size: 16)),
              ),
            )
          : IconButton(
              key: const ValueKey('settings-button'),
              icon: const Icon(FluentIcons.settings),
              onPressed: onPressed,
            ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.i18n,
    required this.platform,
    required this.paths,
    required this.uiGuards,
  });
  final SettingsController settings;
  final I18nController i18n;
  final PlatformServices platform;
  final AppPaths paths;
  final UiOperationGuards uiGuards;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final ExportDirectoryDraft _directory;
  late final Object _guard;
  bool _closing = false;
  bool _confirming = false;
  String? _message;
  bool _messageError = false;
  bool get _working => _directory.working;

  @override
  void initState() {
    super.initState();
    _directory = ExportDirectoryDraft(
      settings: widget.settings,
      paths: widget.paths,
      selectDirectory: widget.platform.selectDirectory,
      revealDirectory: widget.platform.revealInFileManager,
      notice: (text, error) => _notice(text, error: error),
    )..addListener(_refresh);
    widget.settings.addListener(_refresh);
    _guard = widget.uiGuards.register(_prepareClose);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ComboBox 弹层先消费 Esc；未消费的 Esc 才关闭设置浮窗。
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape ||
        _confirming ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    unawaited(requestClose());
    return KeyEventResult.handled;
  }

  void _notice(String? text, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = text;
        _messageError = error;
      });
    }
  }

  Future<bool> _prepareClose() async {
    if (_confirming) return false;
    return _directory.prepareClose(context);
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

  void _setLanguage(String code) {
    if (widget.i18n.setLanguage(code)) widget.settings.setLanguage(code);
  }

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
    isExpanded: true,
    value: value,
    items: [
      for (final v in values) ComboBoxItem(value: v, child: Text(label(v))),
    ],
    onChanged: _working ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings.settings;
    final packs = widget.i18n.packs;
    final fontSizes = <double>[for (var v = 14; v <= 28; v++) v.toDouble()];
    final lineHeights = <double>[for (var s = 0; s <= 10; s++) (14 + s) / 10];
    final error = widget.settings.saveError;
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
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 756),
          style: const ContentDialogThemeData(
            padding: EdgeInsetsDirectional.fromSTEB(24, 20, 24, 20),
            actionsPadding: EdgeInsetsDirectional.fromSTEB(24, 16, 24, 16),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  t(context, 'settings.title'),
                  style: TextStyle(
                    color: accentColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Tooltip(
                message: t(context, 'common.close'),
                child: IconButton(
                  key: const ValueKey('settings-close'),
                  icon: const Icon(FluentIcons.chrome_close, size: 14),
                  onPressed: _working || _confirming
                      ? null
                      : () => unawaited(requestClose()),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsRow(
                    label: t(context, 'settings.language'),
                    child: ComboBox<String>(
                      key: const ValueKey('settings-language'),
                      isExpanded: true,
                      value: packs.any((p) => p.code == widget.i18n.currentCode)
                          ? widget.i18n.currentCode
                          : null,
                      items: [
                        for (final pack in packs)
                          ComboBoxItem(
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
                  CustomThemeSection(
                    settings: widget.settings,
                    blocked: _working,
                    onModalChanged: (value) {
                      if (mounted) setState(() => _confirming = value);
                    },
                    notice: _notice,
                  ),
                  _divider(),
                  SettingsRow(
                    label: t(context, 'settings.fontSize'),
                    child: _combo(
                      comboKey: const ValueKey('settings-font-size'),
                      value: fontSizes.contains(settings.fontSize)
                          ? settings.fontSize
                          : null,
                      values: fontSizes,
                      label: (v) => t(context, 'settings.fontSize.value', {
                        'value': v.toInt().toString(),
                      }),
                      onChanged: (value) {
                        if (value != null) widget.settings.setFontSize(value);
                      },
                    ),
                  ),
                  SettingsRow(
                    label: t(context, 'settings.lineHeight'),
                    child: _combo(
                      comboKey: const ValueKey('settings-line-height'),
                      value: lineHeights.contains(settings.lineHeight)
                          ? settings.lineHeight
                          : null,
                      values: lineHeights,
                      label: (v) => t(context, 'settings.lineHeight.value', {
                        'value': v.toStringAsFixed(1),
                      }),
                      onChanged: (value) {
                        if (value != null) widget.settings.setLineHeight(value);
                      },
                    ),
                  ),
                  SettingsRow(
                    label: t(context, 'settings.autoIndent'),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ToggleSwitch(
                        key: const ValueKey('settings-auto-indent'),
                        checked: settings.autoIndent,
                        onChanged: _working
                            ? null
                            : widget.settings.setAutoIndent,
                      ),
                    ),
                  ),
                  SettingsRow(
                    label: t(context, 'settings.blankLine'),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ToggleSwitch(
                        key: const ValueKey('settings-blank-line'),
                        checked: settings.blankLineBetween,
                        onChanged: _working
                            ? null
                            : widget.settings.setBlankLineBetween,
                      ),
                    ),
                  ),
                  _divider(),
                  ExportDirectorySection(
                    draft: _directory,
                    paths: widget.paths,
                  ),
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                  if (error != null) ...[
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
                      onPressed: _working
                          ? null
                          : () => _directory.retry(context),
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
          actions: [
            Button(
              key: const ValueKey('settings-done'),
              onPressed: _working || _confirming
                  ? null
                  : () => unawaited(requestClose()),
              child: Text(t(context, 'settings.done')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.uiGuards.remove(_guard);
    widget.settings.removeListener(_refresh);
    _directory.removeListener(_refresh);
    _directory.dispose();
    super.dispose();
  }
}
