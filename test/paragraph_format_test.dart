import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/text/indenting_controller.dart';

void main() {
  test('initial and pasted paragraphs receive two fullwidth spaces', () {
    final c = IndentingTextEditingController(
      autoIndent: () => true,
      blankLineBetween: () => false,
    );
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
      text: '第一段\n第二段',
      selection: TextSelection.collapsed(offset: 7),
    );
    expect(c.text, '　　第一段\n　　第二段');
    expect(c.selection.extentOffset, 11);
  });

  test('blank-line preference works independently of indentation', () {
    final c = IndentingTextEditingController(
      autoIndent: () => false,
      blankLineBetween: () => true,
    );
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
      text: '甲\n乙',
      selection: TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(c.text, '甲\n\n乙');
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
  });

  test('Enter immediately adds a blank line without auto indentation', () {
    final c = IndentingTextEditingController(
      autoIndent: () => false,
      blankLineBetween: () => true,
    );
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
      text: '正文',
      selection: TextSelection.collapsed(offset: 2),
    );
    c.value = const TextEditingValue(
      text: '正文\n',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(c.text, '正文\n\n');
    expect(c.selection.extentOffset, 4);
    c.value = const TextEditingValue(
      text: '正文\n\n\n',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(
      c.text,
      '正文\n\n\n',
      reason: 'consecutive Enter must not double blank lines',
    );
  });

  test('live toggles are independent, reversible and idempotent', () {
    var indent = false;
    var blank = false;
    final c = IndentingTextEditingController(
      autoIndent: () => indent,
      blankLineBetween: () => blank,
    );
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
      text: '甲\n乙',
      selection: TextSelection(baseOffset: 3, extentOffset: 1),
    );
    indent = true;
    c.refreshParagraphStyle();
    expect(c.text, '　　甲\n　　乙');
    expect(c.selection, const TextSelection(baseOffset: 7, extentOffset: 3));
    blank = true;
    c.refreshParagraphStyle();
    expect(c.text, '　　甲\n\n　　乙');
    final formatted = c.value;
    c.value = c.value;
    c.refreshParagraphStyle();
    expect(c.value, formatted);
    indent = false;
    c.refreshParagraphStyle();
    expect(c.text, '甲\n\n乙');
    blank = false;
    c.refreshParagraphStyle();
    expect(c.text, '甲\n乙');
    expect(c.selection, const TextSelection(baseOffset: 3, extentOffset: 1));
  });

  test('preference changes defer rewriting until IME commits', () {
    var indent = false;
    final c = IndentingTextEditingController(
      autoIndent: () => indent,
      blankLineBetween: () => false,
    );
    addTearDown(c.dispose);
    const draft = TextEditingValue(
      text: 'zhong',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    c.value = draft;
    indent = true;
    c.refreshParagraphStyle();
    expect(c.value, draft);
    c.value = const TextEditingValue(
      text: '中',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(c.text, '　　中');
  });

  test('IME value stays byte-for-byte intact until commit', () {
    final c = IndentingTextEditingController(
      autoIndent: () => true,
      blankLineBetween: () => true,
    );
    addTearDown(c.dispose);
    const composing = TextEditingValue(
      text: 'zhong',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    c.value = composing;
    expect(c.value, composing);
    c.value = const TextEditingValue(
      text: '中',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(c.text, '　　中');
    expect(c.selection.extentOffset, 3);
  });
}
