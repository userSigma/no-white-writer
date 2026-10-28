import 'package:flutter/services.dart';

import 'composing.dart';

/// 首行缩进常量：两个全角空格（PLAN.md §8.1）。
const String kIndent = '\u3000\u3000';

/// 回车缩进规则（纯函数，可单测；PLAN.md §8.1/§8.2）。
///
/// 只在「一次换行插入」且无 IME 组合态时生效，不使用 TextInputFormatter：
/// 由编辑器 controller 的监听器调用，把修正后的 value（含光标）一次性写回。
TextEditingValue applyEnterIndent(
  TextEditingValue oldValue,
  TextEditingValue newValue, {
  required bool autoIndent,
  required bool blankLineBetween,
}) {
  if (!autoIndent) return newValue;
  if (isComposingValue(newValue)) return newValue;

  final String text = newValue.text;
  final int? newlineAt = _singleNewlineInsertion(oldValue.text, text);
  if (newlineAt == null) return newValue;

  final int lineStart = newlineAt == 0
      ? 0
      : text.lastIndexOf('\n', newlineAt - 1) + 1;
  final String beforeLine = text.substring(lineStart, newlineAt);
  final int nextBreak = text.indexOf('\n', newlineAt + 1);
  final String afterLine = nextBreak < 0
      ? text.substring(newlineAt + 1)
      : text.substring(newlineAt + 1, nextBreak);

  // 连续回车：光标正好在行首缩进之后（本行除缩进外没有别的字）→ 只回车，不叠加 U+3000。
  final bool consecutive = beforeLine == kIndent;
  final bool alreadyIndented = afterLine.startsWith(kIndent);

  String insertion = '';
  if (!consecutive) {
    if (!alreadyIndented) insertion = kIndent;
    // 段间空行（默认关）：只在段末回车时补一个空行，空行本身不含全角空格。
    if (blankLineBetween && insertion.isNotEmpty && afterLine.isEmpty) {
      insertion = '\n$insertion';
    }
  }

  if (insertion.isEmpty) return newValue;

  final int insertPos = newlineAt + 1;
  final String newText = text.replaceRange(insertPos, insertPos, insertion);
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: insertPos + insertion.length),
    composing: TextRange.empty,
  );
}

/// 若 new 相比 old 只多插入了一个 `\n`，返回它的位置；否则 null。
/// 允许用户在别处改动造成的选择变化，但不接受批量替换。
int? _singleNewlineInsertion(String oldText, String newText) {
  if (newText.length != oldText.length + 1) return null;
  int i = 0;
  while (i < oldText.length && oldText.codeUnitAt(i) == newText.codeUnitAt(i)) {
    i++;
  }
  if (i >= newText.length || newText.codeUnitAt(i) != 0x0A) return null;
  if (newText.substring(i + 1) != oldText.substring(i)) return null;
  return i;
}
