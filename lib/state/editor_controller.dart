import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show TextEditingValue, TextRange, TextSelection;
import 'package:flutter/widgets.dart' show TextEditingController;

import '../core/chapter_numbering.dart';
import '../core/logging/app_logger.dart';
import '../core/models.dart';
import '../core/storage/book_store.dart';
import '../core/storage/chapter_store.dart';
import '../core/storage/export_service.dart';
import '../core/text/indenting_controller.dart';
import '../core/text/word_count.dart';
import 'library_controller.dart';
import 'settings_controller.dart';

enum SaveState { clean, dirty, saving, failed, blocked }

/// 标题与正文共享保存基线、5 秒防抖、失败状态和离开门禁（PLAN.md §15）。
class EditorController extends ChangeNotifier {
  EditorController({
    required this.chapters,
    required this.books,
    required this.exports,
    required this.library,
    required this.settings,
  }) {
    _text = IndentingTextEditingController(
      autoIndent: () => settings.settings.autoIndent,
      blankLineBetween: () => settings.settings.blankLineBetween,
    );
    _text.addListener(_onChanged);
    _title.addListener(_onChanged);
  }

  final ChapterStore chapters;
  final BookStore books;
  final ExportService exports;
  final LibraryController library;
  final SettingsController settings;
  static const Duration autosaveDelay = Duration(seconds: 5);

  late final IndentingTextEditingController _text;
  final TextEditingController _title = TextEditingController();
  TextEditingController get text => _text;
  TextEditingController get title => _title;

  BookIndex? book;
  Volume? volume;
  ChapterMeta? chapter;
  SaveState state = SaveState.clean;
  bool isDirty = false;
  bool loading = false;
  bool structuralBusy = false;
  String? errorMessage;
  String? noticeMessage;
  DateTime? lastSavedAt;
  int wordCount = 0;

  String _savedText = '';
  String _savedTitle = '';
  bool _internal = false;
  bool _disposed = false;
  bool _missing = false;
  bool _needsRetry = false;
  Timer? _debounce;
  Future<void>? _inflight;
  Future<void>? _opening;
  Future<void> _navigationTail = Future<void>.value();
  int _openToken = 0;

  bool get hasChapter => book != null && volume != null && chapter != null;
  bool get _dirty =>
      _missing ||
      _needsRetry ||
      _text.text != _savedText ||
      _title.text != _savedTitle;

  /// 导航串行化，调用者必须检查返回值；保存失败绝不偷偷覆盖旧草稿。
  Future<bool> open({
    required BookIndex inBook,
    required Volume inVolume,
    required ChapterMeta inChapter,
  }) => _navigate(() async {
    if (!await flush()) return false;
    final int token = ++_openToken;
    final Completer<void> opened = Completer<void>();
    _opening = opened.future;
    loading = true;
    _debounce?.cancel();
    book = inBook;
    volume = inVolume;
    chapter = inChapter;
    _savedText = '';
    _savedTitle = inChapter.title;
    _missing = false;
    _needsRetry = false;
    isDirty = false;
    errorMessage = null;
    noticeMessage = null;
    lastSavedAt = null;
    wordCount = 0;
    _internal = true;
    _text.clear();
    _title.value = TextEditingValue(
      text: inChapter.title,
      selection: TextSelection.collapsed(offset: inChapter.title.length),
    );
    _internal = false;
    final TextEditingValue beforeRead = _text.value;
    state = SaveState.clean;
    _notify();
    try {
      final String? content = await chapters.readText(
        inBook.id,
        inVolume.id,
        inChapter.id,
      );
      if (_disposed || token != _openToken) return false;
      final String loadedText = content ?? '';
      // 极快的输入也不能被异步读盘覆盖。UI 在 loading 时禁用输入，控制器仍保护它。
      if (_text.value == beforeRead) {
        _internal = true;
        _text.value = TextEditingValue(
          text: loadedText,
          selection: TextSelection.collapsed(offset: loadedText.length),
        );
        _internal = false;
      }
      _savedText = loadedText;
      _missing = content == null;
      isDirty = _dirty;
      state = _missing
          ? SaveState.failed
          : (isDirty ? SaveState.dirty : SaveState.clean);
      errorMessage = _missing ? '正文文件缺失，已按空章打开；保存会重建文件。' : null;
      wordCount = countWords(_text.text);
      if (isDirty) _schedule();
      return true;
    } catch (error) {
      // 无法读取不等于空文件：禁止用空白草稿覆盖一份尚未成功读取的正文。
      state = SaveState.blocked;
      errorMessage = '读取正文失败，已阻止写入：$error';
      return false;
    } finally {
      loading = false;
      _opening = null;
      opened.complete();
      _notify();
    }
  });

