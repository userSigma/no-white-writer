import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('页面显式接收依赖，不再持有整个 AppContext', () {
    for (final path in [
      'lib/ui/shelf_page.dart',
      'lib/ui/editor_page.dart',
      'lib/ui/settings_menu.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('AppContext')), reason: path);
      expect(source, isNot(contains('app_context.dart')), reason: path);
    }
  });

  test('导出控制器由组合根创建，不在 AppContext 中延迟装配', () {
    final context = File('lib/app_context.dart').readAsStringSync();
    expect(context, contains('required this.exporter'));
    expect(context, contains('final ExportController exporter;'));
    expect(context, isNot(contains('ExportController get exporter')));
    expect(context, isNot(contains('ExportController(')));
  });

  test('纯编号规则不再反向依赖书籍模型，显示投影单向依赖模型', () {
    final rule = File('lib/core/chapter_numbering.dart').readAsStringSync();
    expect(rule, isNot(contains("import 'models.dart'")));
    expect(rule, isNot(contains('BookIndex')));
    expect(rule, contains('class ChapterNumbering'));
    final projection = File('lib/core/chapter_display.dart');
    expect(projection.existsSync(), isTrue);
    expect(projection.readAsStringSync(), contains("import 'models.dart'"));
  });

  test('设置入口不再持有颜色编辑器、主题 CRUD 和目录草稿实现', () {
    final source = File('lib/ui/settings_menu.dart').readAsStringSync();
    for (final implementation in [
      'class _CustomThemeDialog',
      'class _ColorField',
      'class _ThemePreview',
      'Future<void> _createCustomTheme',
      'Future<void> _renameCustomTheme',
      'Future<void> _deleteCustomTheme',
      'Future<void> open() => _open()',
      'Widget _row(',
      'TextEditingController _path',
      'Future<void> _savePath',
      'settings.exportDir.confirm.title',
    ]) {
      expect(source, isNot(contains(implementation)));
    }
    expect(
      File('lib/ui/settings/custom_theme_section.dart').existsSync(),
      isTrue,
    );
  });

  test('AppContext 只暴露恢复章节数量，不保留恢复记录列表', () {
    final source = File('lib/app_context.dart').readAsStringSync();
    expect(source, contains('final int recoveredChapterCount;'));
    expect(source, isNot(contains('final List<RecoveryRecord> recovered;')));
    expect(source, isNot(contains('this.recovered =')));
  });
}
