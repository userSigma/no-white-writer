import 'package:fluent_ui/fluent_ui.dart';

import '../../core/i18n/i18n.dart';
import '../theme/tokens.dart';

/// 「新建自定义主题」对话框的返回值。
class CustomThemeDraft {
  const CustomThemeDraft(this.background, this.accent, this.name);
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
class CustomThemeDialog extends StatefulWidget {
  const CustomThemeDialog({super.key});

  @override
  State<CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<CustomThemeDialog> {
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
              CustomThemeDraft(
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
class RenameThemeDialog extends StatefulWidget {
  const RenameThemeDialog({super.key, required this.initial});

  final String initial;

  @override
  State<RenameThemeDialog> createState() => _RenameThemeDialogState();
}

class _RenameThemeDialogState extends State<RenameThemeDialog> {
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[TextBox(controller: _controller, autofocus: true)],
      ),
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
