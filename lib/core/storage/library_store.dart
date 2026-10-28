import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import '../models.dart';
import '../platform/path_utils.dart';
import 'app_paths.dart';
import 'atomic_file_writer.dart';
import 'book_store.dart';
import 'corrupt_file.dart';

/// `library.json` 的读写与按作品目录重建（PLAN.md §4.1 / §4.7 / §4.8）。
class LibraryStore {
  LibraryStore(this._paths, this._writer);

  final AppPaths _paths;
  final AtomicFileWriter _writer;

  Future<LibraryIndex> load() async {
    final File file = _paths.libraryFile;
    if (!await file.exists()) return LibraryIndex();
    try {
      final String raw = await file.readAsString();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('library.json 顶层不是对象');
      }
      final Object? entries = decoded['books'];
      if (entries is List<dynamic> &&
          entries.any((Object? entry) => entry is! Map<String, dynamic>)) {
        throw const FormatException('library.json 的 books 含非法条目');
      }
      return LibraryIndex.fromJson(decoded);
    } catch (error) {
      await keepCorrupt(file, 'library');
      AppLogger.instance.error('library.load.failed', <String, Object?>{
        'error': '$error',
      });
      return LibraryIndex();
    }
  }

  Future<LibraryIndex> loadOrRebuild(BookStore bookStore) async {
    final LibraryIndex index = await load();
    final Set<String> directoryIds = await _bookDirectoryIds();
    final Set<String> summaryIds = index.books
        .map((BookSummary book) => book.id)
        .toSet();
    if (summaryIds.length == index.books.length &&
        summaryIds.length == directoryIds.length &&
        summaryIds.containsAll(directoryIds)) {
      return index;
    }

    if (await _paths.libraryFile.exists()) {
      await keepCorrupt(_paths.libraryFile, 'library');
    }
    final Map<String, BookSummary> previous = <String, BookSummary>{
      for (final BookSummary book in index.books) book.id: book,
    };
    final List<String> ids = directoryIds.toList()..sort();
    final List<BookSummary> summaries = <BookSummary>[];
    final DateTime now = DateTime.now();
    for (final String id in ids) {
      final BookSummary? old = previous[id];
      final BookSummary fallback = BookSummary(
        id: id,
        title: old?.title ?? '未命名作品',
        createdAt: old?.createdAt ?? now,
        updatedAt: old?.updatedAt ?? now,
        coverSeed: old?.coverSeed ?? 0,
        lastOpenedChapterId: old?.lastOpenedChapterId,
      );
      final BookIndex book = await bookStore.load(fallback);
      summaries.add(
        BookSummary(
          id: book.id,
          title: book.title,
          createdAt: fallback.createdAt,
          updatedAt: fallback.updatedAt,
          coverSeed: old?.coverSeed ?? book.title.hashCode,
          lastOpenedChapterId: fallback.lastOpenedChapterId,
          volumeCount: book.volumes.length,
          chapterCount: book.allChapters.length,
          wordCount: book.totalWordCount,
        ),
      );
    }
    final LibraryIndex rebuilt = LibraryIndex(books: summaries);
    await save(rebuilt);
    AppLogger.instance.warn('library.rebuilt', <String, Object?>{
      'books': summaries.length,
    });
    return rebuilt;
  }

  Future<Set<String>> _bookDirectoryIds() async {
    final Directory dir = Directory(_paths.booksDir);
    if (!await dir.exists()) return <String>{};
    return dir
        .list()
        .where((FileSystemEntity entity) => entity is Directory)
        .map((FileSystemEntity entity) => fileNameOf(entity.path))
        .toSet();
  }

  Future<void> save(LibraryIndex index) async {
    final String raw = const JsonEncoder.withIndent('  ')
        .convert(index.toJson());
    await _writer.writeAtomically(_paths.libraryFile, raw);
  }
}

/// `settings.json` 的读写；字段缺失一律用默认值（PLAN.md §4.1）。
class SettingsStore {
  SettingsStore(this._paths, this._writer);

  final AppPaths _paths;
  final AtomicFileWriter _writer;

  Future<AppSettings> load() async {
    final File file = _paths.settingsFile;
    if (!await file.exists()) return AppSettings();
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('settings.json 顶层不是对象');
      }
      return AppSettings.fromJson(decoded);
    } catch (error) {
      AppLogger.instance.error('settings.load.failed', <String, Object?>{
        'error': '$error',
      });
      return AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final String raw = const JsonEncoder.withIndent('  ')
        .convert(settings.toJson());
    await _writer.writeAtomically(_paths.settingsFile, raw);
  }
}
