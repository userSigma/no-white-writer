import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';

void main() {
  test('独立显示号按列表顺序而非旧order计算且关闭原样显示', () {
    final a = ChapterMeta(id: 'a', title: '第 7 章 原名', order: 90);
    final b = ChapterMeta(id: 'b', title: '正文外标题', order: 99);
    final v = Volume(id: 'v', title: '卷', order: 0, chapters: [a, b]);
    expect(displayChapterTitle(v, a), a.title);
    v.numbering = const ChapterNumbering(
      enabled: true,
      prefix: '',
      suffix: '',
      padding: 3,
      start: 0,
      step: 2,
    );
    expect(displayChapterTitle(v, a), '000 第 7 章 原名');
    expect(displayChapterTitle(v, b, rawTitle: '草稿'), '002 草稿');
    v.chapters.insert(0, v.chapters.removeLast());
    expect(displayChapterTitle(v, a), '002 第 7 章 原名');
    expect(a.title, '第 7 章 原名');
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
  });
}
