import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/text/word_count.dart';

void main() {
  group('countWords', () {
    test('空白全部忽略，标点计入', () {
      expect(countWords('你好，世界'), 5);
      expect(countWords('a b\nc\t d'), 4);
      expect(countWords('　　'), 0);
      expect(countWords('\uFEFF\u00A0\u3000'), 0);
    });

    test('按码点计数（emoji/扩展区算一个字）', () {
      expect(countWords('𠀀'), 1);
      expect(countWords('文😀字'), 3);
    });
  });

  group('formatWordCount', () {
    test('一万以下千分位', () {
      expect(formatWordCount(0), '0 字');
      expect(formatWordCount(3214), '3,214 字');
      expect(formatWordCount(9999), '9,999 字');
    });

    test('一万以上用万字', () {
      expect(formatWordCount(10000), '1.0 万字');
      expect(formatWordCount(386123), '38.6 万字');
    });
  });
}
