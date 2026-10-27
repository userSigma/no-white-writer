import 'dart:convert';
import 'dart:io';

import '../chapter_numbering.dart';
import '../models.dart';
import '../platform/path_utils.dart';
import 'app_paths.dart';

/// Strict, side-effect-free export reads. Never runs load/recovery/rebuild.
class ExportSnapshotStore {
  ExportSnapshotStore(this.paths, {Future<List<int>> Function(File)? readBytes})
    : _readBytes = readBytes ?? ((file) => file.readAsBytes());

  final AppPaths paths;
  final Future<List<int>> Function(File) _readBytes;

  void _checkId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('作品目录 ID 无效，已停止导出');
    }
  }

  Future<void> _requireType(String path, FileSystemEntityType expected) async {
    if (await FileSystemEntity.type(path, followLinks: false) != expected) {
      throw FileSystemException('作品文件缺失或类型异常，已停止导出', path);
    }
  }

  Future<void> _requireAbsent(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('作品存在未解决临时文件，请先完成恢复再导出', path);
    }
  }

  Future<void> _checkBookConflicts(String bookId) async {
    for (final path in [
      paths.dataRoot.path,
      paths.booksDir,
      paths.bookDir(bookId),
    ]) {
      await _requireType(path, FileSystemEntityType.directory);
    }
    for (final name in [
      '.chapter-move.json',
      '.chapter-move.json.tmp',
      'book.json.tmp',
    ]) {
      await _requireAbsent(pathJoin(paths.bookDir(bookId), name));
    }
  }

  String _decode(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: false);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('作品索引条目不是对象，已停止导出');
    }
    return value;
  }

  List<dynamic> _list(Object? value) {
    if (value is! List<dynamic>) {
      throw const FormatException('作品索引缺少完整卷章列表，已停止导出');
    }
    return value;
  }

  void _uniqueId(Object? value, Set<String> seen) {
    if (value is! String) {
      throw const FormatException('作品索引缺少有效 ID，已停止导出');
    }
    _checkId(value);
    if (!seen.add(value.toLowerCase())) {
      throw const FormatException('作品索引含重复 ID，已停止导出');
    }
  }

  void _checkNumbering(Object? value, int count) {
    if (value == null) return; // Compatible with pre-numbering indexes.
    final rule = _object(value);
    if (rule['enabled'] != null && rule['enabled'] is! bool) {
      throw const FormatException('编号开关无效，已停止导出');
    }
    for (final key in ['start', 'step', 'padding']) {
      if (rule[key] != null && rule[key] is! int) {
        throw const FormatException('编号数值必须为整数，已停止导出');
      }
    }
    if (rule['enabled'] == true) {
      final numbering = ChapterNumbering.fromJson(rule);
      numbering.validate(count);
      if ('${numbering.prefix}${numbering.suffix}'.contains(RegExp('[\r\n]'))) {
        throw const FormatException('编号前后缀须为单行，已停止导出');
      }
    }
  }

  Future<BookIndex> readBook(String bookId) async {
    _checkId(bookId);
    await _checkBookConflicts(bookId);
    final file = paths.bookFile(bookId);
    await _requireType(file.path, FileSystemEntityType.file);
    final data = _object(jsonDecode(_decode(await _readBytes(file))));
    if (data['id'] != bookId) {
      throw const FormatException('作品索引 ID 不符，已停止导出');
    }
    final volumes = <String>{};
    final chapters = <String>{};
    try {
      for (final entry in _list(data['volumes'])) {
        final volume = _object(entry);
        _uniqueId(volume['id'], volumes);
        final members = _list(volume['chapters']);
        for (final member in members) {
          _uniqueId(_object(member)['id'], chapters);
        }
        _checkNumbering(volume['numbering'], members.length);
      }
      // Parsing only after validation prevents the legacy model's whereType
      // compatibility filters from hiding corrupt/missing chapter entries.
      return BookIndex.fromJson(data);
    } on TypeError {
      throw const FormatException('作品索引字段类型无效，已停止导出');
    }
  }

  Future<String> readChapter(
    String bookId,
    String volumeId,
    String chapterId,
  ) async {
    _checkId(bookId);
    _checkId(volumeId);
    _checkId(chapterId);
    await _checkBookConflicts(bookId);
    for (final path in [
      paths.volumesDir(bookId),
      paths.volumeDir(bookId, volumeId),
    ]) {
      await _requireType(path, FileSystemEntityType.directory);
    }
    final file = paths.chapterFile(bookId, volumeId, chapterId);
    for (final suffix in ['.tmp', '.bak.tmp']) {
      await _requireAbsent('${file.path}$suffix');
    }
    await _requireType(file.path, FileSystemEntityType.file);
    final backup = File('${file.path}.bak');
    final backupType = await FileSystemEntity.type(
      backup.path,
      followLinks: false,
    );
    if (backupType != FileSystemEntityType.notFound) {
      await _requireType(backup.path, FileSystemEntityType.file);
      if ((await backup.lastModified()).isAfter(await file.lastModified())) {
        throw FileSystemException('备份较新，请先完成恢复再导出', backup.path);
      }
    }
    return _decode(await _readBytes(file))
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }
}
