import 'package:flutter/services.dart' show TextEditingValue, TextRange;
import 'package:flutter/widgets.dart' show TextEditingController;

import 'composing.dart';
import 'indent_rules.dart';

/// Paragraph whitespace is applied as one controller transaction, with selection
/// offsets mapped by TextEditingValue.replaced. Never rewrite an IME draft.
class IndentingTextEditingController extends TextEditingController {
  IndentingTextEditingController({
    required this.autoIndent,
    required this.blankLineBetween,
  }) : _indent = autoIndent(),
       _blank = blankLineBetween();

  final bool Function() autoIndent;
  final bool Function() blankLineBetween;
  bool _indent;
  bool _blank;

  void refreshParagraphStyle() {
    if (_indent != autoIndent() || _blank != blankLineBetween()) {
      value = value;
    }
  }

  @override
  set value(TextEditingValue newValue) {
    if (isComposingValue(newValue)) {
      super.value = newValue;
      return;
    }
    final bool indent = autoIndent(), blank = blankLineBetween();
    TextEditingValue formatted = applyEnterIndent(
      super.value,
      newValue,
      autoIndent: indent,
      blankLineBetween: blank,
    );
    // Remove only the conventional formatting when its preference is disabled.
    if (_indent && !indent) {
      formatted = _replaceMatches(
        formatted,
        RegExp(r'^　　', multiLine: true),
        '',
      );
    }
    if (_blank && !blank) {
      formatted = _replaceMatches(formatted, RegExp(r'\n\n(?=[^\n])'), '\n');
    }
    if (indent) {
      formatted = _replaceMatches(
        formatted,
        RegExp(r'^(?!　　)(?=[^\s])', multiLine: true),
        kIndent,
      );
    }
    if (blank) {
      formatted = _replaceMatches(
        formatted,
        RegExp(r'(?<=[^\n])\n(?=[^\n])'),
        '\n\n',
      );
    }
    _indent = indent;
    _blank = blank;
    super.value = formatted;
  }

  TextEditingValue _replaceMatches(
    TextEditingValue input,
    RegExp pattern,
    String replacement,
  ) {
    TextEditingValue result = input;
    for (final match in pattern.allMatches(input.text).toList().reversed) {
      result = result.replaced(
        TextRange(start: match.start, end: match.end),
        replacement,
      );
    }
    return result;
  }
}
