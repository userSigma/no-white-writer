import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/text/indent_rules.dart';

TextEditingValue _value(String text, [int? offset]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset ?? text.length),
);

void main() {
  group('applyEnterIndent', () {
    test('关闭自动缩进时原样返回', () {
      final TextEditingValue oldValue = _value('正文');
      final TextEditingValue newValue = _value('正文\n');
      expect(
        applyEnterIndent(
          oldValue,
          newValue,
          autoIndent: false,
          blankLineBetween: false,
        ),
        same(newValue),
      );
    });

    test('段末回车补两个全角空格，光标在缩进之后', () {
      final TextEditingValue result = applyEnterIndent(
        _value('正文'),
        _value('正文\n'),
        autoIndent: true,
        blankLineBetween: false,
      );
      expect(result.text, '正文\n$kIndent');
      expect(result.selection.baseOffset, '正文\n$kIndent'.length);
      expect(result.composing, TextRange.empty);
    });

    test('段中回车只给后段补缩进', () {
      final TextEditingValue result = applyEnterIndent(
        _value('前半后半', 2),
        _value('前半\n后半', 3),
        autoIndent: true,
        blankLineBetween: false,
      );
      expect(result.text, '前半\n$kIndent后半');
    });

    test('连续回车不叠加缩进', () {
      final TextEditingValue oldValue = _value('正文\n$kIndent');
      final TextEditingValue result = applyEnterIndent(
        oldValue,
        _value('正文\n$kIndent\n'),
        autoIndent: true,
        blankLineBetween: false,
      );
      expect(result.text, '正文\n$kIndent\n');
    });

    test('下一行已有缩进则不重复插入', () {
      final TextEditingValue result = applyEnterIndent(
        _value('$kIndent甲乙$kIndent丙丁', '$kIndent甲乙'.length),
        _value('$kIndent甲乙\n$kIndent丙丁', '$kIndent甲乙'.length + 1),
        autoIndent: true,
        blankLineBetween: true,
      );
      expect(result.text, '$kIndent甲乙\n$kIndent丙丁');
    });

    test('段间空行开启时在段末补一个空行，空行不含全角空格', () {
      final TextEditingValue result = applyEnterIndent(
        _value('正文'),
        _value('正文\n'),
        autoIndent: true,
        blankLineBetween: true,
      );
      expect(result.text, '正文\n\n$kIndent');
    });

    test('IME 组合态输入回车不干预', () {
      final TextEditingValue newValue = const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      expect(
        applyEnterIndent(
          _value(''),
          newValue,
          autoIndent: true,
          blankLineBetween: false,
        ),
        same(newValue),
      );
    });

    test('粘贴/批量替换（长度变化不是 +1）不干预', () {
      final TextEditingValue newValue = _value('正文\n\n\n');
      expect(
        applyEnterIndent(
          _value('正文'),
          newValue,
          autoIndent: true,
          blankLineBetween: false,
        ),
        same(newValue),
      );
    });
  });
}
