import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';
import 'package:no_white_writer/core/chapter_display.dart';
import 'package:no_white_writer/core/models.dart';

import 'support/app_harness.dart';

void main() {
  test('仅新建作品默认启用汉字编号，追加与重载不改写作者标题', () async {
    final h = await createHarness();
    addTearDown(h.dispose);
    final summary = await h.app.library.createBook('新作品');
    final book = await h.app.library.readBookDetails(summary);
    final volume = book.volumes.first;
    expect(book.globalNumbering.enabled, isTrue);
    expect(book.globalNumbering.style, 'chinese');
    expect(displayChapterTitle(book, volume, volume.chapters.first), '第一章');
    final second = await h.app.library.structure.appendChapter(book, volume);
    expect(displayChapterTitle(book, volume, second), '第二章');
    final named = await h.app.library.structure.appendChapter(
      book,
      volume,
      title: '重逢',
    );
    expect(named.title, '重逢');
    expect(displayChapterTitle(book, volume, named), '第三章 重逢');
    final reloaded = await h.app.library.readBookDetails(summary);
    expect(reloaded.globalNumbering.style, 'chinese');
    expect(reloaded.globalNumbering.enabled, isTrue);
    expect(reloaded.allChapters.map((chapter) => chapter.title), [
      '',
      '',
      '重逢',
    ]);
  });

  test('旧数据缺省保持关闭且显式阿拉伯数字规则和作者名保持原样', () {
    final old = BookIndex.fromJson({
      'id': 'old',
      'title': '旧作品',
      'volumes': [
        {
          'id': 'v',
          'title': '旧卷',
          'order': 0,
          'chapters': [
            {'id': 'c', 'title': '第 7 章 原名', 'order': 0},
          ],
        },
      ],
    });
    expect(old.globalNumbering.enabled, isFalse);
    expect(old.globalNumbering.style, 'arabic');
    expect(
      displayChapterTitle(old, old.volumes.first, old.allChapters.first),
      '第 7 章 原名',
    );
    old.globalNumbering = const ChapterNumbering(enabled: true, start: 7);
    final roundTrip = BookIndex.fromJson(old.toJson());
    expect(roundTrip.globalNumbering.style, 'arabic');
    expect(chapterNumberLabel(roundTrip, roundTrip.volumes.first, 'c'), '第7章');
    expect(roundTrip.allChapters.first.title, '第 7 章 原名');
  });
}
