import 'dart:io';

import '../core/chapter_numbering.dart';
import '../core/ids.dart';
import '../core/models.dart';
import '../core/storage/app_paths.dart';
import '../core/storage/book_store.dart';
import '../core/storage/chapter_store.dart';
import 'book_mutation_transaction.dart';
import 'library_operation_gate.dart';

/// Book-local volume/chapter algorithms. Every entry uses the same operation
/// gate as the library controller, including delta calculations and snapshot reads.
class BookStructureService {
  BookStructureService({
    required this.paths,
    required this.bookStore,
    required this.chapterStore,
    required this.gate,
    required this.transaction,
  });

  final AppPaths paths;
  final BookStore bookStore;
  final ChapterStore chapterStore;
  final LibraryOperationGate gate;
  final BookMutationTransaction transaction;

  Future<T> _mutate<T>(Future<T> Function() action) => gate.write(action);

  Future<ChapterMeta> appendChapter(
    BookIndex book,
    Volume volume, {
    String? title,
  }) => _mutate(() => _appendChapter(book, volume, title: title));

  Future<ChapterMeta> _appendChapter(
    BookIndex book,
    Volume volume, {
    String? title,
  }) async {
    final next = transaction.copy(book);
    final target = next.volumes.where((v) => v.id == volume.id).firstOrNull;
    if (target == null) throw StateError('目标卷不属于当前作品');
    final ChapterNumbering? rule = effectiveChapterNumbering(next, target);
    if (rule != null) {
      rule.validate(_numberedChapterCount(next, target) + 1);
    }
    final chapter = ChapterMeta(
      id: newId(),
      title: title?.trim().isNotEmpty == true ? title!.trim() : '未命名章节',
      order: target.chapters.length,
    );
    target.chapters.add(chapter);
    BookMutationTransaction.normalize(next);
    await chapterStore.writeText(book.id, target.id, chapter.id, '');
    try {
      await transaction.commit(book, next);
    } catch (_) {
      if (book.chapterById(chapter.id) == null &&
          !transaction.blockedBooks.contains(book.id)) {
        await chapterStore.deleteToTrash(
          book.id,
          target.id,
          chapter.id,
          title: chapter.title,
        );
      }
      rethrow;
    }
    return book.chapterById(chapter.id)!;
  }

  Future<Volume> appendVolume(BookIndex book, {String? title}) =>
      _mutate(() => _appendVolume(book, title: title));

  Future<Volume> _appendVolume(BookIndex book, {String? title}) async {
    final next = transaction.copy(book);
    final volume = Volume(
      id: newId(),
      title: title?.trim().isNotEmpty == true ? title!.trim() : '未命名卷',
      order: book.volumes.length,
    );
    next.volumes.add(volume);
    BookMutationTransaction.normalize(next);
    await transaction.commit(book, next);
    return book.volumes.firstWhere((v) => v.id == volume.id);
  }

  Future<void> setNumbering(
    BookIndex book,
    Volume volume,
    ChapterNumbering rule,
  ) => _mutate(() => _setNumbering(book, volume, rule));

  Future<void> _setNumbering(
    BookIndex book,
    Volume volume,
    ChapterNumbering rule,
  ) async {
    rule.validate(volume.chapters.length);
    final next = transaction.copy(book);
    final target = next.volumes.firstWhere((v) => v.id == volume.id);
    target.numbering = rule;
    // legacy 调用方只设规则、不设两层模式：启用规则即进入卷内独立编号，
    // 关闭后回到跟随全局（显式「不编号」的卷保持不编号），
    // 使旧接口与新两层编号行为保持一致。
    target.numberingMode = rule.enabled
        ? VolumeNumberingMode.independent
        : target.numberingMode == VolumeNumberingMode.none
        ? VolumeNumberingMode.none
        : VolumeNumberingMode.followGlobal;
    await transaction.commit(book, next);
  }

