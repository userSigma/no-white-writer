import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../core/chapter_numbering.dart';
import '../core/models.dart';
import '../state/workspace_controller.dart';

class VolumeSettingsDialog extends StatefulWidget {
  const VolumeSettingsDialog({
    super.key,
    required this.workspace,
    required this.volume,
  });
  final WorkspaceController workspace;
  final Volume volume;
  @override
  State<VolumeSettingsDialog> createState() => _VolumeSettingsDialogState();
}

class _VolumeSettingsDialogState extends State<VolumeSettingsDialog> {
  late bool _enabled = widget.volume.numbering.enabled;
  late String _style = widget.volume.numbering.style;
  late final _prefix = TextEditingController(
    text: widget.volume.numbering.prefix,
  );
  late final _suffix = TextEditingController(
    text: widget.volume.numbering.suffix,
  );
  late final _padding = TextEditingController(
    text: '${widget.volume.numbering.padding}',
  );
  late final _start = TextEditingController(
    text: '${widget.volume.numbering.start}',
  );
  late final _step = TextEditingController(
    text: '${widget.volume.numbering.step}',
  );
  bool _saving = false;
  String? _failure;
  List<TextEditingController> get _fields => [
    _prefix,
    _suffix,
    _padding,
    _start,
    _step,
  ];
  bool get _composing => _fields.any(
    (c) => c.value.composing.isValid && !c.value.composing.isCollapsed,
  );
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

  ChapterNumbering _rule() {
    int number(TextEditingController c) {
      if (!RegExp(r'^\d+$').hasMatch(c.text)) {
        throw const FormatException('请输入有效整数');
      }
      return int.parse(c.text);
    }

    final rule = ChapterNumbering(
      enabled: _enabled,
      prefix: _prefix.text,
      suffix: _suffix.text,
      style: _style,
      padding: number(_padding),
      start: number(_start),
      step: number(_step),
    );
    rule.validate(math.max(3, widget.volume.chapters.length));
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
    final ok = await widget.workspace.change(
      () => widget.workspace.library.setNumbering(
        widget.workspace.book,
        widget.volume,
        rule,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _failure = widget.workspace.error ?? '保存未完成，请重试';
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
    return PopScope(
      canPop: !_saving && !_composing,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 540),
        title: Text('卷设置 · ${widget.volume.title}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ToggleSwitch(
                  key: const ValueKey('numbering-enabled'),
                  checked: _enabled,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _enabled = v),
                  content: const Text('自动章节编号（仅显示，不改原名/正文）'),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _field('prefix', '前缀', _prefix)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('suffix', '后缀', _suffix)),
                  ],
                ),
                const Text('数字样式'),
                const SizedBox(height: 4),
                ComboBox<String>(
                  value: _style,
                  items: const [
                    ComboBoxItem(value: 'arabic', child: Text('阿拉伯数字')),
                    ComboBoxItem(value: 'chinese', child: Text('小写中文数字')),
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
                        '补零宽度 1–9',
                        _padding,
                        enabled: _style == 'arabic',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _field('start', '起始值（可为 0）', _start)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('step', '步长 ≥ 1', _step)),
                  ],
                ),
                const Text('预览（原始章名保持不变）'),
                const SizedBox(height: 6),
                if (rule != null)
                  for (int i = 0; i < 3; i++)
                    Text(
                      '${rule.label(i)} ${i < widget.volume.chapters.length ? widget.volume.chapters[i].title : '未命名章节'}',
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
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-volume-settings'),
            onPressed: _saving || _composing || error != null ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
