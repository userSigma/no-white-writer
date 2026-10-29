import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import '../models.dart';
import '../platform/path_utils.dart';
import 'app_paths.dart';

class RecoveryRecord {
  RecoveryRecord({
    required this.bookId,
    required this.volumeId,
    required this.chapterId,
    required this.chapterTitle,
    required this.source,
  });

  final String bookId;
  final String volumeId;
  final String chapterId;
  final String chapterTitle;

  /// `tmp` / `bak` / `missing`
  final String source;

  bool get isMissing => source == 'missing';
}

/// 章节正文文件的读写、原子保存与崩溃恢复（PLAN.md §4.2 S0–S7、§4.10）。
class ChapterStore {
  ChapterStore(this._paths);

  final AppPaths _paths;

  File fileOf(String bookId, String volumeId, String chapterId) =>
      _paths.chapterFile(bookId, volumeId, chapterId);

  File _tmpOf(File txt) => File('${txt.path}.tmp');
  File _bakOf(File txt) => File('${txt.path}.bak');

  /// 返回归一化后的正文：严格 UTF-8 解码、去 BOM、`\r\n`/`\r` → `\n`。
  /// 只有文件不存在才返回 null；读取或解码失败由上层阻止写入。
  Future<String?> readText(
    String bookId,
    String volumeId,
    String chapterId,
  ) async {
    final File file = fileOf(bookId, volumeId, chapterId);
    if (!await file.exists()) return null;
    try {
      return normalize(await file.readAsBytes());
    } catch (error) {
      AppLogger.instance.error('chapter.read.failed', <String, Object?>{
        'book': bookId,
        'volume': volumeId,
        'chapter': chapterId,
        'error': '$error',
      });
      rethrow;
    }
  }

  static String normalize(List<int> bytes) {
    String text = utf8.decode(bytes, allowMalformed: false);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// 原子保存：tmp 写入并 flush → 旧正文改名为 .bak → tmp 改名为主文件。
  Future<void> writeText(
    String bookId,
    String volumeId,
    String chapterId,
    String text,
  ) async {
    final File txt = fileOf(bookId, volumeId, chapterId);
    await txt.parent.create(recursive: true);
    final File tmp = _tmpOf(txt);
    final File bak = _bakOf(txt);

    final RandomAccessFile raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeString(text, encoding: utf8);
      await raf.flush();
    } finally {
      await raf.close();
    }

    if (await txt.exists()) {
      // rename 覆盖已存在的 .bak（Dart File.rename 允许覆盖目标文件）。
      await txt.rename(bak.path);
    }
    // 崩溃点若落在「tmp 已落盘、尚未改名」之前，恢复逻辑会用 tmp。
    await tmp.rename(txt.path);
  }

  Future<void> deleteToTrash(
    String bookId,
    String volumeId,
    String chapterId, {
    String? title,
  }) async {
    final File txt = fileOf(bookId, volumeId, chapterId);
    final Directory trashDir = Directory(pathJoin(_paths.trashDir, bookId));
    await trashDir.create(recursive: true);
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    if (await txt.exists()) {
      await txt.rename(pathJoin(trashDir.path, '${stamp}_$chapterId.txt'));
    }
    for (final String scene in <String>['.bak', '.tmp']) {
      final File f = File('${txt.path}$scene');
      if (await f.exists()) {
        await f.rename(
          pathJoin(trashDir.path, '${stamp}_$chapterId.txt$scene'),
        );
      }
    }
    AppLogger.instance.info('chapter.trash', <String, Object?>{
      'bookId': bookId,
      'volumeId': volumeId,
      'chapterId': chapterId,
      'title': title,
      'stamp': stamp,
    });
  }

  /// 启动时的崩溃恢复判定（PLAN.md §4.10 的 6 行判定表）。
  /// 正文或备份恢复失败必须抛出，禁止带着不完整现场继续写入。
  Future<List<RecoveryRecord>> recover(BookIndex book) async {
    final List<RecoveryRecord> records = <RecoveryRecord>[];
    for (final Volume volume in book.volumes) {
      for (final ChapterMeta chapter in volume.chapters) {
        final File txt = fileOf(book.id, volume.id, chapter.id);
        final File tmp = _tmpOf(txt);
        final File bak = _bakOf(txt);
        final bool tmpExists = await tmp.exists();
        final bool txtExists = await txt.exists();
        final bool bakExists = await bak.exists();

        if (tmpExists) {
          final DateTime tmpTime = await tmp.lastModified();
          final bool newer =
              !txtExists || tmpTime.isAfter(await txt.lastModified());
          if (newer) {
            try {
              if (txtExists) await txt.rename(bak.path);
              await tmp.rename(txt.path);
              records.add(_record(book, volume, chapter, 'tmp'));
              AppLogger.instance.warn('chapter.recover.tmp', <String, Object?>{
                'book': book.id,
                'chapter': chapter.id,
              });
            } catch (error) {
              AppLogger.instance.error(
                'chapter.recover.tmp.failed',
                <String, Object?>{'chapter': chapter.id, 'error': '$error'},
              );
              rethrow;
            }
          } else {
            try {
              await tmp.delete();
            } catch (_) {}
          }
          continue;
        }

        if (!txtExists) {
          if (bakExists) {
            try {
              await bak.copy(txt.path);
              records.add(_record(book, volume, chapter, 'bak'));
              AppLogger.instance.warn('chapter.recover.bak', <String, Object?>{
                'book': book.id,
                'chapter': chapter.id,
              });
            } catch (error) {
              AppLogger.instance.error(
                'chapter.recover.bak.failed',
                <String, Object?>{'chapter': chapter.id, 'error': '$error'},
              );
              rethrow;
            }
          } else {
            records.add(_record(book, volume, chapter, 'missing'));
          }
          continue;
        }

        if (bakExists) {
          final DateTime bakTime = await bak.lastModified();
          final DateTime txtTime = await txt.lastModified();
          if (bakTime.isAfter(txtTime)) {
            try {
              await bak.copy(txt.path);
              records.add(_record(book, volume, chapter, 'bak'));
            } catch (error) {
              AppLogger.instance.error(
                'chapter.recover.bak.failed',
                <String, Object?>{'chapter': chapter.id, 'error': '$error'},
              );
              rethrow;
            }
          }
        }
      }
    }
    return records;
  }

  RecoveryRecord _record(
    BookIndex book,
    Volume volume,
    ChapterMeta chapter,
    String source,
  ) => RecoveryRecord(
    bookId: book.id,
    volumeId: volume.id,
    chapterId: chapter.id,
    chapterTitle: chapter.title,
    source: source,
  );
}