  Future<bool> _navigate(Future<bool> Function() action) {
    final Future<bool> result = _navigationTail.then(
      (_) => _disposed ? false : action(),
    );
    _navigationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// 所有目录写操作共用导航队列：保护组合态、在途保存与当前绑定。
  Future<bool> runStructure(BookIndex target, Future<void> Function() action) =>
      _navigate(() async {
        if (structuralBusy || library.blockedBooks.contains(target.id)) {
          return false;
        }
        if (_isComposing) {
          noticeMessage = '请先完成输入法组词，再修改目录。';
          _notify();
          return false;
        }
        structuralBusy = true;
        _notify();
        try {
          if (!await flush()) return false;
          await action();
          return true;
        } catch (error) {
          noticeMessage = '目录操作未完成：$error';
          return false;
        } finally {
          if (book?.id == target.id) {
            if (library.blockedBooks.contains(target.id)) {
              state = SaveState.blocked;
              errorMessage = noticeMessage ?? '迁移待恢复，已阻止继续写入。';
            } else {
              final current = target.chapterById(chapter?.id ?? '');
              if (current == null) {
                ++_openToken;
                _debounce?.cancel();
                book = null;
                volume = null;
                chapter = null;
                _savedText = '';
                _savedTitle = '';
                _internal = true;
                _text.clear();
                _title.clear();
                _internal = false;
                _missing = false;
                _needsRetry = false;
                isDirty = false;
                wordCount = 0;
                state = SaveState.clean;
              } else {
                book = target;
                chapter = current;
                volume = target.volumeOfChapter(current.id);
                if (_title.text == _savedTitle &&
                    _savedTitle != current.title) {
                  _internal = true;
                  _title.text = current.title;
                  _savedTitle = current.title;
                  _internal = false;
                }
              }
            }
          }
          structuralBusy = false;
          _notify();
        }
      });

  /// 常规导出与导航、结构变更共用队列，但不改变当前编辑绑定。
  Future<bool> runExport(Future<void> Function() action) => _navigate(() async {
    if (structuralBusy || state == SaveState.blocked) return false;
    if (_isComposing) {
      noticeMessage = '请先完成输入法组词，再导出。';
      _notify();
      return false;
    }
    structuralBusy = true;
    _notify();
    try {
      if (!await flush()) return false;
      await action();
      return true;
    } finally {
      structuralBusy = false;
      _notify();
    }
  });

  /// 先落盘再解绑；删除当前章必须等待本方法成功后才能操作文件。
  Future<bool> close() => _navigate(() async {
    if (!await flush()) return false;
    ++_openToken;
    _debounce?.cancel();
    _debounce = null;
    book = null;
    volume = null;
    chapter = null;
    _savedText = '';
    _savedTitle = '';
    _missing = false;
    _needsRetry = false;
    _internal = true;
    _text.clear();
    _title.clear();
    _internal = false;
    isDirty = false;
    wordCount = 0;
    state = SaveState.clean;
    errorMessage = null;
    noticeMessage = null;
    _notify();
    return true;
  });

  /// 强制等待正在保存的快照，再保存期间产生的新输入。
  Future<bool> flush() async {
    await _opening;
    if (_disposed || state == SaveState.blocked) return false;
    _debounce?.cancel();
    do {
      await saveNow(force: true);
      if (state == SaveState.failed || state == SaveState.blocked) return false;
    } while (hasChapter && isDirty);
    return !isDirty;
  }

  void _onChanged() {
    if (_internal || _disposed || !hasChapter) return;
    wordCount = countWords(_text.text);
    isDirty = _dirty;
    if (state != SaveState.saving && state != SaveState.blocked) {
      state = _needsRetry
          ? SaveState.failed
          : (isDirty ? SaveState.dirty : SaveState.clean);
    }
    if (isDirty && !loading && !structuralBusy && state != SaveState.blocked) {
      _schedule();
    } else if (!isDirty) {
      _debounce?.cancel();
    }
    _notify();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, () => saveNow());
  }

