import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/chapter_display.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';

BookIndex _book(List<Volume> volumes) =>
    BookIndex(id: 'b', title: '书', volumes: volumes);

void main() {
  test('卷内独立编号按列表顺序而非旧order计算且关闭原样显示', () {
    final a = ChapterMeta(id: 'a', title: '第 7 章 原名', order: 90);
    final b = ChapterMeta(id: 'b', title: '正文外标题', order: 99);
    final v = Volume(
      id: 'v',
      title: '卷',
      order: 0,
      numberingMode: VolumeNumberingMode.independent,
      chapters: [a, b],
    );
    final book = _book([v]);
    expect(displayChapterTitle(book, v, a), a.title);
    v.numbering = const ChapterNumbering(
      enabled: true,
      prefix: '',
      suffix: '',
      padding: 3,
      start: 0,
      step: 2,
    );
    expect(displayChapterTitle(book, v, a), '000 第 7 章 原名');
    expect(displayChapterTitle(book, v, b, rawTitle: '草稿'), '002 草稿');
    v.chapters.insert(0, v.chapters.removeLast());
    expect(displayChapterTitle(book, v, a), '002 第 7 章 原名');
    expect(a.title, '第 7 章 原名');
  });

  test('跟随全局的卷按全书连续序号且全局关闭时不编号', () {
    final v1 = Volume(
      id: 'v1',
      title: '一',
      order: 0,
      chapters: [
        ChapterMeta(id: 'a', title: '甲', order: 0),
        ChapterMeta(id: 'b', title: '乙', order: 1),
      ],
    );
    final v2 = Volume(
      id: 'v2',
      title: '二',
      order: 1,
      chapters: [ChapterMeta(id: 'c', title: '丙', order: 0)],
    );
    final book = _book([v1, v2]);
    // 全局关闭：跟随全局的卷不显示编号。
    expect(displayChapterTitle(book, v1, v1.chapters[0]), '甲');
    expect(effectiveChapterNumbering(book, v1), isNull);
    book.globalNumbering = const ChapterNumbering(enabled: true);
    // 全局开启：跨卷连续编号。
    expect(displayChapterTitle(book, v1, v1.chapters[0]), '第1章 甲');
    expect(displayChapterTitle(book, v1, v1.chapters[1]), '第2章 乙');
    expect(displayChapterTitle(book, v2, v2.chapters[0]), '第3章 丙');
    expect(chapterNumberIndex(book, v2, 'c'), 2);
    expect(chapterNumberLabel(book, v1, 'b'), '第2章');
    expect(globalNumberingChapterCount(book), 3);
    // 卷内独立编号的卷不占用全局连续序号。
    v2.numberingMode = VolumeNumberingMode.independent;
    v2.numbering = const ChapterNumbering(enabled: true, start: 9);
    expect(displayChapterTitle(book, v2, v2.chapters[0]), '第9章 丙');
    expect(globalNumberingChapterCount(book), 2);
    // 不编号的卷永远没有编号，也不占全局序号。
    final v3 = Volume(
      id: 'v3',
      title: '三',
      order: 2,
      numberingMode: VolumeNumberingMode.none,
      chapters: [ChapterMeta(id: 'd', title: '丁', order: 0)],
    );
    book.volumes.add(v3);
    expect(displayChapterTitle(book, v3, v3.chapters[0]), '丁');
    expect(effectiveChapterNumbering(book, v3), isNull);
    expect(globalNumberingChapterCount(book), 2);
  });

  test('旧卷缺编号字段默认关闭并持久化独立规则', () {
    final volume = Volume.fromJson({'id': 'v', 'title': '旧卷', 'order': 0});
    expect(volume.toJson()['numbering'], {
      'enabled': false,
      'prefix': '第',
      'suffix': '章',
      'style': 'arabic',
      'padding': 1,
      'start': 1,
      'step': 1,
    });
  });

  test('旧数据迁移：已启用独立编号的卷迁移为卷内独立，其余跟随全局', () {
    final migrated = Volume.fromJson({
      'id': 'v1',
      'title': '旧卷一',
      'order': 0,
      'numbering': {'enabled': true, 'prefix': '', 'suffix': '', 'start': 0},
    });
    expect(migrated.numberingMode, VolumeNumberingMode.independent);
    expect(migrated.numbering.start, 0);
    final plain = Volume.fromJson({
      'id': 'v2',
      'title': '旧卷二',
      'order': 1,
      'numbering': {'enabled': false},
    });
    expect(plain.numberingMode, VolumeNumberingMode.followGlobal);
    // 显式 numberingMode 字段优先于迁移推导。
    final explicit = Volume.fromJson({
      'id': 'v3',
      'title': '新卷',
      'order': 2,
      'numberingMode': 'none',
      'numbering': {'enabled': true},
    });
    expect(explicit.numberingMode, VolumeNumberingMode.none);
    // 未知的 numberingMode 值回退到迁移推导，不损坏数据。
    final unknown = Volume.fromJson({
      'id': 'v4',
      'title': '脏卷',
      'order': 3,
      'numberingMode': 'broken',
      'numbering': {'enabled': true},
    });
    expect(unknown.numberingMode, VolumeNumberingMode.independent);
    // 新卷默认跟随全局，且模式随 toJson 往返保留。
    expect(
      Volume(id: 'v5', title: '新', order: 4).numberingMode,
      VolumeNumberingMode.followGlobal,
    );
    expect(migrated.toJson()['numberingMode'], 'independent');
    expect(plain.toJson()['numberingMode'], 'follow-global');
  });

  test('书籍级全局编号持久化往返且旧书缺字段默认关闭', () {
    final legacy = BookIndex.fromJson({
      'id': 'b',
      'title': '旧书',
      'schemaVersion': 1,
      'volumes': [
        {'id': 'v', 'title': '卷', 'order': 0},
      ],
    });
    expect(legacy.globalNumbering.enabled, isFalse);
    legacy.globalNumbering = const ChapterNumbering(
      enabled: true,
      prefix: '',
      suffix: '话',
      padding: 2,
      start: 0,
    );
    final round = BookIndex.fromJson(legacy.toJson());
    expect(round.globalNumbering.enabled, isTrue);
    expect(round.globalNumbering.suffix, '话');
    expect(round.globalNumbering.padding, 2);
    expect(round.globalNumbering.start, 0);
    // 损坏的全局编号对象回退默认而不是抛异常。
    final corrupt = BookIndex.fromJson({
      'id': 'b2',
      'title': '坏书',
      'volumes': [],
      'globalNumbering': {'enabled': 'yes'},
    });
    expect(corrupt.globalNumbering.enabled, isFalse);
  });

  test('普通中文数词覆盖零与跨万亿分组', () {
    const expected = <int, String>{
      0: '零',
      1: '一',
      10: '十',
      11: '十一',
      20: '二十',
      101: '一百零一',
      1001: '一千零一',
      1010: '一千零一十',
      10000: '一万',
      10001: '一万零一',
      10010: '一万零一十',
      11000: '一万一千',
      100000: '十万',
      100000001: '一亿零一',
      100010001: '一亿零一万零一',
      110000000: '一亿一千万',
      999999999: '九亿九千九百九十九万九千九百九十九',
    };
    for (final entry in expected.entries) {
      final rule = ChapterNumbering(
        enabled: true,
        style: 'chinese',
        start: entry.key,
      );
      expect(rule.label(0), '第${entry.value}章', reason: '${entry.key}');
    }
  });

  test('规则范围单行与序列溢出明确拒绝不环绕', () {
    const invalid = [
      ChapterNumbering(start: -1),
      ChapterNumbering(start: 1000000000),
      ChapterNumbering(step: 0),
      ChapterNumbering(step: 1000000000),
      ChapterNumbering(padding: 0),
      ChapterNumbering(padding: 10),
      ChapterNumbering(prefix: '第\n'),
      ChapterNumbering(suffix: '\r章'),
      ChapterNumbering(style: 'script'),
    ];
    for (final rule in invalid) {
      expect(() => rule.validate(1), throwsFormatException);
    }
    const rule = ChapterNumbering(enabled: true, start: 999999999);
    expect(() => rule.validate(1), returnsNormally);
    expect(() => rule.validate(2), throwsFormatException);
    expect(() => rule.label(1), throwsFormatException);
    expect(() => rule.label(-1), throwsFormatException);
  });

  test('卷索引往返保留自定义编号而不改原始章名', () {
    final volume = Volume.fromJson({
      'id': 'v',
      'title': '原卷',
      'order': 4,
      'numbering': {
        'enabled': true,
        'prefix': '',
        'suffix': '',
        'style': 'chinese',
        'padding': 3,
        'start': 0,
        'step': 2,
      },
      'chapters': [
        {'id': 'c', 'title': '第 1 章 原名', 'order': 17},
      ],
    });
    expect((volume.toJson()['numbering'] as Map?)?['start'], 0);
    expect(volume.chapters.single.title, '第 1 章 原名');
    // 旧数据里显式启用编号的卷迁移后仍可独立编号显示。
    expect(volume.numberingMode, VolumeNumberingMode.independent);
  });
}
