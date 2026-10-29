import 'dart:io';

import '../platform/path_utils.dart';

/// 磁盘布局的唯一来源（PLAN.md §4.1）。
class AppPaths {
  AppPaths({required this.dataRoot, required this.documentsRoot});

  final Directory dataRoot;
  final Directory documentsRoot;

  String get dataRootPath => dataRoot.path;

  File get libraryFile => File(pathJoin(dataRoot.path, 'library.json'));
  File get settingsFile => File(pathJoin(dataRoot.path, 'settings.json'));
  File get instanceLockFile => File(pathJoin(dataRoot.path, 'instance.lock'));

  String get logsDir => pathJoin(dataRoot.path, 'logs');
  String get booksDir => pathJoin(dataRoot.path, 'books');
  String get trashDir => pathJoin(dataRoot.path, 'trash');
  String get languagesDir => pathJoin(dataRoot.path, 'languages');

  String bookDir(String bookId) => pathJoin(booksDir, bookId);
  File bookFile(String bookId) => File(pathJoin(bookDir(bookId), 'book.json'));

  String volumesDir(String bookId) => pathJoin(bookDir(bookId), 'volumes');
  String volumeDir(String bookId, String volumeId) =>
      pathJoin(volumesDir(bookId), volumeId);

  File chapterFile(String bookId, String volumeId, String chapterId) =>
      File(pathJoin(volumeDir(bookId, volumeId), '$chapterId.txt'));

  /// 默认导出根：`文档\不白写作`；设置里可改。
  String exportRoot([String? custom]) => (custom != null && custom.isNotEmpty)
      ? custom
      : pathJoin(documentsRoot.path, '不白写作');

  Future<void> ensureLayout() async {
    await dataRoot.create(recursive: true);
    await Directory(logsDir).create(recursive: true);
    await Directory(booksDir).create(recursive: true);
    await Directory(trashDir).create(recursive: true);
    // languages/：用户可放入自定义语言包 JSON（i18n 可插拔语言）。
    await Directory(languagesDir).create(recursive: true);
  }
}
