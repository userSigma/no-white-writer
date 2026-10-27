import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/export_service.dart';
import 'package:no_white_writer/core/storage/export_snapshot_store.dart';

class _PartialExportWriter extends AtomicFileWriter {
  @override
  Future<void> writeAtomically(File target, String content) async {
    await target.parent.create(recursive: true);
    await File('${target.path}.tmp').writeAsString('partial', flush: true);
    throw const FileSystemException('export injected write failure');
  }
}

class _AfterCommitExportWriter extends AtomicFileWriter {
  @override
  Future<void> writeAtomically(File target, String content) async {
    await super.writeAtomically(target, content);
    throw const FileSystemException('export injected after commit');
  }
}

class _IncompleteExportWriter extends AtomicFileWriter {
  @override
  Future<void> writeAtomically(File target, String content) async {
    await File('${target.path}.tmp').writeAsString('partial', flush: true);
  }
}

void main() {
  late Directory root;
  late AppPaths paths;
  late String out;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nww_export_snapshot_');
    paths = AppPaths(
      dataRoot: Directory('${root.path}/data'),
      documentsRoot: Directory('${root.path}/documents'),
    );
    await paths.ensureLayout();
    out = '${root.path}/out';
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  group('严格只读快照', () {
    late ExportSnapshotStore reader;
    late File index;

    Map<String, dynamic> fixture() => {
      'id': 'book1',
      'title': '顺序书',
      'volumes': [
        {
          'id': 'v2',
          'title': '',
          'order': 9,
          'chapters': [
            {'id': 'c2', 'title': '', 'order': 8},
          ],
        },
        {
          'id': 'v1',
          'title': '卷一',
          'order': 0,
          'chapters': [
            {'id': 'c1', 'title': '章一', 'order': 0},
          ],
        },
      ],
    };
    Map<String, dynamic> volume(Map<String, dynamic> data, int at) =>
        (data['volumes'] as List)[at] as Map<String, dynamic>;
    Future<void> writeIndex(Map<String, dynamic> data) =>
        index.writeAsString(jsonEncode(data), flush: true);

    Future<Map<String, List<int>>> sourceBytes() async {
      final result = <String, List<int>>{};
      await for (final entity in paths.dataRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) result[entity.path] = await entity.readAsBytes();
      }
      return result;
    }

    Future<void> rejectsUnchanged(
      Future<Object?> Function() action,
      Matcher exception,
    ) async {
      final before = await sourceBytes();
      await expectLater(action(), throwsA(exception));
      expect(await sourceBytes(), before);
      expect(await Directory(out).exists(), isFalse);
    }

    setUp(() async {
      reader = ExportSnapshotStore(paths);
      index = paths.bookFile('book1');
      await index.parent.create(recursive: true);
      await writeIndex(fixture());
      for (final pair in [('v1', 'c1'), ('v2', 'c2')]) {
        final file = paths.chapterFile('book1', pair.$1, pair.$2);
        await file.parent.create(recursive: true);
        await file.writeAsString('保留 ${pair.$2}', flush: true);
      }
      await File('${paths.logsDir}/untouched.log').writeAsString('不得修改的日志');
    });

    test('数组顺序不按旧order重排，显式空标题不被填回', () async {
      final before = await sourceBytes();
      final book = await reader.readBook('book1');
      expect(book.volumes.map((v) => v.id), ['v2', 'v1']);
      expect(book.allChapters.map((c) => c.id), ['c2', 'c1']);
      expect(book.volumes.first.title, '');
      expect(book.allChapters.first.title, '');
      book.title = '仅修改返回副本';
      expect((await reader.readBook('book1')).title, '顺序书');
      expect(await sourceBytes(), before);
    });

    test('合法空正文和导出副本的BOM换行归一化不改原字节', () async {
      final file = paths.chapterFile('book1', 'v1', 'c1');
      await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode('甲\r\n乙\r丙')]);
      final before = await sourceBytes();
      expect(await reader.readChapter('book1', 'v1', 'c1'), '甲\n乙\n丙');
      expect(await sourceBytes(), before);
      await file.writeAsBytes([]);
      expect(await reader.readChapter('book1', 'v1', 'c1'), '');
    });

    test('缺正文不能替换为空稿或从bak静默恢复', () async {
      final file = paths.chapterFile('book1', 'v1', 'c1');
      await File('${file.path}.bak').writeAsString('只有备份');
      await file.delete();
      await rejectsUnchanged(
        () => reader.readChapter('book1', 'v1', 'c1'),
        isA<FileSystemException>(),
      );
    });

    test('坏UTF8正文不能容错替换', () async {
      await paths.chapterFile('book1', 'v1', 'c1').writeAsBytes([0xFF, 0x80]);
      await rejectsUnchanged(
        () => reader.readChapter('book1', 'v1', 'c1'),
        isA<FormatException>(),
      );
    });

    test('注入的读取异常原样拒绝且不写作品或日志', () async {
      reader = ExportSnapshotStore(
        paths,
        readBytes: (file) async {
          throw FileSystemException(
            'snapshot injected read failure',
            file.path,
          );
        },
      );
      await rejectsUnchanged(
        () => reader.readBook('book1'),
        isA<FileSystemException>(),
      );
      await rejectsUnchanged(
        () => reader.readChapter('book1', 'v1', 'c1'),
        isA<FileSystemException>(),
      );
    });

    for (final name in [
      '.chapter-move.json',
      '.chapter-move.json.tmp',
      'book.json.tmp',
    ]) {
      test('$name 未解决时不恢复、不重建、不导出', () async {
        await File('${index.parent.path}/$name').writeAsBytes([255, 0, 3]);
        await rejectsUnchanged(
          () => reader.readBook('book1'),
          isA<FileSystemException>(),
        );
        await rejectsUnchanged(
          () => reader.readChapter('book1', 'v1', 'c1'),
          isA<FileSystemException>(),
        );
      });
    }

    for (final suffix in ['.tmp', '.bak.tmp']) {
      test('正文$suffix 保持原样并阻止读取', () async {
        await File('${paths.chapterFile('book1', 'v1', 'c1').path}$suffix')
            .writeAsString('尚未完成的正文');
        await rejectsUnchanged(
          () => reader.readChapter('book1', 'v1', 'c1'),
          isA<FileSystemException>(),
        );
      });
    }

    test('较新bak不擅自恢复，较旧bak允许读取且字节保持', () async {
      final file = paths.chapterFile('book1', 'v1', 'c1');
      final backup = File('${file.path}.bak');
      await backup.writeAsString('备份原字节');
      await backup.setLastModified(
        DateTime.now().add(const Duration(minutes: 10)),
      );
      await rejectsUnchanged(
        () => reader.readChapter('book1', 'v1', 'c1'),
        isA<FileSystemException>(),
      );
      await backup.setLastModified(DateTime(2000));
      final before = await sourceBytes();
      expect(await reader.readChapter('book1', 'v1', 'c1'), '保留 c1');
      expect(await sourceBytes(), before);
    });

    for (final bytes in [
      utf8.encode('{broken-json'),
      [0xFF],
      utf8.encode('[]'),
    ]) {
      test('损坏或非对象索引拒绝 ${bytes.join(',')}', () async {
        await index.writeAsBytes(bytes);
        await rejectsUnchanged(
          () => reader.readBook('book1'),
          isA<FormatException>(),
        );
      });
    }

    final invalid = <String, void Function(Map<String, dynamic>)>{
      '作品ID不符': (d) => d['id'] = 'other',
      '缺卷列表': (d) => d.remove('volumes'),
      '非对象卷条目': (d) => (d['volumes'] as List).add('broken'),
      '重复卷ID': (d) => volume(d, 1)['id'] = 'v2',
      '大小写重复卷ID': (d) => volume(d, 1)['id'] = 'V2',
      '大小写重复章ID': (d) => (volume(d, 1)['chapters'] as List).first['id'] = 'C2',
      '错误标题类型': (d) => volume(d, 1)['title'] = 42,
      '错误编号对象': (d) => volume(d, 0)['numbering'] = [],
      '编号换行': (d) =>
          volume(d, 0)['numbering'] = {'enabled': true, 'prefix': '第\n'},
      '未知编号格式': (d) =>
          volume(d, 0)['numbering'] = {'enabled': true, 'style': 'other'},
      '卷ID越界': (d) => volume(d, 0)['id'] = '../outside',
      '缺章列表': (d) => volume(d, 0).remove('chapters'),
      '非对象章条目': (d) => (volume(d, 0)['chapters'] as List).add('broken'),
      '跨卷重复章ID': (d) => (volume(d, 1)['chapters'] as List).first['id'] = 'c2',
      '章ID越界': (d) =>
          (volume(d, 0)['chapters'] as List).first['id'] = '../outside',
      '非法启用规则': (d) => volume(d, 0)['numbering'] = {'enabled': true, 'step': 0},
      '编号非整数': (d) =>
          volume(d, 0)['numbering'] = {'enabled': true, 'step': 1.5},
      '编号溢出': (d) {
        volume(d, 0)['numbering'] = {'enabled': true, 'start': 999999999};
        (volume(d, 0)['chapters'] as List).add({
          'id': 'c3',
          'title': '溢出',
          'order': 1,
        });
      },
    };
    for (final entry in invalid.entries) {
      test('${entry.key} 不被过滤成看似有效的索引', () async {
        final data = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
        entry.value(data);
        await writeIndex(data);
        await rejectsUnchanged(
          () => reader.readBook('book1'),
          isA<FormatException>(),
        );
      });
    }

    test('请求路径ID穿越在触及作品外文件前拒绝', () async {
      await rejectsUnchanged(
        () => reader.readBook('../outside'),
        isA<FormatException>(),
      );
      await rejectsUnchanged(
        () => reader.readChapter('book1', '../outside', 'c1'),
        isA<FormatException>(),
      );
      await rejectsUnchanged(
        () => reader.readChapter('book1', 'v1', '../outside'),
        isA<FormatException>(),
      );
    });
  });

  test('卷导出实际文件保留分隔符和当前顺序，清洗路径且不覆盖', () async {
    final service = ExportService(paths, const AtomicFileWriter());
    const chapters = [(title: '第2章', text: '乙\n'), (title: '第1章', text: '')];
    final first = await service.exportVolume(
      bookTitle: '书/名',
      volumeTitle: '卷:二',
      chapters: chapters,
      customDir: out,
    );
    final second = await service.exportVolume(
      bookTitle: '书/名',
      volumeTitle: '卷:二',
      chapters: chapters,
      customDir: out,
    );
    expect(first.path, endsWith('卷_二.txt'));
    expect(second.path, endsWith('卷_二 (2).txt'));
    const expected =
        '──── 卷：卷:二 ────\n\n'
        '──── 章：第2章 ────\n\n乙\n──── 章：第1章 ────\n\n\n';
    expect(await first.readAsBytes(), utf8.encode(expected));
    expect(await second.readAsBytes(), await first.readAsBytes());
    expect(await Directory(out).exists(), isTrue);
    expect(
      await Directory('${paths.documentsRoot.path}/不白写作').exists(),
      isFalse,
    );
  });

  test('书导出实际文件包含空卷卷头，空文件名后备且避开旧临时物', () async {
    final service = ExportService(paths, const AtomicFileWriter());
    final pending = File('$out/未命名.txt.tmp');
    await pending.parent.create(recursive: true);
    await pending.writeAsBytes([7, 8, 9]);
    final file = await service.exportBook(
      bookTitle: '',
      customDir: out,
      volumes: [
        (volumeTitle: '空卷', chapters: []),
        (volumeTitle: '卷二', chapters: [(title: '章', text: '正文')]),
      ],
    );
    expect(file.path, endsWith('未命名 (2).txt'));
    expect(
      await file.readAsString(),
      '──── 卷：空卷 ────\n\n──── 卷：卷二 ────\n\n──── 章：章 ────\n\n正文\n',
    );
    expect(await pending.readAsBytes(), [7, 8, 9]);
  });

  for (final scope in ['卷', '书']) {
    test('$scope 导出失败只清理自身临时物，之后可重试', () async {
      final before = await paths.libraryFile.exists();
      Future<File> exportWith(AtomicFileWriter writer) {
        final service = ExportService(paths, writer);
        return scope == '卷'
            ? service.exportVolume(
                bookTitle: '书',
                volumeTitle: '卷',
                chapters: [(title: '章', text: '正文')],
                customDir: out,
              )
            : service.exportBook(
                bookTitle: '书',
                volumes: [
                  (volumeTitle: '卷', chapters: [(title: '章', text: '正文')]),
                ],
                customDir: out,
              );
      }

      await expectLater(
        exportWith(_PartialExportWriter()),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await Directory(out)
            .list(recursive: true)
            .where((e) => e is File)
            .toList(),
        isEmpty,
      );
      final file = await exportWith(const AtomicFileWriter());
      expect(
        await file.readAsString(),
        '──── 卷：卷 ────\n\n──── 章：章 ────\n\n正文\n',
      );
      expect(await File('${file.path}.tmp').exists(), isFalse);
      expect(await paths.libraryFile.exists(), before);
    });
  }

  test('导出原子写失败清理本次临时物而不改变既有导出', () async {
    final existing = File('$out/书/卷/章.txt');
    await existing.parent.create(recursive: true);
    await existing.writeAsBytes([1, 2, 3, 4], flush: true);
    final service = ExportService(paths, _PartialExportWriter());
    await expectLater(
      service.exportChapter(
        bookTitle: '书',
        volumeTitle: '卷',
        chapterTitle: '章',
        text: '新正文',
        customDir: out,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await existing.readAsBytes(), [1, 2, 3, 4]);
    expect(
      await existing.parent.list().map((f) => f.uri.pathSegments.last).toList(),
      ['章.txt'],
    );
  });

  test('提交后异常须核实完整字节再认定导出成功', () async {
    final service = ExportService(paths, _AfterCommitExportWriter());
    final file = await service.exportChapter(
      bookTitle: '书',
      volumeTitle: '卷',
      chapterTitle: '章',
      text: '已完整提交',
      customDir: out,
    );
    expect(await file.readAsString(), '已完整提交\n');
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('写入器返回但只有残片时不冒充完整导出', () async {
    final service = ExportService(paths, _IncompleteExportWriter());
    await expectLater(
      service.exportChapter(
        bookTitle: '书',
        volumeTitle: '卷',
        chapterTitle: '章',
        text: '应完整写入',
        customDir: out,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory('$out/书/卷').list().toList(), isEmpty);
  });

  test('预先存在的导出临时物不被覆盖或清理', () async {
    final pending = File('$out/书/卷/章.txt.tmp');
    await pending.parent.create(recursive: true);
    await pending.writeAsBytes([9, 8, 7], flush: true);
    final service = ExportService(paths, const AtomicFileWriter());
    final file = await service.exportChapter(
      bookTitle: '书',
      volumeTitle: '卷',
      chapterTitle: '章',
      text: '新正文',
      customDir: out,
    );
    expect(file.path, endsWith('章 (2).txt'));
    expect(await file.readAsString(), '新正文\n');
    expect(await pending.readAsBytes(), [9, 8, 7]);
  });
}
