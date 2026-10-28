import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'atomic_file_writer.dart';
import 'bytes.dart';

/// 单书内跨卷迁移；恢复先于普通章节缺失恢复与索引重建。
class ChapterMoveStore {
  ChapterMoveStore(this.paths, this.writer, {this.onPhase});
  final AppPaths paths;
  final AtomicFileWriter writer;
  final Future<void> Function(String phase)? onPhase;

  File recordFile(String bookId) =>
      File('${paths.bookFile(bookId).parent.path}/.chapter-move.json');

  Future<void> move({
    required String bookId,
    required String sourceId,
    required String targetId,
    required String chapterId,
    required Future<void> Function() commitIndex,
    Future<void> Function()? commitSummary,
  }) async {
    for (final id in [bookId, sourceId, targetId, chapterId]) {
      _checkId(id);
    }
    if (sourceId == targetId) throw StateError('同卷排序不需要迁移正文。');
    await recover(bookId);
    final source = paths.chapterFile(bookId, sourceId, chapterId);
    final target = paths.chapterFile(bookId, targetId, chapterId);
    if (!await source.exists()) throw StateError('源正文缺失，已停止移动。');
    for (final file in [
      File('${source.path}.tmp'),
      File('${source.path}.bak.tmp'),
      target,
      File('${target.path}.bak'),
      File('${target.path}.tmp'),
      File('${target.path}.bak.tmp'),
    ]) {
      if (await file.exists()) {
        throw StateError('存在未解决或冲突文件：${file.path}；已停止移动。');
      }
    }
    final backup = File('${source.path}.bak');
    final Map<String, dynamic> record = {
      'version': 1,
      'book': bookId,
      'source': sourceId,
      'target': targetId,
      'chapter': chapterId,
      'txt': base64Encode(await source.readAsBytes()),
      'bak': await backup.exists()
          ? base64Encode(await backup.readAsBytes())
          : null,
    };
    await onPhase?.call('beforeRecord');
    await writer.writeAtomically(recordFile(bookId), jsonEncode(record));
    await onPhase?.call('record');
    await _ensure(target, base64Decode(record['txt'] as String));
    await onPhase?.call('txt');
    if (record['bak'] != null) {
      await _ensure(
        File('${target.path}.bak'),
        base64Decode(record['bak'] as String),
      );
    }
    await onPhase?.call('bak');
    await _verify(source, base64Decode(record['txt'] as String));
    await _verify(target, base64Decode(record['txt'] as String));
    if (record['bak'] != null) {
      await _verify(backup, base64Decode(record['bak'] as String));
      await _verify(
        File('${target.path}.bak'),
        base64Decode(record['bak'] as String),
      );
    }
    await onPhase?.call('verified');
    await commitIndex();
    await onPhase?.call('index');
    await commitSummary?.call();
    await onPhase?.call('summary');
    await recover(
      bookId,
      beforeClear: () => onPhase?.call('cleanup') ?? Future<void>.value(),
    );
  }

  /// 只信已落盘索引，不比较时间戳。未知归属/字节冲突时不清理任何证据。
  Future<void> recover(
    String bookId, {
    Future<void> Function()? beforeClear,
  }) async {
    _checkId(bookId);
    final file = recordFile(bookId);
    final tmp = File('${file.path}.tmp');
    if (!await file.exists() && !await tmp.exists()) return;
    try {
      if (await file.exists() && await tmp.exists()) {
        throw StateError('恢复记录存在冲突临时文件');
      }
      final from = await file.exists() ? file : tmp;
      final r = jsonDecode(await from.readAsString()) as Map<String, dynamic>;
      if (r['version'] != 1 || r['book'] != bookId) {
        throw StateError('迁移记录身份无效');
      }
      final sourceId = r['source'] as String;
      final targetId = r['target'] as String;
      final chapterId = r['chapter'] as String;
      for (final id in [sourceId, targetId, chapterId]) {
        _checkId(id);
      }
      if (sourceId == targetId) throw StateError('迁移记录卷身份冲突');
      final txt = base64Decode(r['txt'] as String);
      final bak = r['bak'] == null ? null : base64Decode(r['bak'] as String);
      final index = jsonDecode(
        await paths.bookFile(bookId).readAsString(),
      ) as Map<String, dynamic>;
      if (index['id'] != bookId) throw StateError('作品索引身份无效');
      final owners = <String>[];
      for (final v in index['volumes'] as List<dynamic>) {
        for (final c in v['chapters'] as List<dynamic>) {
          if (c['id'] == chapterId) owners.add(v['id'] as String);
        }
      }
      if (owners.length != 1 || ![sourceId, targetId].contains(owners.single)) {
        throw StateError('无法确定章节唯一归属，禁止重建索引');
      }
      final source = paths.chapterFile(bookId, sourceId, chapterId);
      final target = paths.chapterFile(bookId, targetId, chapterId);
      final keep = owners.single == sourceId ? source : target;
      final discard = owners.single == sourceId ? target : source;
      // 先核验所有现有文件，避免清理了一半才发现另一份被外部改写。
      for (final f in [source, target]) {
        if (await f.exists()) await _verify(f, txt);
        final b = File('${f.path}.bak');
        if (await b.exists()) {
          if (bak == null) throw StateError('出现记录外的备份文件：${b.path}');
          await _verify(b, bak);
        }
        final t = File('${f.path}.tmp');
        if (await t.exists()) await _verify(t, txt);
        final bt = File('${f.path}.bak.tmp');
        if (await bt.exists()) {
          if (bak == null) throw StateError('存在记录外的备份临时文件');
          await _verify(bt, bak);
        }
      }
      if (!await file.exists()) await tmp.rename(file.path);
      await _ensure(keep, txt);
      if (bak != null) {
        final backup = File('${keep.path}.bak');
        await _ensure(backup, bak);
        // 两份已按记录逐字节验证，txt 是当前稿、bak 是旧稿。
        // 复制先 txt 后 bak 会使旧稿 mtime 较新；必须在清记录前消除该假象，
        // 否则下一步普通 ChapterStore.recover 会错误地用旧备份覆盖当前正文。
        final backupTime = await backup.lastModified();
        if (backupTime.isAfter(await keep.lastModified())) {
          await keep.setLastModified(backupTime);
        }
      }
      for (final f in [
        discard,
        File('${discard.path}.bak'),
        File('${discard.path}.tmp'),
        File('${discard.path}.bak.tmp'),
        File('${keep.path}.tmp'),
        File('${keep.path}.bak.tmp'),
      ]) {
        if (await f.exists()) await f.delete();
      }
      await beforeClear?.call();
      await file.delete();
    } catch (error) {
      throw StateError('章节移动待恢复，已保留正文和迁移记录并阻止编辑/重建：$error');
    }
  }

  static void _checkId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw StateError('不安全的作品/卷/章 ID');
    }
  }

  Future<void> _ensure(File file, List<int> bytes) async {
    if (await file.exists()) {
      await _verify(file, bytes);
      return;
    }
    await writer.writeBytesAtomically(file, bytes);
    await _verify(file, bytes);
  }

  Future<void> _verify(File file, List<int> expected) async {
    final actual = await file.readAsBytes();
    if (!bytesEqual(actual, expected)) {
      throw StateError('字节校验失败：${file.path}');
    }
  }
}
