import 'models.dart';

String displayVolumeTitle(Volume volume, {String untitledLabel = '未命名卷'}) =>
    volume.title.trim().isEmpty ? untitledLabel : volume.title.trim();

/// 两层编号解析：按卷级模式取生效规则，不编号时返回 `null`。
///
/// - 跟随全局：全局配置开启 → 全局规则；关闭 → 不编号；
/// - 卷内独立：本卷规则开启 → 本卷规则；关闭 → 不编号；
/// - 不编号：`null`。
///
/// 列表、正文上方、窗口标题、导出文件名都经此函数取号，保证四处一致。
ChapterNumbering? effectiveChapterNumbering(BookIndex book, Volume volume) {
  switch (volume.numberingMode) {
    case VolumeNumberingMode.none:
      return null;
    case VolumeNumberingMode.independent:
      return volume.numbering.enabled ? volume.numbering : null;
    case VolumeNumberingMode.followGlobal:
      return book.globalNumbering.enabled ? book.globalNumbering : null;
  }
}

/// 章的取号索引：卷内独立 → 卷内序号；跟随全局 → 参与全局编号的卷
/// （按卷序）合并后的全书连续序号；不编号或找不到 → -1。
int chapterNumberIndex(BookIndex book, Volume volume, String chapterId) {
  switch (volume.numberingMode) {
    case VolumeNumberingMode.independent:
      return volume.chapters.indexWhere((c) => c.id == chapterId);
    case VolumeNumberingMode.followGlobal:
      int index = 0;
      for (final Volume v in book.volumes) {
        if (v.numberingMode != VolumeNumberingMode.followGlobal) continue;
        final int inVolume = v.chapters.indexWhere(
          (c) => c.id == chapterId,
        );
        if (inVolume >= 0) return index + inVolume;
        index += v.chapters.length;
      }
      return -1;
    case VolumeNumberingMode.none:
      return -1;
  }
}

/// 章的编号标签（如「第 3 章」）；不编号时返回 `null`。
/// 列表、正文上方、窗口标题、导出文件名共用，保证四处一致。
String? chapterNumberLabel(BookIndex book, Volume volume, String chapterId) {
  final ChapterNumbering? rule = effectiveChapterNumbering(book, volume);
  if (rule == null) return null;
  return rule.label(chapterNumberIndex(book, volume, chapterId));
}

/// 「跟随全局编号」卷的章数合计（全书连续编号的取号总数）。
int globalNumberingChapterCount(BookIndex book) => book.volumes
    .where((Volume v) => v.numberingMode == VolumeNumberingMode.followGlobal)
    .fold(0, (int sum, Volume v) => sum + v.chapters.length);

String displayChapterTitle(
  BookIndex book,
  Volume volume,
  ChapterMeta chapter, {
  String? rawTitle,
  String untitledLabel = '未命名章节',
}) {
  final String title = (rawTitle ?? chapter.title).trim();
  final String? label = chapterNumberLabel(book, volume, chapter.id);
  if (label == null) {
    return title.isEmpty ? untitledLabel : title;
  }
  return title.isEmpty ? label : '$label $title';
}

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
