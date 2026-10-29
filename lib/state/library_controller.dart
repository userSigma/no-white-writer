import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import '../core/models.dart';
import '../core/storage/app_paths.dart';
import '../core/storage/book_store.dart';
import '../core/storage/chapter_store.dart';
import '../core/storage/library_store.dart';
import '../core/text/word_count.dart';
import 'library_operation_gate.dart';
import 'book_mutation_transaction.dart';
import 'book_structure_service.dart';
import 'settings_controller.dart';

enum LibrarySort { recent, title }

/// 书架与目录事务；所有书库写入经 [LibraryOperationGate] 串行，
/// 导出预约后拒绝后续写入，并在读取快照前等待既有写入结束。
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
  bool _disposed = false;
  final LibraryOperationGate _gate = LibraryOperationGate();
  late final BookMutationTransaction _transaction = BookMutationTransaction(
    bookStore: bookStore,
    findSummary: _find,
    saveSummary: _saveSummary,
    notifyChanged: _notify,
  );
  late final BookStructureService structure = BookStructureService(
    paths: paths,
    bookStore: bookStore,
    chapterStore: chapterStore,
    gate: _gate,
    transaction: _transaction,
  );
  bool get exporting => _gate.isExportReserved;

  /// 所有书库写入（含 [noteChapterSaved] 的摘要写盘）都从这里串行进入。
  Future<T> _mutate<T>(Future<T> Function() action) => _gate.write(action);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> beginExport() async {
    // 预约必须在等待之前生效：等待期间新到的写入在入口即被拒绝。
    _gate.reserveExport();
    _notify();
    try {
      await _gate.waitForWrites();
      if (_gate.isClosed) throw StateError('书库已关闭，不能再导出。');
    } catch (_) {
      endExport();
      rethrow;
    }
  }

  void endExport() {
    _gate.releaseExport();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _gate.close();
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
    _notify();
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
    _notify();
    try {
      _index = await libraryStore.loadOrRebuild(bookStore);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      _loaded = true;
      _notify();
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
    _notify();
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
    _notify();
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
    _notify();
  }

  Future<void> updateBookDetails(BookIndex book, String title, String notes) =>
      _mutate(() => _updateBookDetails(book, title, notes));

  Future<void> _updateBookDetails(
    BookIndex book,
    String title,
    String notes,
  ) async {
    final previous = _transaction.copy(book);
    final next = _transaction.copy(book)
      ..title = title.trim().isEmpty ? '未命名作品' : title.trim()
      ..notes = notes;
    try {
      await _transaction.commit(book, next);
    } catch (_) {
      // 信息编辑可补偿回滚；与跨卷目录提交不同，没有文件归属变化。
      try {
        await bookStore.save(previous);
        _transaction.apply(book, previous);
      } catch (_) {
        await _transaction.syncActual(book);
      }
      rethrow;
    }
  }

  /// 单章保存后刷新字数/时间，不重写 book.json（由 EditorController 负责）。
  /// 摘要写盘同样进入写屏障：导出预约会等它结束，预约后它也会被拒绝。
  Future<void> noteChapterSaved(BookIndex book) =>
      _mutate(() => _saveSummary(book));

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
    _notify();
  }

  Future<void> renameBook(BookSummary summary, String rawTitle) =>
      _mutate(() async {
        final title = rawTitle.trim();
        if (title.isEmpty || title == summary.title) return;
        final book = await bookStore.load(summary);
        await _updateBookDetails(book, title, book.notes);
      });

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
    _notify();
  }

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

  Set<String> get blockedBooks => _transaction.blockedBooks;
}
