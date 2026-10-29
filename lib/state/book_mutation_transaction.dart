import '../core/models.dart';
import '../core/storage/book_store.dart';

/// Shared commit boundary for book metadata and structure changes.
///
/// Callers enter the library operation gate before taking a snapshot. Applying
/// committed state preserves the objects held by the editor; recovery always
/// follows actual disk state rather than pretending a completed commit rolled back.
class BookMutationTransaction {
  BookMutationTransaction({
    required this.bookStore,
    required this.findSummary,
    required this.saveSummary,
    required this.notifyChanged,
  });

  final BookStore bookStore;
  final BookSummary? Function(String bookId) findSummary;
  final Future<void> Function(BookIndex book) saveSummary;
  final void Function() notifyChanged;
  final Set<String> blockedBooks = <String>{};

  BookIndex copy(BookIndex book) => BookIndex.fromJson(book.toJson());

  Future<void> commit(BookIndex book, BookIndex next) async {
    try {
      await bookStore.save(next);
      apply(book, next);
      await saveSummary(book);
    } catch (_) {
      await syncActual(book);
      rethrow;
    }
  }

  Future<void> syncActual(BookIndex book) async {
    try {
      final summary = findSummary(book.id);
      if (summary == null) throw StateError('作品摘要缺失');
      apply(book, await bookStore.load(summary));
      blockedBooks.remove(book.id);
    } catch (_) {
      blockedBooks.add(book.id);
      rethrow;
    } finally {
      notifyChanged();
    }
  }

  void apply(BookIndex book, BookIndex next) {
    final volumes = {for (final v in book.volumes) v.id: v};
    final chapters = {for (final c in book.allChapters) c.id: c};
    book
      ..title = next.title
      ..notes = next.notes
      ..globalNumbering = next.globalNumbering;
    final ordered = <Volume>[];
    for (final v in next.volumes) {
      final current = volumes[v.id] ?? v;
      final list = <ChapterMeta>[];
      for (final c in v.chapters) {
        final existing = chapters[c.id] ?? c;
        existing
          ..title = c.title
          ..order = c.order
          ..wordCount = c.wordCount
          ..updatedAt = c.updatedAt;
        list.add(existing);
      }
      current
        ..title = v.title
        ..order = v.order
        ..numbering = v.numbering
        ..numberingMode = v.numberingMode;
      current.chapters
        ..clear()
        ..addAll(list);
      ordered.add(current);
    }
    book.volumes
      ..clear()
      ..addAll(ordered);
    notifyChanged();
  }

  static void normalize(BookIndex book) {
    for (int v = 0; v < book.volumes.length; v++) {
      book.volumes[v].order = v;
      for (int c = 0; c < book.volumes[v].chapters.length; c++) {
        book.volumes[v].chapters[c].order = c;
      }
    }
  }
}