  /// 设置卷级编号模式（两层编号的卷层）。
  ///
  /// 进入独立编号时卷规则必须对现有章数成立；legacy 的
  /// `numbering.enabled` 与模式保持镜像（independent ⇔ true），
  /// 旧版本程序读同一份数据时行为仍然自洽。
  Future<void> setVolumeNumberingMode(
    BookIndex book,
    Volume volume,
    VolumeNumberingMode mode,
  ) => _mutate(() => _setVolumeNumberingMode(book, volume, mode));

  Future<void> _setVolumeNumberingMode(
    BookIndex book,
    Volume volume,
    VolumeNumberingMode mode,
  ) async {
    final next = transaction.copy(book);
    final target = next.volumes.firstWhere((v) => v.id == volume.id);
    switch (mode) {
      case VolumeNumberingMode.independent:
        target.numbering.validate(target.chapters.length);
        target.numbering = _withEnabled(target.numbering, true);
      case VolumeNumberingMode.followGlobal:
        final ChapterNumbering? global = effectiveChapterNumbering(
          next,
          target,
        );
        if (global != null) global.validate(globalNumberingChapterCount(next));
        target.numbering = _withEnabled(target.numbering, false);
      case VolumeNumberingMode.none:
        target.numbering = _withEnabled(target.numbering, false);
    }
    target.numberingMode = mode;
    await transaction.commit(book, next);
  }

  /// 取号计数：卷内独立 → 本卷章数；跟随全局 → 参与全局编号的章总数。
  /// （新章校验在此基础上 +1。）
  static int _numberedChapterCount(BookIndex book, Volume volume) =>
      volume.numberingMode == VolumeNumberingMode.independent
      ? volume.chapters.length
      : globalNumberingChapterCount(book);

  static ChapterNumbering _withEnabled(ChapterNumbering rule, bool enabled) =>
      ChapterNumbering(
        enabled: enabled,
        prefix: rule.prefix,
        suffix: rule.suffix,
        style: rule.style,
        padding: rule.padding,
        start: rule.start,
        step: rule.step,
      );

  /// 设置书籍级「全局自动章节序号」配置（两层编号的全局层）。
  ///
  /// 校验口径与解析一致：跟随全局的卷合并使用全书连续序号，
  /// 因此规则必须对参与全局编号的章总数成立。
  Future<void> setGlobalNumbering(BookIndex book, ChapterNumbering rule) =>
      _mutate(() => _setGlobalNumbering(book, rule));

  Future<void> _setGlobalNumbering(
    BookIndex book,
    ChapterNumbering rule,
  ) async {
    if (rule.enabled) {
      rule.validate(globalNumberingChapterCount(book));
    }
    final next = transaction.copy(book)..globalNumbering = rule;
    await transaction.commit(book, next);
  }

  Future<void> relocateChapter(
    BookIndex book,
    String chapterId,
    String targetId,
    int insertionIndex,
  ) => _mutate(
    () => _relocateChapter(book, chapterId, targetId, insertionIndex),
  );

  Future<void> _relocateChapter(
    BookIndex book,
    String chapterId,
    String targetId,
    int insertionIndex,
  ) async {
    final next = transaction.copy(book);
    final source = next.volumeOfChapter(chapterId);
    final target = next.volumes.where((v) => v.id == targetId).firstOrNull;
    if (source == null || target == null) throw StateError('只允许同一作品内移动章节');
    RangeError.checkValueInInterval(
      insertionIndex,
      0,
      target.chapters.length,
      'insertionIndex',
    );
    final chapter = next.chapterById(chapterId)!;
    final oldIndex = source.chapters.indexOf(chapter);
    int index = insertionIndex;
    if (source.id == target.id && index > oldIndex) index--;
    if (source.id == target.id && index == oldIndex) return;
    source.chapters.remove(chapter);
    target.chapters.insert(index, chapter);
    // 校验口径与取号一致：移动后目标卷的编号范围必须仍合法。
    // （卷内独立 → 目标卷章数；跟随全局 → 参与全局编号的章总数。）
    final ChapterNumbering? targetRule = effectiveChapterNumbering(
      next,
      target,
    );
    if (targetRule != null) {
      targetRule.validate(_numberedChapterCount(next, target));
    }
    BookMutationTransaction.normalize(next);
    if (source.id == target.id) {
      await transaction.commit(book, next);
      return;
    }
    try {
      await bookStore.moves.move(
        bookId: book.id,
        sourceId: source.id,
        targetId: target.id,
        chapterId: chapterId,
        commitIndex: () async {
          await bookStore.save(next);
          transaction.apply(book, next);
        },
        commitSummary: () => transaction.saveSummary(book),
      );
    } catch (_) {
      await transaction.syncActual(book);
      rethrow;
    }
    transaction.notifyChanged();
  }

