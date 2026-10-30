import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/chapter_numbering.dart';

// Only the pure rule module is imported: labels/JSON must not need book models.
void main() {
  test('纯编号规则独立完成旧字段 JSON 往返及阿拉伯数字格式化', () {
    final json = <String, dynamic>{
      'enabled': true,
      'prefix': '节 ',
      'suffix': ' ·',
      'style': 'arabic',
      'padding': 3,
      'start': 7,
      'step': 2,
    };
    final rule = ChapterNumbering.fromJson(json);
    rule.validate(3);
    expect(rule.toJson(), json);
    expect(rule.label(0), '节 007 ·');
    expect(rule.label(2), '节 011 ·');
  });

  test('缺失旧编号字段维持默认值，中文编号无模型也可使用', () {
    final legacy = ChapterNumbering.fromJson({});
    expect(legacy.toJson(), const ChapterNumbering().toJson());
    const rule = ChapterNumbering(enabled: true, style: 'chinese', start: 10);
    expect(rule.label(0), '第十章');
    expect(rule.label(11), '第二十一章');
  });

  test('纯规则保留负索引、超范围及配置校验边界', () {
    const rule = ChapterNumbering(
      enabled: true,
      start: ChapterNumbering.maxValue,
    );
    expect(() => rule.label(-1), throwsFormatException);
    expect(() => rule.label(1), throwsFormatException);
    expect(() => rule.validate(2), throwsFormatException);
    expect(
      () => const ChapterNumbering(step: 0).validate(1),
      throwsFormatException,
    );
  });
}
