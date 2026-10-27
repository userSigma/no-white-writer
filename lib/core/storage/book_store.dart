import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import '../models.dart';
import '../platform/path_utils.dart';
import '../text/word_count.dart';
import 'app_paths.dart';
import 'atomic_file_writer.dart';
import 'chapter_store.dart';
import 'chapter_move_store.dart';

/// `book.json` 的读写与从磁盘重建索引（PLAN.md §4.7 第 1–4 步）。
class BookStore {
  BookStore(
    this._paths,
    this._writer,
    this._chapters, {
    ChapterMoveStore? moves,
  }) : moves = moves ?? ChapterMoveStore(_paths, _writer);

  final ChapterMoveStore moves;

  final AppPaths _paths;
  final AtomicFileWriter _writer;
  final ChapterStore _chapters;

  Future<BookIndex> load(BookSummary summary) async {
    await moves.recover(summary.id);
    final File file = _paths.bookFile(summary.id);
    if (await file.exists()) {
      try {
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('book.json 顶层不是对象');
        }
        final BookIndex book = BookIndex.fromJson(decoded);
        if (book.id.isEmpty) {
          throw const FormatException('book.json 缺 id');
        }
        return book;
      } catch (error) {
        await _keepCorrupt(file, summary.id);
        AppLogger.instance.warn('book.load.failed', <String, Object?>{
          'book': summary.id,
          'error': '$error',
        });
      }
    }
    return rebuild(summary);
  }

  /// 扫描 `volumes/` 与 `*.txt` 重建；卷/章名只能用默认名（真实标题已随 book.json 丢失）。
  Future<BookIndex> rebuild(BookSummary summary) async {
    await moves.recover(summary.id);
    final Directory volumesDir = Directory(_paths.volumesDir(summary.id));
    final BookIndex book = BookIndex(id: summary.id, title: summary.title);
    if (await volumesDir.exists()) {
      final List<Directory> volumeDirs = await volumesDir
          .list()
          .where((FileSystemEntity e) => e is Directory)
          .cast<Directory>()
          .toList();
      volumeDirs.sort(
        (Directory a, Directory b) =>
            fileNameOf(a.path).compareTo(fileNameOf(b.path)),
      );
      for (int i = 0; i < volumeDirs.length; i++) {
        final Directory vdir = volumeDirs[i];
        final String volumeId = fileNameOf(vdir.path);
        final Volume volume = Volume(
          id: volumeId,
          title: '第 ${i + 1} 卷',
          order: i,
        );
        final List<File> files = await vdir
            .list()
            .where(
              (FileSystemEntity e) =>
                  e is File && e.path.toLowerCase().endsWith('.txt'),
            )
            .cast<File>()
            .toList();
        files.sort(
          (File a, File b) => fileNameOf(a.path).compareTo(fileNameOf(b.path)),
        );
        for (int j = 0; j < files.length; j++) {
          final File f = files[j];
          final String stem = fileNameOf(f.path);
          final String chapterId = stem.substring(0, stem.length - 4);
          String text = '';
          try {
            text =
                await _chapters.readText(summary.id, volumeId, chapterId) ?? '';
          } catch (_) {}
          volume.chapters.add(
            ChapterMeta(
              id: chapterId,
              title: '第 ${j + 1} 章',
              order: j,
              wordCount: countWords(text),
              updatedAt: await f.lastModified(),
            ),
          );
        }
        book.volumes.add(volume);
      }
    }
    await save(book);
    AppLogger.instance.warn('book.index.rebuilt', <String, Object?>{
      'book': summary.id,
      'volumes': book.volumes.length,
      'chapters': book.allChapters.length,
    });
    return book;
  }

  /// 只重算字数，保留用户设定的卷名/章名（崩溃恢复后用，别用 rebuild）。
  Future<void> refreshWordCounts(BookIndex book) async {
    for (final Volume volume in book.volumes) {
      for (final ChapterMeta chapter in volume.chapters) {
        String text = '';
        try {
          text = await _chapters.readText(book.id, volume.id, chapter.id) ?? '';
        } catch (_) {}
        chapter.wordCount = countWords(text);
      }
    }
    await save(book);
  }

  Future<void> save(BookIndex book) async {
    final Directory dir = Directory(_paths.bookDir(book.id));
    await dir.create(recursive: true);
    final String raw = const JsonEncoder.withIndent('  ')
        .convert(book.toJson());
    await _writer.writeAtomically(_paths.bookFile(book.id), raw);
  }

  /// 删书：整个目录移到 `trash/<bookId>-<stamp>/`，不真删（PLAN.md §3.4/§4）。
  Future<String> moveToTrash(String bookId) async {
    final Directory dir = Directory(_paths.bookDir(bookId));
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String target = pathJoin(_paths.trashDir, '$bookId-$stamp');
    if (await dir.exists()) {
      await Directory(_paths.trashDir).create(recursive: true);
      await dir.rename(target);
    }
    return target;
  }

  Future<void> _keepCorrupt(File file, String bookId) async {
    try {
      final String suffix = DateTime.now().millisecondsSinceEpoch.toString();
      await file.rename('${file.path}.corrupt-$suffix');
    } catch (_) {}
  }
}