  Future<void> reorderVolume(
    BookIndex book,
    String volumeId,
    int insertionIndex,
  ) => _mutate(() => _reorderVolume(book, volumeId, insertionIndex));

  Future<void> _reorderVolume(
    BookIndex book,
    String volumeId,
    int insertionIndex,
  ) async {
    RangeError.checkValueInInterval(
      insertionIndex,
      0,
      book.volumes.length,
      'insertionIndex',
    );
    final next = transaction.copy(book);
    final from = next.volumes.indexWhere((v) => v.id == volumeId);
    if (from < 0) throw StateError('卷不属于当前作品');
    final index = insertionIndex > from ? insertionIndex - 1 : insertionIndex;
    if (index == from) return;
    next.volumes.insert(index, next.volumes.removeAt(from));
    BookMutationTransaction.normalize(next);
    await transaction.commit(book, next);
  }

  Future<void> deleteChapter(
    BookIndex book,
    Volume volume,
    ChapterMeta chapter,
  ) => _mutate(() => _deleteChapter(book, volume, chapter));

  Future<void> _deleteChapter(
    BookIndex book,
    Volume volume,
    ChapterMeta chapter,
  ) async {
    final next = transaction.copy(book);
    next.volumes
        .firstWhere((v) => v.id == volume.id)
        .chapters
        .removeWhere((c) => c.id == chapter.id);
    BookMutationTransaction.normalize(next);
    // 索引提交前不移除正文；摘要失败时同样遵从真实的已提交索引。
    try {
      await transaction.commit(book, next);
    } finally {
      if (book.chapterById(chapter.id) == null &&
          !transaction.blockedBooks.contains(book.id)) {
        await chapterStore.deleteToTrash(
          book.id,
          volume.id,
          chapter.id,
          title: chapter.title,
        );
      }
    }
  }

  Future<void> deleteVolume(BookIndex book, Volume volume) =>
      _mutate(() => _deleteVolume(book, volume));

  Future<void> _deleteVolume(BookIndex book, Volume volume) async {
    final removed = List<ChapterMeta>.of(volume.chapters);
    final next = transaction.copy(book)
      ..volumes.removeWhere((v) => v.id == volume.id);
    BookMutationTransaction.normalize(next);
    try {
      await transaction.commit(book, next);
    } finally {
      if (!book.volumes.any((v) => v.id == volume.id) &&
          !transaction.blockedBooks.contains(book.id)) {
        for (final c in removed) {
          await chapterStore.deleteToTrash(
            book.id,
            volume.id,
            c.id,
            title: c.title,
          );
        }
        final dir = Directory(paths.volumeDir(book.id, volume.id));
        if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
      }
    }
  }

  Future<void> renameVolume(BookIndex book, Volume volume, String title) =>
      _mutate(() => _renameVolume(book, volume, title));

  Future<void> _renameVolume(
    BookIndex book,
    Volume volume,
    String title,
  ) async {
    final name = title.trim();
    if (name == volume.title) return;
    final next = transaction.copy(book);
    next.volumes.firstWhere((v) => v.id == volume.id).title = name;
    await transaction.commit(book, next);
  }

  Future<void> renameChapter(
    BookIndex book,
    ChapterMeta chapter,
    String title,
  ) => _mutate(() => _renameChapter(book, chapter, title));

  Future<void> _renameChapter(
    BookIndex book,
    ChapterMeta chapter,
    String title,
  ) async {
    final name = title.trim();
    if (name == chapter.title) return;
    final next = transaction.copy(book);
    next.chapterById(chapter.id)!.title = name;
    await transaction.commit(book, next);
  }
}
