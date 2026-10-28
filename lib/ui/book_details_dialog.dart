import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/text/composing.dart';

/// 创建和作品信息共用表单。异步提交成功才关闭，失败保留输入供重试。
class BookDetailsDialog<T> extends StatefulWidget {
  const BookDetailsDialog({
    super.key,
    required this.onSave,
    this.initialTitle = '',
    this.initialNotes = '',
    this.creating = false,
  });
  final Future<T> Function(String title, String notes) onSave;
  final String initialTitle;
  final String initialNotes;
  final bool creating;

  @override
  State<BookDetailsDialog<T>> createState() => _BookDetailsDialogState<T>();
}

class _BookDetailsDialogState<T> extends State<BookDetailsDialog<T>> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.initialNotes,
  );
  final FocusNode _notesFocus = FocusNode(debugLabel: 'book-notes');
  static final LengthLimitingTextInputFormatter _limit =
      LengthLimitingTextInputFormatter(
        50,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
      );
  bool _saving = false;
  String? _error;
  bool get _composing => [_name, _notes].any((c) => isComposingValue(c.value));
  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _notes.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_saving || _composing) return;
    if (_name.text != widget.initialTitle) {
      _name.value = _limit.formatEditUpdate(
        TextEditingValue.empty,
        _name.value,
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final T result = await widget.onSave(_name.text, _notes.text);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请重试：$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _name.removeListener(_changed);
    _notes.removeListener(_changed);
    _name.dispose();
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_composing,
    child: ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(widget.creating ? '新建作品' : '作品信息'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('作品名称（最多 50 字）'),
              const SizedBox(height: 8),
              TextBox(
                key: const ValueKey('book-title-input'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                maxLines: 1,
                maxLength: 50,
                // 默认 limiter 在旧值已满 50 字时会丢弃新的 IME 组合态。
                // 先完整保留组合输入，只在上屏后按用户可见字符簇裁剪。
                maxLengthEnforcement: MaxLengthEnforcement.none,
                inputFormatters: <TextInputFormatter>[
                  TextInputFormatter.withFunction((
                    TextEditingValue oldValue,
                    TextEditingValue newValue,
                  ) {
                    if (isComposingValue(newValue)) {
                      return newValue;
                    }
                    return _limit.formatEditUpdate(
                      TextEditingValue.empty,
                      newValue,
                    );
                  }),
                ],
                textInputAction: TextInputAction.next,
                placeholder: '留空则叫「未命名作品」',
                onSubmitted: (_) => _notesFocus.requestFocus(),
              ),
              const SizedBox(height: 18),
              const Text('备注（可留空）'),
              const SizedBox(height: 8),
              TextBox(
                key: const ValueKey('book-notes-input'),
                controller: _notes,
                focusNode: _notesFocus,
                enabled: !_saving,
                minLines: 3,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                placeholder: '关于这部作品的想法…',
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                InfoBar(
                  title: const Text('未保存'),
                  content: Text(_error!),
                  severity: InfoBarSeverity.error,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        Button(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _composing ? null : _submit,
          child: Text(_saving ? '保存中…' : (widget.creating ? '创建' : '保存')),
        ),
      ],
    ),
  );
}
