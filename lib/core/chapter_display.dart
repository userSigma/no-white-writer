import 'chapter_numbering.dart';
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
        final int inVolume = v.chapters.indexWhere((c) => c.id == chapterId);
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
