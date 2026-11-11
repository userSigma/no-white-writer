import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/chapter_display.dart';
import '../core/models.dart';
import '../core/storage/export_service.dart';
import '../core/storage/export_snapshot_store.dart';
import 'editor_controller.dart';
import 'library_controller.dart';
import 'settings_controller.dart';

enum ExportScope { chapter, volume, book }

class ExportTarget {
  const ExportTarget.chapter(this.bookId, this.volumeId, this.chapterId)
    : scope = ExportScope.chapter;
  const ExportTarget.volume(this.bookId, this.volumeId)
    : scope = ExportScope.volume,
      chapterId = null;
  const ExportTarget.book(this.bookId)
    : scope = ExportScope.book,
      volumeId = null,
      chapterId = null;

  final ExportScope scope;
  final String bookId;
  final String? volumeId;
  final String? chapterId;
}

/// Coordinates regular exports. Failed-save emergency export is separate.
class ExportController extends ChangeNotifier {
  ExportController({
    required this.reader,
    required this.editor,
    required this.library,
    required this.settings,
    required this.service,
  });

  final ExportSnapshotStore reader;
  final EditorController editor;
  final LibraryController library;
  final SettingsController settings;
  final ExportService service;
  bool _busy = false;
  bool _disposed = false;
  String? message;
  bool get busy => _busy;

  Future<File?> export(ExportTarget target) async {
    if (_disposed || _busy) return null;
    _busy = true;
    message = null;
    _notify();
    try {
      File? result;
      final saved = await editor.runExport(() async {
        await library.beginExport();
        try {
          if (library.blockedBooks.contains(target.bookId)) {
            throw StateError('作品迁移待恢复，已停止导出。');
          }
          // 书级冲突检查只在 openSession 做一次；整本导出时逐章读取
          // 不再重复 stat 书目录与迁移记录探针。
          final session = await reader.openSession(target.bookId);
          final book = await session.readBook();
          result = await _writeTarget(
            session,
            target,
            book,
            settings.settings.exportDirectory,
          );
          if (result == null) message = '暂无章节可导出';
        } finally {
          library.endExport();
        }
      });
      if (!saved) {
        message =
            editor.noticeMessage ?? editor.errorMessage ?? '未能完成保存，已停止导出。';
      }
      return result;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<List<({String title, String text})>> _readVolume(
    ExportBookSession session,
    BookIndex book,
    Volume volume,
  ) async {
    final chapters = <({String title, String text})>[];
    for (final chapter in volume.chapters) {
      final text = await session.readChapter(volume.id, chapter.id);
      chapters.add((
        title: displayChapterTitle(book, volume, chapter),
        text: text,
      ));
    }
    return chapters;
  }

  Future<File?> _writeTarget(
    ExportBookSession session,
    ExportTarget target,
    BookIndex book,
    String? customDir,
  ) async {
    switch (target.scope) {
      case ExportScope.chapter:
        final volume = book.volumes.firstWhere((v) => v.id == target.volumeId);
        final chapter = volume.chapters.firstWhere(
          (c) => c.id == target.chapterId,
        );
        final text = await session.readChapter(volume.id, chapter.id);
        return service.exportChapter(
          bookTitle: book.title,
          volumeTitle: displayVolumeTitle(volume),
          chapterTitle: displayChapterTitle(book, volume, chapter),
          text: text,
          customDir: customDir,
        );
      case ExportScope.volume:
        final volume = book.volumes.firstWhere((v) => v.id == target.volumeId);
        if (volume.chapters.isEmpty) return null;
        final chapters = await _readVolume(session, book, volume);
        return service.exportVolume(
          bookTitle: book.title,
          volumeTitle: displayVolumeTitle(volume),
          chapters: chapters,
          customDir: customDir,
        );
      case ExportScope.book:
        if (book.volumes.every((v) => v.chapters.isEmpty)) return null;
        final volumes =
            <
              ({
                String volumeTitle,
                List<({String title, String text})> chapters,
              })
            >[];
        for (final volume in book.volumes) {
          volumes.add((
            volumeTitle: displayVolumeTitle(volume),
            chapters: await _readVolume(session, book, volume),
          ));
        }
        return service.exportBook(
          bookTitle: book.title,
          volumes: volumes,
          customDir: customDir,
        );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
