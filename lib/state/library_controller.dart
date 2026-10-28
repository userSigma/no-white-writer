import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import '../core/chapter_numbering.dart';
import '../core/models.dart';
import '../core/storage/app_paths.dart';
import '../core/storage/book_store.dart';
import '../core/storage/chapter_store.dart';
import '../core/storage/library_store.dart';
import '../core/text/word_count.dart';
import 'settings_controller.dart';

enum LibrarySort { recent, title }

/// 书架与目录事务；所有磁盘变更入口计数，导出预约后拒绝后续写入。
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.paths,
    required this.libraryStore,
    required this.bookStore,
    required this.chapterStore,
    required this.settings,
  });

  final AppPaths paths;
  final LibraryStore libraryStore;
  final BookStore bookStore;
  final ChapterStore chapterStore;
  final SettingsController settings;

  LibraryIndex _index = LibraryIndex();
  bool loading = true;
  bool _loaded = false;
  String? error;
  LibrarySort sort = LibrarySort.recent;
  bool _exporting = false;
  bool _disposed = false;
  int _activeWrites = 0;
  Completer<void>? _writesDone;
  bool get exporting => _exporting;

  Future<T> _mutate<T>(Future<T> Function() action) async {
    if (_exporting || _disposed) {
      throw StateError('正在导出，暂不能修改作品。');
    }
    _activeWrites++;
    try {
      return await action();
    } finally {
      _activeWrites--;
      if (_activeWrites == 0) {
        final done = _writesDone;
        _writesDone = null;
        done?.complete();
      }
    }
  }

  Future<void> beginExport() async {
    if (_exporting || _disposed) throw StateError('正在导出，请稍候。');
    // Reserve before waiting: later writes cannot overtake this snapshot.
    _exporting = true;
    notifyListeners();
    if (_activeWrites > 0) {
      _writesDone ??= Completer<void>();
      await _writesDone!.future;
    }
  }

  void endExport() {
    _exporting = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Set<String> expandedVolumesOf(BookIndex book) =>
      settings.expandedOf(book.id).toSet();

  Future<void> setVolumeExpanded(
    BookIndex book,
    String volumeId,
    bool expanded,
  ) => _mutate(() => _setVolumeExpanded(book, volumeId, expanded));

  Future<void> _setVolumeExpanded(
    BookIndex book,
    String volumeId,
    bool expanded,
  ) async {
    final ids = expandedVolumesOf(book);
    if (expanded) {
      ids.add(volumeId);
    } else {
      ids.remove(volumeId);
    }
    settings.rememberExpanded(book.id, ids.toList());
    await settings.flush();
    notifyListeners();
  }

  List<BookSummary> get books {
    final List<BookSummary> list = List<BookSummary>.of(_index.books);
    if (sort == LibrarySort.title) {
      list.sort((BookSummary a, BookSummary b) => a.title.compareTo(b.title));
    } else {
      list.sort(
        (BookSummary a, BookSummary b) => b.updatedAt.compareTo(a.updatedAt),
      );
    }
    return list;
  }

  bool get isEmpty => _index.books.isEmpty;

  Future<void> load() => _mutate(_load);

  Future<void> _load() async {
    loading = true;
    notifyListeners();
    try {
      _index = await libraryStore.loadOrRebuild(bookStore);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// 只在还没加载过时读盘；页面 initState 用它，避免每次进书架都重读一遍。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  void setSort(LibrarySort next) {
    if (sort == next) return;
    sort = next;
    notifyListeners();
  }

  Future<BookSummary> createBook(String rawTitle, {String notes = ''}) =>
      _mutate(() => _createBook(rawTitle, notes: notes));

  Future<BookSummary> _createBook(String rawTitle, {String notes = ''}) async {
    final String title = rawTitle.trim().isEmpty ? '未命名作品' : rawTitle.trim();
    final DateTime now = DateTime.now();
    final String bookId = newId();
    final BookIndex book = BookIndex(id: bookId, title: title, notes: notes);
    final Volume volume = Volume(id: newId(), title: '未命名卷', order: 0);
    final ChapterMeta chapter = ChapterMeta(
      id: newId(),
      title: '未命名章节',
      order: 0,
    );
    volume.chapters.add(chapter);
    book.volumes.add(volume);
    final BookSummary summary = BookSummary(
      id: bookId,
      title: title,
      createdAt: now,
      updatedAt: now,
      coverSeed: title.hashCode,
      volumeCount: 1,
      chapterCount: 1,
      wordCount: 0,
    );
    try {
      await chapterStore.writeText(bookId, volume.id, chapter.id, '');
      await bookStore.save(book);
      _index.books.add(summary);
      await libraryStore.save(_index);
    } catch (_) {
      _index.books.removeWhere((BookSummary b) => b.id == bookId);
      // 只处理本次全新 ID 的半成品，移入回收站而不永久删除。
      try {
        await bookStore.moveToTrash(bookId);
      } catch (_) {}
      rethrow;
    }
    notifyListeners();
    return summary;
  }

  Future<BookIndex> readBookDetails(BookSummary summary) =>
      _mutate(() => bookStore.load(summary));

  Future<BookIndex> openBook(BookSummary summary) =>
      _mutate(() => _openBook(summary));

  Future<BookIndex> _openBook(BookSummary summary) async {
    settings.setLastOpenedBook(summary.id);
    return bookStore.load(summary);
  }

  String? lastChapterId(String bookId) => _find(bookId)?.lastOpenedChapterId;

  Future<void> rememberChapter(String bookId, String? chapterId) =>
      _mutate(() => _rememberChapter(bookId, chapterId));

  Future<void> _rememberChapter(String bookId, String? chapterId) async {
    final BookSummary? summary = _find(bookId);
    if (summary == null || summary.lastOpenedChapterId == chapterId) return;
    final String? previous = summary.lastOpenedChapterId;
    summary.lastOpenedChapterId = chapterId;
    try {
      await libraryStore.save(_index);
    } catch (_) {
      summary.lastOpenedChapterId = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> updateBookDetails(BookIndex book, String title, String notes) =>
      _mutate(() => _updateBookDetails(book, title, notes));

  Future<void> _updateBookDetails(
    BookIndex book,
    String title,
    String notes,
  ) async {
    final previous = _copy(book);
    final next = _copy(book)
      ..title = title.trim().isEmpty ? '未命名作品' : title.trim()
      ..notes = notes;
    try {
      await _commit(book, next);
    } catch (_) {
      // 信息编辑可补偿回滚；与跨卷目录提交不同，没有文件归属变化。
      try {
        await bookStore.save(previous);
        _apply(book, previous);
      } catch (_) {
        await _syncActual(book);
      }
      rethrow;
    }
  }

  /// 把书内改动（卷/章标题、顺序、增删）落盘，并同步书架摘要。
  Future<void> saveBook(BookIndex book) => _mutate(() => _saveBook(book));

  Future<void> _saveBook(BookIndex book) async {
    await bookStore.save(book);
    await _saveSummary(book);
  }

  /// 单章保存后刷新字数/时间，不重写 book.json（由 EditorController 负责）。
  Future<void> noteChapterSaved(BookIndex book) => _saveSummary(book);

  Future<void> _saveSummary(BookIndex book) async {
    final BookSummary? summary = _find(book.id);
    if (summary != null) {
      final BookSummary previous = BookSummary.fromJson(summary.toJson());
      summary
        ..title = book.title
        ..volumeCount = book.volumes.length
        ..chapterCount = book.allChapters.length
        ..wordCount = book.totalWordCount
        ..updatedAt = DateTime.now();
      try {
        await libraryStore.save(_index);
      } catch (_) {
        summary
          ..title = previous.title
          ..volumeCount = previous.volumeCount
          ..chapterCount = previous.chapterCount
          ..wordCount = previous.wordCount
          ..updatedAt = previous.updatedAt;
        rethrow;
      }
    }
    notifyListeners();
  }

  Future<void> renameBook(BookSummary summary, String rawTitle) async {
    final title = rawTitle.trim();
    if (title.isEmpty || title == summary.title) return;
    final book = await _mutate(() => bookStore.load(summary));
    await updateBookDetails(book, title, book.notes);
  }

  Future<void> deleteBook(BookSummary summary) =>
      _mutate(() => _deleteBook(summary));

  Future<void> _deleteBook(BookSummary summary) async {
    final original = Directory(paths.bookDir(summary.id));
    if (!await original.exists()) {
      throw FileSystemException('作品目录缺失，未移除书架卡片', original.path);
    }
    final previous = List<BookSummary>.of(_index.books);
    final trash = await bookStore.moveToTrash(summary.id);
    try {
      _index.books.removeWhere((b) => b.id == summary.id);
      await libraryStore.save(_index);
    } catch (error) {
      _index.books
        ..clear()
        ..addAll(previous);
      try {
        if (await original.exists()) {
          throw FileSystemException('原目录已存在，保留回收站副本', original.path);
        }
        await Directory(trash).rename(original.path);
      } catch (restore) {
        throw FileSystemException(
          '删除失败：$error；恢复目录失败：$restore。正文仍保留于回收站',
          trash,
        );
      }
      rethrow;
    }
    if (settings.settings.lastOpenedBookId == summary.id) {
      settings.setLastOpenedBook(null);
    }
    notifyListeners();
  }

  int wordCountOf(ChapterMeta chapter) => chapter.wordCount;

  String statsLine(BookSummary summary) {
    final String words = formatWordCount(summary.wordCount);
    return '${summary.volumeCount} 卷 · ${summary.chapterCount} 章 · $words';
  }

  BookSummary? _find(String bookId) {
    for (final BookSummary b in _index.books) {
      if (b.id == bookId) return b;
    }
    return null;
  }

  final Set<String> blockedBooks = <String>{};

  BookIndex _copy(BookIndex book) => BookIndex.fromJson(book.toJson());

  /// 先写快照，提交后才更新可见对象；失败读取真实落盘状态，绝不假回滚。
  Future<void> _commit(BookIndex book, BookIndex next) async {
    try {
      await bookStore.save(next);
      _apply(book, next);
      await _saveSummary(book);
    } catch (_) {
      await _syncActual(book);
      rethrow;
    }
  }

  Future<void> _syncActual(BookIndex book) async {
    try {
      final summary = _find(book.id);
      if (summary == null) throw StateError('作品摘要缺失');
      _apply(book, await bookStore.load(summary));
      blockedBooks.remove(book.id);
    } catch (_) {
      blockedBooks.add(book.id);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 保留对象身份，编辑器仍引用同一个章对象；跨卷绑定由编辑门禁重新定位。
  void _apply(BookIndex book, BookIndex next) {
    final volumes = {for (final v in book.volumes) v.id: v};
    final chapters = {for (final c in book.allChapters) c.id: c};
    book
      ..title = next.title
      ..notes = next.notes
      ..globalNumbering = next.globalNumbering;
    final ordered = <Volume>[];
    for (final v in next.volumes) {
      final current = volumes[v.id] ?? v;
      final list = <ChapterMeta>[];
      for (final c in v.chapters) {
        final existing = chapters[c.id] ?? c;
        existing
          ..title = c.title
          ..order = c.order
          ..wordCount = c.wordCount
          ..updatedAt = c.updatedAt;
        list.add(existing);
      }
      current
        ..title = v.title
        ..order = v.order
        ..numbering = v.numbering
        ..numberingMode = v.numberingMode;
      current.chapters
        ..clear()
        ..addAll(list);
      ordered.add(current);
    }
    book.volumes
      ..clear()
      ..addAll(ordered);
    notifyListeners();
  }

  static void _normalize(BookIndex book) {
    for (int v = 0; v < book.volumes.length; v++) {
      book.volumes[v].order = v;
      for (int c = 0; c < book.volumes[v].chapters.length; c++) {
        book.volumes[v].chapters[c].order = c;
      }
    }
  }

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
    final next = _copy(book);
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
    _normalize(next);
    await chapterStore.writeText(book.id, target.id, chapter.id, '');
    try {
      await _commit(book, next);
    } catch (_) {
      if (book.chapterById(chapter.id) == null &&
          !blockedBooks.contains(book.id)) {
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
    final next = _copy(book);
    final volume = Volume(
      id: newId(),
      title: title?.trim().isNotEmpty == true ? title!.trim() : '未命名卷',
      order: book.volumes.length,
    );
    next.volumes.add(volume);
    _normalize(next);
    await _commit(book, next);
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
    final next = _copy(book);
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
    await _commit(book, next);
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
    final next = _copy(book);
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
    await _commit(book, next);
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
    final next = _copy(book)..globalNumbering = rule;
    await _commit(book, next);
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
    final next = _copy(book);
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
    _normalize(next);
    if (source.id == target.id) {
      await _commit(book, next);
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
          _apply(book, next);
        },
        commitSummary: () => _saveSummary(book),
      );
    } catch (_) {
      await _syncActual(book);
      rethrow;
    }
    notifyListeners();
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
    final next = _copy(book);
    final from = next.volumes.indexWhere((v) => v.id == volumeId);
    if (from < 0) throw StateError('卷不属于当前作品');
    final index = insertionIndex > from ? insertionIndex - 1 : insertionIndex;
    if (index == from) return;
    next.volumes.insert(index, next.volumes.removeAt(from));
    _normalize(next);
    await _commit(book, next);
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
    final next = _copy(book);
    next.volumes
        .firstWhere((v) => v.id == volume.id)
        .chapters
        .removeWhere((c) => c.id == chapter.id);
    _normalize(next);
    // 索引提交前不移除正文；摘要失败时同样遵从真实的已提交索引。
    try {
      await _commit(book, next);
    } finally {
      if (book.chapterById(chapter.id) == null &&
          !blockedBooks.contains(book.id)) {
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
    final next = _copy(book)..volumes.removeWhere((v) => v.id == volume.id);
    _normalize(next);
    try {
      await _commit(book, next);
    } finally {
      if (!book.volumes.any((v) => v.id == volume.id) &&
          !blockedBooks.contains(book.id)) {
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

  Future<void> moveChapter(
    BookIndex book,
    Volume volume,
    ChapterMeta chapter,
    int delta,
  ) async {
    final from = volume.chapters.indexWhere((c) => c.id == chapter.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= volume.chapters.length) return;
    await relocateChapter(book, chapter.id, volume.id, to > from ? to + 1 : to);
  }

  Future<void> moveVolume(BookIndex book, Volume volume, int delta) async {
    final from = book.volumes.indexWhere((v) => v.id == volume.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= book.volumes.length) return;
    await reorderVolume(book, volume.id, to > from ? to + 1 : to);
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
    final next = _copy(book);
    next.volumes.firstWhere((v) => v.id == volume.id).title = name;
    await _commit(book, next);
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
    final next = _copy(book);
    next.chapterById(chapter.id)!.title = name;
    await _commit(book, next);
  }
}
