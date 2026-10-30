import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models.dart';
import '../../state/settings_controller.dart';
import 'custom_theme_dialog.dart';
import 'settings_row.dart';

typedef SettingsNotice = void Function(String? text, {bool error});

class CustomThemeSection extends StatefulWidget {
  const CustomThemeSection({
    super.key,
    required this.settings,
    required this.blocked,
    required this.onModalChanged,
    required this.notice,
  });

  final SettingsController settings;
  final bool blocked;
  final ValueChanged<bool> onModalChanged;
  final SettingsNotice notice;

  @override
  State<CustomThemeSection> createState() => _CustomThemeSectionState();
}

class _CustomThemeSectionState extends State<CustomThemeSection> {
  bool _manageOpen = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_refresh);
  }

  @override
  void didUpdateWidget(CustomThemeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_refresh);
      widget.settings.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<T?> _showThemeDialog<T>(Widget dialog) async {
    widget.onModalChanged(true);
    try {
      return await showDialog<T>(context: context, builder: (_) => dialog);
    } finally {
      widget.onModalChanged(false);
    }
  }

  void _limitNotice() {
    widget.notice(
      t(context, 'settings.theme.limitReached', {
        'limit': '${SettingsController.customThemeLimit}',
      }),
      error: true,
    );
  }

  Future<void> _createCustomTheme() async {
    if (widget.settings.settings.customThemes.length >=
        SettingsController.customThemeLimit) {
      _limitNotice();
      return;
    }
    final CustomThemeDraft? draft = await _showThemeDialog<CustomThemeDraft>(
      const CustomThemeDialog(),
    );
    if (draft == null || !mounted) return;
    final CustomTheme? created = widget.settings.addCustomTheme(
      background: draft.background,
      accent: draft.accent,
      name: draft.name,
    );
    if (created == null) {
      _limitNotice();
      return;
    }
    widget.settings.setThemeMode('custom:${created.id}');
    widget.notice(t(context, 'settings.theme.created', {'name': created.name}));
  }

  Future<void> _renameCustomTheme(CustomTheme theme) async {
    final String? name = await _showThemeDialog<String>(
      RenameThemeDialog(initial: theme.name),
    );
    if (name == null || !mounted) return;
    if (!widget.settings.renameCustomTheme(theme.id, name)) {
      widget.notice(t(context, 'settings.theme.rename.failed'), error: true);
    }
  }

  Future<void> _deleteCustomTheme(CustomTheme theme) async {
    final bool? ok = await _showThemeDialog<bool>(
      ContentDialog(
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
    if (ok != true || !mounted) return;
    widget.settings.deleteCustomTheme(theme.id);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings.settings;
    final themeEntries = <(String, String)>[
      ('system', t(context, 'settings.theme.system')),
      ('light', t(context, 'settings.theme.light')),
      ('dark', t(context, 'settings.theme.dark')),
      for (final CustomTheme theme in settings.customThemes)
        ('custom:${theme.id}', theme.name),
    ];
    return SettingsRow(
      label: t(context, 'settings.theme'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ComboBox<String>(
            key: const ValueKey('settings-theme'),
            value: themeEntries.any((entry) => entry.$1 == settings.themeMode)
                ? settings.themeMode
                : null,
            items: <ComboBoxItem<String>>[
              for (final entry in themeEntries)
                ComboBoxItem<String>(value: entry.$1, child: Text(entry.$2)),
            ],
            onChanged: widget.blocked
                ? null
                : (mode) {
                    if (mode != null) widget.settings.setThemeMode(mode);
                  },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Button(
                onPressed:
                    widget.blocked ||
                        settings.customThemes.length >=
                            SettingsController.customThemeLimit
                    ? null
                    : () => unawaited(_createCustomTheme()),
                child: Text(t(context, 'settings.theme.newCustom')),
              ),
              if (settings.customThemes.isNotEmpty)
                Button(
                  onPressed: widget.blocked
                      ? null
                      : () => setState(() => _manageOpen = !_manageOpen),
                  child: Text(t(context, 'settings.theme.manage')),
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
                      key: ValueKey('custom-theme-rename-${theme.id}'),
                      onPressed: widget.blocked
                          ? null
                          : () => unawaited(_renameCustomTheme(theme)),
                      child: Text(t(context, 'common.rename')),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      key: ValueKey('custom-theme-delete-${theme.id}'),
                      onPressed: widget.blocked
                          ? null
                          : () => unawaited(_deleteCustomTheme(theme)),
                      child: Text(t(context, 'common.delete')),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.settings.removeListener(_refresh);
    super.dispose();
  }
}
