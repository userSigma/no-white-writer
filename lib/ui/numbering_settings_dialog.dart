import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../core/chapter_numbering.dart';
import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../core/text/composing.dart';
import '../state/workspace_controller.dart';

/// 编号规则编辑浮窗（任务4：两层自动章节序号）。
///
/// - [volume] 为 `null` → 全局层：编辑书籍级「全局自动章节序号」
///   （开关 + 规则），保存到 `setGlobalNumbering`；
/// - [volume] 非 `null` → 卷层：编辑该卷的「卷内独立编号」规则
///   （模式开关在卷菜单三选一里，此处只编辑规则），保存到 `setNumbering`。
///
/// 旧 `VolumeSettingsDialog`（卷设置）除编号外无其他内容，已被本浮窗取代。
class NumberingSettingsDialog extends StatefulWidget {
  const NumberingSettingsDialog({
    super.key,
    required this.workspace,
    this.volume,
  });
  final WorkspaceController workspace;
  final Volume? volume;
  @override
  State<NumberingSettingsDialog> createState() =>
      _NumberingSettingsDialogState();
}

class _NumberingSettingsDialogState extends State<NumberingSettingsDialog> {
  bool get _isGlobal => widget.volume == null;

  ChapterNumbering get _initial =>
      _isGlobal
          ? widget.workspace.book.globalNumbering
          : widget.volume!.numbering;

  late bool _enabled = _initial.enabled;
  late String _style = _initial.style;
  late final _prefix = TextEditingController(text: _initial.prefix);
  late final _suffix = TextEditingController(text: _initial.suffix);
  late final _padding = TextEditingController(text: '${_initial.padding}');
  late final _start = TextEditingController(text: '${_initial.start}');
  late final _step = TextEditingController(text: '${_initial.step}');
  bool _saving = false;
  String? _failure;
  List<TextEditingController> get _fields => [
    _prefix,
    _suffix,
    _padding,
    _start,
    _step,
  ];
  bool get _composing => _fields.any((c) => isComposingValue(c.value));
  @override
  void initState() {
    super.initState();
    for (final c in _fields) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() => _failure = null);
  }

  int get _validateCount {
    if (!_isGlobal) return math.max(3, widget.volume!.chapters.length);
    return math.max(3, globalNumberingChapterCount(widget.workspace.book));
  }

  ChapterNumbering _rule() {
    int number(TextEditingController c) {
      if (!RegExp(r'^\d+$').hasMatch(c.text)) {
        throw FormatException(t(context, 'numbering.invalidInt'));
      }
      return int.parse(c.text);
    }

    final rule = ChapterNumbering(
      // 卷模式固定启用：是否启用由卷菜单的「章节编号」三选一控制。
      enabled: _isGlobal ? _enabled : true,
      prefix: _prefix.text,
      suffix: _suffix.text,
      style: _style,
      padding: number(_padding),
      start: number(_start),
      step: number(_step),
    );
    rule.validate(_validateCount);
    return rule;
  }

  Future<void> _save() async {
    if (_saving || _composing) return;
    ChapterNumbering rule;
    try {
      rule = _rule();
    } catch (_) {
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    final w = widget.workspace;
    final ok = await w.change(() {
      if (_isGlobal) {
        return w.library.setGlobalNumbering(w.book, rule);
      }
      return w.library.setNumbering(w.book, widget.volume!, rule);
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _failure = w.error ?? t(context, 'numbering.save.fallback');
      });
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 4),
        TextBox(
          key: ValueKey('numbering-$key'),
          controller: c,
          maxLines: 1,
          enabled: enabled && !_saving,
          onChanged: (_) => setState(() => _failure = null),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    ChapterNumbering? rule;
    String? error;
    try {
      rule = _rule();
    } catch (e) {
      error = '$e';
    }
    final String title = _isGlobal
        ? t(context, 'numbering.global.title')
        : t(
            context,
            'numbering.volume.title',
            {'name': displayVolumeTitle(widget.volume!)},
          );
    final int previewCount = _isGlobal
        ? globalNumberingChapterCount(widget.workspace.book)
        : widget.volume!.chapters.length;
    return PopScope(
      canPop: !_saving && !_composing,
      child: ContentDialog(
        key: const ValueKey('numbering-dialog'),
        constraints: const BoxConstraints(maxWidth: 540),
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isGlobal)
                  ToggleSwitch(
                    key: const ValueKey('numbering-enabled'),
                    checked: _enabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _enabled = v),
                    content: Text(t(context, 'numbering.enabled.caption')),
                  )
                else
                  Text(t(context, 'numbering.volume.caption')),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        'prefix',
                        t(context, 'numbering.prefix'),
                        _prefix,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        'suffix',
                        t(context, 'numbering.suffix'),
                        _suffix,
                      ),
                    ),
                  ],
                ),
                Text(t(context, 'numbering.style')),
                const SizedBox(height: 4),
                ComboBox<String>(
                  value: _style,
                  items: [
                    ComboBoxItem(
                      value: 'arabic',
                      child: Text(t(context, 'numbering.style.arabic')),
                    ),
                    ComboBoxItem(
                      value: 'chinese',
                      child: Text(t(context, 'numbering.style.chinese')),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v != null) setState(() => _style = v);
                        },
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        'padding',
                        t(context, 'numbering.padding'),
                        _padding,
                        enabled: _style == 'arabic',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        'start',
                        t(context, 'numbering.start'),
                        _start,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        'step',
                        t(context, 'numbering.step'),
                        _step,
                      ),
                    ),
                  ],
                ),
                Text(t(context, 'numbering.preview')),
                const SizedBox(height: 6),
                if (rule != null)
                  for (int i = 0; i < 3; i++)
                    Text(
                      '${rule.label(i)} ${i < previewCount ? (_isGlobal ? t(context, 'common.untitledChapter') : widget.volume!.chapters[i].title) : t(context, 'common.untitledChapter')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                if (error != null) Text(error),
                if (_failure != null) Text(_failure!),
              ],
            ),
          ),
        ),
        actions: [
          Button(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            key: const ValueKey('numbering-save'),
            onPressed: _saving || _composing || error != null ? null : _save,
            child: Text(
              _saving
                  ? t(context, 'numbering.saving')
                  : t(context, 'common.save'),
            ),
          ),
        ],
      ),
    );
  }
}
