import 'dart:convert';
import 'dart:io';

import '../platform/path_utils.dart';
import 'app_paths.dart';
import 'atomic_file_writer.dart';
import 'bytes.dart';

/// 导出规格见 PLAN.md §4.9。全部写入走临时文件 + rename。
class ExportService {
  ExportService(this._paths, this._writer);

  final AppPaths _paths;
  final AtomicFileWriter _writer;

  /// 单章：`<导出根>\<书名>\<卷名>\<章名>.txt`
  Future<File> exportChapter({
    required String bookTitle,
    required String volumeTitle,
    required String chapterTitle,
    required String text,
    String? customDir,
  }) async {
    final Directory dir = await _bookVolumeDir(
      bookTitle,
      volumeTitle,
      customDir,
    );
    final String stem = await _uniqueStem(dir, chapterTitle);
    final File file = File(pathJoin(dir.path, '$stem.txt'));
    await _writeExport(file, _withFinalNewline(text));
    return file;
  }

  /// 整卷：`<导出根>\<书名>\<卷名>.txt`
  Future<File> exportVolume({
    required String bookTitle,
    required String volumeTitle,
    required List<({String title, String text})> chapters,
    String? customDir,
  }) async {
    final Directory dir = await _bookDir(bookTitle, customDir);
    final String stem = await _uniqueStem(dir, volumeTitle);
    final File file = File(pathJoin(dir.path, '$stem.txt'));
    final StringBuffer out = StringBuffer();
    out.write(_volumeHeader(volumeTitle));
    for (final ({String title, String text}) chapter in chapters) {
      out.write(_chapterHeader(chapter.title));
      out.write(_withFinalNewline(chapter.text));
    }
    await _writeExport(file, _withFinalNewline(out.toString()));
    return file;
  }

  /// 整书：`<导出根>\<书名>.txt`
  Future<File> exportBook({
    required String bookTitle,
    required List<
      ({String volumeTitle, List<({String title, String text})> chapters})
    >
    volumes,
    String? customDir,
  }) async {
    final Directory dir = Directory(_paths.exportRoot(customDir));
    await dir.create(recursive: true);
    final String stem = await _uniqueStem(dir, bookTitle);
    final File file = File(pathJoin(dir.path, '$stem.txt'));
    final StringBuffer out = StringBuffer();
    for (final ({
          String volumeTitle,
          List<({String title, String text})> chapters,
        })
        volume
        in volumes) {
      out.write(_volumeHeader(volume.volumeTitle));
      for (final ({String title, String text}) chapter in volume.chapters) {
        out.write(_chapterHeader(chapter.title));
        out.write(_withFinalNewline(chapter.text));
      }
    }
    await _writeExport(file, _withFinalNewline(out.toString()));
    return file;
  }

  /// 生成整卷/整书内容（供预览与测试复用）。
  String composeVolume(
    String volumeTitle,
    List<({String title, String text})> chapters,
  ) {
    final StringBuffer out = StringBuffer(_volumeHeader(volumeTitle));
    for (final ({String title, String text}) chapter in chapters) {
      out.write(_chapterHeader(chapter.title));
      out.write(_withFinalNewline(chapter.text));
    }
    return _withFinalNewline(out.toString());
  }

  String composeBook(
    List<({String volumeTitle, List<({String title, String text})> chapters})>
    volumes,
  ) {
    final StringBuffer out = StringBuffer();
    for (final ({
          String volumeTitle,
          List<({String title, String text})> chapters,
        })
        volume
        in volumes) {
      out.write(_volumeHeader(volume.volumeTitle));
      for (final ({String title, String text}) chapter in volume.chapters) {
        out.write(_chapterHeader(chapter.title));
        out.write(_withFinalNewline(chapter.text));
      }
    }
    return _withFinalNewline(out.toString());
  }

  String _volumeHeader(String title) => '──── 卷：$title ────\n\n';
  String _chapterHeader(String title) => '──── 章：$title ────\n\n';

  String _withFinalNewline(String text) =>
      text.endsWith('\n') ? text : '$text\n';

  Future<Directory> _bookDir(String bookTitle, String? customDir) async {
    final Directory dir = Directory(
      pathJoin(_paths.exportRoot(customDir), sanitizeFileName(bookTitle)),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _bookVolumeDir(
    String bookTitle,
    String volumeTitle,
    String? customDir,
  ) async {
    final Directory book = await _bookDir(bookTitle, customDir);
    final Directory dir = Directory(
      pathJoin(book.path, sanitizeFileName(volumeTitle)),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _writeExport(File file, String text) async {
    final temporary = File('${file.path}.tmp');
    for (final path in [file.path, temporary.path]) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('导出目标已存在，未覆盖任何文件', path);
      }
    }
    final expected = utf8.encode(text);
    try {
      try {
        await _writer.writeAtomically(file, text);
      } catch (_) {
        // An error after rename is a committed export only if every byte is
        // exactly the requested UTF-8 output, never merely because it exists.
        if (!await _hasBytes(file, expected)) rethrow;
      }
      if (!await _hasBytes(file, expected)) {
        throw FileSystemException('导出文件未完整写入', file.path);
      }
    } finally {
      // Both names were absent before this exclusive export. Never remove an
      // older tmp, a link/directory, or a final file of uncertain ownership.
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  Future<bool> _hasBytes(File file, List<int> expected) async {
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return false;
      }
      return bytesEqual(await file.readAsBytes(), expected);
    } on FileSystemException {
      return false;
    }
  }

  Future<String> _uniqueStem(Directory dir, String raw) async {
    final taken = <String>{};
    await for (final entity in dir.list(followLinks: false)) {
      final name = fileNameOf(entity.path).toLowerCase();
      if (name.endsWith('.txt.tmp')) {
        taken.add(name.substring(0, name.length - '.txt.tmp'.length));
      } else {
        final dot = name.lastIndexOf('.');
        taken.add(dot < 0 ? name : name.substring(0, dot));
      }
    }
    return uniqueFileName(sanitizeFileName(raw), taken);
  }
}
