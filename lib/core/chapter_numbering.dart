/// 卷级显示规则，不修改作者的原始章名或正文（PLAN.md §17.7）。
class ChapterNumbering {
  const ChapterNumbering({
    this.enabled = false,
    this.prefix = '第',
    this.suffix = '章',
    this.style = 'arabic',
    this.padding = 1,
    this.start = 1,
    this.step = 1,
  });

  final bool enabled;
  final String prefix;
  final String suffix;
  final String style;
  final int padding;
  final int start;
  final int step;

  static const int maxValue = 999999999;

  void validate(int count) {
    if (start < 0 ||
        start > maxValue ||
        step < 1 ||
        step > maxValue ||
        padding < 1 ||
        padding > 9 ||
        !['arabic', 'chinese'].contains(style) ||
        prefix.contains(RegExp(r'[\r\n]')) ||
        suffix.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException(
        '编号规则无效：起始值 0–999999999、步长 1–999999999、补零 1–9，前后缀须为单行。',
      );
    }
    if (count < 0 || (count > 0 && start + (count - 1) * step > maxValue)) {
      throw const FormatException('章节编号超出 999999999，请调整起始值或步长。');
    }
  }

  /// 章显示号。规则本身（范围/单行/样式）由保存对话框与严格导出读取器经
  /// [validate] 校验，这里不逐调用重跑；只保留随章数变化的边界检查：
  /// 负索引与序列溢出（numbering_test 钉死的行为）。
  String label(int index) {
    if (index < 0) throw const FormatException('章节不在此卷中。');
    final int value = start + index * step;
    if (value > maxValue) {
      throw const FormatException('章节编号超出 999999999，请调整起始值或步长。');
    }
    final String digits = style == 'chinese'
        ? _chinese(value)
        : '$value'.padLeft(padding, '0');
    return '$prefix$digits$suffix';
  }

  static String _chinese(int value) {
    if (value == 0) return '零';
    const String digits = '零一二三四五六七八九';
    const List<String> smallUnits = ['', '十', '百', '千'];
    const List<String> bigUnits = ['', '万', '亿'];
    final List<int> groups = [];
    while (value > 0) {
      groups.add(value % 10000);
      value ~/= 10000;
    }
    String result = '';
    bool gap = false;
    for (int g = groups.length - 1; g >= 0; g--) {
      final int section = groups[g];
      if (section == 0) {
        gap = result.isNotEmpty;
        continue;
      }
      if (result.isNotEmpty && (gap || section < 1000)) result += '零';
      gap = false;
      String part = '';
      bool zero = false;
      int divisor = 1000;
      for (int p = 3; p >= 0; p--, divisor ~/= 10) {
        final int digit = section ~/ divisor % 10;
        if (digit == 0) {
          zero = part.isNotEmpty;
          continue;
        }
        if (zero) part += '零';
        zero = false;
        part += '${digits[digit]}${smallUnits[p]}';
      }
      result += '$part${bigUnits[g]}';
    }
    return result.startsWith('一十') ? result.substring(1) : result;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'prefix': prefix,
    'suffix': suffix,
    'style': style,
    'padding': padding,
    'start': start,
    'step': step,
  };

  /// 字段缺失或类型不符时回退默认值：损坏的编号配置不应让整本书打不开。
  factory ChapterNumbering.fromJson(Map<String, dynamic> json) {
    final Object? enabled = json['enabled'];
    final Object? prefix = json['prefix'];
    final Object? suffix = json['suffix'];
    final Object? style = json['style'];
    return ChapterNumbering(
      enabled: enabled is bool ? enabled : false,
      prefix: prefix is String ? prefix : '第',
      suffix: suffix is String ? suffix : '章',
      style: style is String ? style : 'arabic',
      padding: (json['padding'] as num?)?.toInt() ?? 1,
      start: (json['start'] as num?)?.toInt() ?? 1,
      step: (json['step'] as num?)?.toInt() ?? 1,
    );
  }
}
