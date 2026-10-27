import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import '../models.dart';
import 'app_paths.dart';
import 'atomic_file_writer.dart';

/// `library.json` 的读写（PLAN.md §4.1 / §4.7）。损坏时改名留存并返回空索引，
/// 由上层用 `BookStore` 重建。
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
      return LibraryIndex.fromJson(decoded);
    } catch (error) {
      await _keepCorrupt(file, 'library');
      AppLogger.instance.error('library.load.failed', <String, Object?>{
        'error': '$error',
      });
      return LibraryIndex();
    }
  }

  Future<void> save(LibraryIndex index) async {
    final String raw = const JsonEncoder.withIndent('  ')
        .convert(index.toJson());
    await _writer.writeAtomically(_paths.libraryFile, raw);
  }

  Future<void> _keepCorrupt(File file, String stem) async {
    try {
      final String suffix = DateTime.now().millisecondsSinceEpoch.toString();
      await file.rename('${file.path}.corrupt-$suffix');
      AppLogger.instance.warn('storage.corrupt.kept', <String, Object?>{
        'file': file.path,
        'backup': '${file.path}.corrupt-$suffix',
        'stem': stem,
      });
    } catch (_) {
      // 保存失败不阻断启动。
    }
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
