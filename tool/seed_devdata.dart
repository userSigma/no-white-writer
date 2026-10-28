import 'dart:io';

import 'package:no_white_writer/core/logging/app_logger.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';
import 'package:no_white_writer/core/storage/library_store.dart';
import 'package:no_white_writer/core/text/word_count.dart';

/// 生成开发用示例数据（数据根 = 仓库下 .devdata），便于人工验收界面。
Future<void> main() async {
  final Directory repo = Directory.current;
  final Directory dataRoot = Directory('${repo.path}\\.devdata');
  final Directory docsRoot = Directory('${repo.path}\\.devdata-docs');
  final AppPaths paths = AppPaths(dataRoot: dataRoot, documentsRoot: docsRoot);
  await paths.ensureLayout();
  await AppLogger.instance.init(Directory(paths.logsDir));

  const AtomicFileWriter writer = AtomicFileWriter();
  final ChapterStore chapters = ChapterStore(paths);
  final BookStore books = BookStore(paths, writer, chapters);
  final LibraryStore libraryStore = LibraryStore(paths, writer);

  final LibraryIndex library = LibraryIndex();
  Future<void> seedBook({
    required String title,
    required String volumeTitle,
    required List<(String, String)> chapterList,
  }) async {
    final String bookId = 'dev-${title.hashCode.abs()}';
    final BookIndex book = BookIndex(id: bookId, title: title);
    final Volume volume = Volume(
      id: 'vol-${title.hashCode.abs()}',
      title: volumeTitle,
      order: 0,
    );
    for (int i = 0; i < chapterList.length; i++) {
      final (String chapterTitle, String text) = chapterList[i];
      final String chapterId = 'ch-$bookId-$i';
      final ChapterMeta chapter = ChapterMeta(
        id: chapterId,
        title: chapterTitle,
        order: i,
        wordCount: countWords(text),
        updatedAt: DateTime.now().subtract(Duration(minutes: 30 * (i + 1))),
      );
      await chapters.writeText(bookId, volume.id, chapterId, text);
      volume.chapters.add(chapter);
    }
    book.volumes.add(volume);
    await books.save(book);
    library.books.add(
      BookSummary(
        id: bookId,
        title: title,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
        coverSeed: title.hashCode,
        lastOpenedChapterId: volume.chapters.first.id,
        volumeCount: book.volumes.length,
        chapterCount: book.allChapters.length,
        wordCount: book.totalWordCount,
      ),
    );
    stdout.writeln('seeded $title (${book.allChapters.length} chapters)');
  }

  const String p1 =
      '　　'
      '雨落在旧城的瓦上，声音像有人在数铜钱。沈砚把窗推开一条缝，让潮气进来，'
      '桌上的稿纸被风掀起一角。\n'
      '　　他按住纸，继续写昨天没写完的那一段：一个人如果连自己的名字都记不清，'
      '还剩下什么可以交出去？\n'
      '　　楼下卖馄饨的摊子刚支起来，白汽在巷口散成一团。';
  const String p2 =
      '　　'
      '第二日天没亮，邮差送来一封没有署名的信。信封里只有半张地图，'
      '角上画着一只闭眼的鸟。\n'
      '　　沈砚把地图摊在灯下，发现背面用很淡的墨写着一行小字：'
      '“别去北门，那里有人等你很久了。”';

  await seedBook(
    title: '旧城记',
    volumeTitle: '第一卷 · 雨巷',
    chapterList: <(String, String)>[('第一章 数铜钱的人', p1), ('第二章 闭眼的鸟', p2)],
  );
  await seedBook(
    title: '白夜抄',
    volumeTitle: '卷一 · 长夜',
    chapterList: <(String, String)>[
      (
        '第一章 灯下',
        '　　'
            '灯芯爆了一下，屋里亮了一瞬。她把针线放下，听见院墙外有脚步声经过，'
            '不快不慢，像在丈量这条巷子的长度。',
      ),
    ],
  );

  await libraryStore.save(library);
  stdout.writeln('library written: ${paths.libraryFile.path}');
}
