import 'package:flutter/services.dart' show TextEditingValue;

import 'package:flutter/widgets.dart' show TextEditingController;

import 'indent_rules.dart';

/// 在 controller 层实现回车自动缩进（PLAN.md Q27 / §8.1）：把修正后的 value
/// 一次性写回，避免 TextInputFormatter 在 IME 组合态下反复改写导致丢字。
class IndentingTextEditingController extends TextEditingController {
  IndentingTextEditingController({
    required this.autoIndent,
    required this.blankLineBetween,
  });

  final bool Function() autoIndent;
  final bool Function() blankLineBetween;

  @override
  set value(TextEditingValue newValue) {
    final TextEditingValue oldValue = super.value;
    super.value = applyEnterIndent(
      oldValue,
      newValue,
      autoIndent: autoIndent(),
      blankLineBetween: blankLineBetween(),
    );
  }
}
