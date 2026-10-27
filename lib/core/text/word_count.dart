/// 字数口径（PLAN.md §3.2-1 / §8.3）。
///
/// 删除所有空白字符（空格、Tab、换行、NBSP、全角空格、BOM）后按 Unicode 码点计数；
/// 标点计入。显示：< 10000 → 「3,214 字」；≥ 10000 → 「38.6 万字」。
const Set<int> _ignoredWhitespace = <int>{
  0x0020, // space
  0x0009, // tab
  0x000A, // LF
  0x000B, // VT
  0x000C, // FF
  0x000D, // CR
  0x00A0, // NBSP
  0x1680, // ogham space mark
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
  0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
  0x3000, // 全角空格（首行缩进）
  0xFEFF, // BOM
};

int countWords(String text) {
  int n = 0;
  for (final int rune in text.runes) {
    if (!_ignoredWhitespace.contains(rune)) n++;
  }
  return n;
}

String formatWordCount(int n) {
  if (n < 10000) {
    return '${_groupThousands(n)} 字';
  }
  final double wan = n / 10000.0;
  return '${wan.toStringAsFixed(1)} 万字';
}

String _groupThousands(int n) {
  final String digits = n.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