  bool get isComposing => _isComposing;

  bool get _isComposing =>
      <TextEditingController>[_text, _title].any((TextEditingController c) {
        final TextRange range = c.value.composing;
        return range.isValid && !range.isCollapsed;
      });

  Future<void> saveNow({bool force = false}) async {
    await _opening;
    if (_disposed || !hasChapter || state == SaveState.blocked) return;
    if (_inflight != null) {
      await _inflight;
      if (state != SaveState.failed) await saveNow(force: force);
      return;
    }
    if (!isDirty && state != SaveState.failed) return;
    if (!force && _isComposing) return;
    final String normalized = _title.text.trim();
    if (normalized != _title.text) {
      _internal = true;
      _title.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _internal = false;
      isDirty = _dirty;
    }
    if (!isDirty && state != SaveState.failed) {
      state = SaveState.clean;
      _debounce?.cancel();
      _notify();
      return;
    }
    final Completer<void> completed = Completer<void>();
    _inflight = completed.future;
    _debounce?.cancel();
    try {
      await _write(_text.text, _title.text, book!, volume!, chapter!);
    } finally {
      _inflight = null;
      completed.complete();
    }
  }

  Future<void> _write(
    String body,
    String heading,
    BookIndex b,
    Volume v,
    ChapterMeta c,
  ) async {
    state = SaveState.saving;
    _notify();
    final String oldTitle = c.title;
    final int oldWords = c.wordCount;
    final DateTime oldUpdated = c.updatedAt;
    try {
      if (body != _savedText || _missing || _needsRetry) {
        await chapters.writeText(b.id, v.id, c.id, body);
      }
      c
        ..title = heading
        ..wordCount = countWords(body)
        ..updatedAt = DateTime.now();
      await books.save(b);
      await library.noteChapterSaved(b);
      _savedText = body;
      _savedTitle = heading;
      _missing = false;
      _needsRetry = false;
      lastSavedAt = c.updatedAt;
      errorMessage = null;
      isDirty = _dirty;
      state = isDirty ? SaveState.dirty : SaveState.clean;
      if (isDirty && !_disposed) _schedule();
      AppLogger.instance.info('chapter.saved', <String, Object?>{
        'book': b.id,
        'chapter': c.id,
        'words': c.wordCount,
      });
    } catch (error) {
      c
        ..title = oldTitle
        ..wordCount = oldWords
        ..updatedAt = oldUpdated;
      _needsRetry = true;
      isDirty = true;
      state = SaveState.failed;
      errorMessage = '保存失败：$error';
      AppLogger.instance.error('chapter.save.failed', <String, Object?>{
        'error': '$error',
      });
    }
    _notify();
  }

  Future<bool> flushForExit() async {
    final DateTime deadline = DateTime.now().add(
      const Duration(milliseconds: 500),
    );
    while (_isComposing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_isComposing) {
      AppLogger.instance.warn('exit.composing.timeout', <String, Object?>{});
    }
    return flush();
  }

  /// 仅供退出保存失败时的内存逃生；常规菜单必须经过 ExportController。
  Future<File?> exportEmergencyDraft() async {
    if (!hasChapter) return null;
    await saveNow(force: true);
    // 保存失败时仍可导出内存正文，不能因为磁盘错误丢掉逃生路径。
    return exports.exportChapter(
      bookTitle: book!.title,
      volumeTitle: displayVolumeTitle(volume!),
      chapterTitle: displayChapterTitle(
        volume!,
        chapter!,
        rawTitle: _title.text,
      ),
      text: _text.text,
      customDir: settings.settings.exportDirectory,
    );
  }

  void clearError() {
    noticeMessage = null;
    if (!_needsRetry && state != SaveState.blocked) errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_openToken;
    _debounce?.cancel();
    _text.removeListener(_onChanged);
    _title.removeListener(_onChanged);
    _text.dispose();
    _title.dispose();
    super.dispose();
  }
}
