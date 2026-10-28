import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';
import 'package:no_white_writer/core/storage/export_service.dart';

void main() {
  late Directory temp;
  late AppPaths paths;
  late ChapterStore chapters;
  const String bookId = 'book1';
  const String volumeId = 'vol1';
  const String chapterId = 'ch1';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nww_storage_');
    paths = AppPaths(
      dataRoot: Directory('${temp.path}/data'),
      documentsRoot: Directory('${temp.path}/docs'),
    );
    await paths.ensureLayout();
    chapters = ChapterStore(paths);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  BookIndex sampleBook() {
    return BookIndex(
      id: bookId,
      title: '测试书',
      volumes: <Volume>[
        Volume(
          id: volumeId,
          title: '第一卷',
          order: 0,
          chapters: <ChapterMeta>[
            ChapterMeta(id: chapterId, title: '第一章', order: 0),
          ],
        ),
      ],
    );
  }

  group('ChapterStore 原子保存', () {
    test('首次写入直接落地，第二次写入把旧正文转成 .bak', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await chapters.writeText(bookId, volumeId, chapterId, '第一版');
      expect(await chapters.readText(bookId, volumeId, chapterId), '第一版');
      expect(await File('${txt.path}.bak').exists(), isFalse);
      expect(await File('${txt.path}.tmp').exists(), isFalse);

      await chapters.writeText(bookId, volumeId, chapterId, '第二版');
      expect(await chapters.readText(bookId, volumeId, chapterId), '第二版');
      expect(await File('${txt.path}.bak').readAsString(), '第一版');
      expect(await File('${txt.path}.tmp').exists(), isFalse);
    });

    test('readText 归一化：去 BOM、CRLF 与 CR 都变 LF', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await txt.parent.create(recursive: true);
      await txt.writeAsBytes(<int>[
        0xEF, 0xBB, 0xBF, // BOM
        ...utf8.encode('第一行\r\n第二行\r第三行'),
      ]);
      expect(
        await chapters.readText(bookId, volumeId, chapterId),
        '第一行\n第二行\n第三行',
      );
    });

    test('readText 缺文件返回 null', () async {
      expect(await chapters.readText(bookId, volumeId, chapterId), isNull);
    });
  });

  group('ChapterStore 崩溃恢复', () {
    test('tmp 比主文件新：tmp 转正，旧正文退成 .bak', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await chapters.writeText(bookId, volumeId, chapterId, '旧正文');
      final File tmp = File('${txt.path}.tmp');
      await tmp.writeAsString('新正文');
      await tmp.setLastModified(DateTime.now().add(const Duration(minutes: 1)));

      final List<RecoveryRecord> records = await chapters.recover(sampleBook());
      expect(records, hasLength(1));
      expect(records.single.source, 'tmp');
      expect(await chapters.readText(bookId, volumeId, chapterId), '新正文');
      expect(await File('${txt.path}.bak').readAsString(), '旧正文');
      expect(await tmp.exists(), isFalse);
    });

    test('tmp 比主文件旧：直接丢弃 tmp，不产生记录', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await chapters.writeText(bookId, volumeId, chapterId, '新正文');
      final File tmp = File('${txt.path}.tmp');
      await tmp.writeAsString('旧残稿');
      await tmp.setLastModified(DateTime(2000));

      final List<RecoveryRecord> records = await chapters.recover(sampleBook());
      expect(records, isEmpty);
      expect(await tmp.exists(), isFalse);
      expect(await chapters.readText(bookId, volumeId, chapterId), '新正文');
    });

    test('主文件缺失但 .bak 在：从 .bak 还原', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await txt.parent.create(recursive: true);
      await File('${txt.path}.bak').writeAsString('备份正文');

      final List<RecoveryRecord> records = await chapters.recover(sampleBook());
      expect(records.single.source, 'bak');
      expect(await chapters.readText(bookId, volumeId, chapterId), '备份正文');
    });

    test('主文件缺失且无 .bak：记 missing', () async {
      final List<RecoveryRecord> records = await chapters.recover(sampleBook());
      expect(records.single.isMissing, isTrue);
      expect(records.single.chapterTitle, '第一章');
    });

    test('tmp 转正失败必须抛出并保留原现场', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await chapters.writeText(bookId, volumeId, chapterId, '旧正文');
      final File tmp = File('${txt.path}.tmp');
      await tmp.writeAsString('新正文');
      await tmp.setLastModified(DateTime.now().add(const Duration(minutes: 1)));
      final Directory conflictingBak = Directory('${txt.path}.bak');
      await conflictingBak.create();

      await expectLater(
        chapters.recover(sampleBook()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await txt.readAsString(), '旧正文');
      expect(await tmp.readAsString(), '新正文');
      expect(await conflictingBak.exists(), isTrue);
    });

    test('bak 恢复失败必须抛出且不当作缺章', () async {
      final File txt = chapters.fileOf(bookId, volumeId, chapterId);
      await txt.parent.create(recursive: true);
      final File bak = File('${txt.path}.bak');
      await bak.writeAsString('备份正文');
      await Directory(txt.path).create();

      await expectLater(
        chapters.recover(sampleBook()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await bak.readAsString(), '备份正文');
      expect(await Directory(txt.path).exists(), isTrue);
    });
  });

  group('ExportService', () {
    late ExportService exports;

    setUp(() {
      exports = ExportService(paths, const AtomicFileWriter());
    });

    test('单章导出：书名/卷名/章名三级目录 + 末尾补换行', () async {
      final File out = await exports.exportChapter(
        bookTitle: '测试书',
        volumeTitle: '第一卷',
        chapterTitle: '第一章',
        text: '　　正文',
        customDir: '${temp.path}/out',
      );
      expect(out.path, endsWith('${Platform.pathSeparator}第一章.txt'));
      expect(
        out.path,
        contains('${Platform.pathSeparator}测试书${Platform.pathSeparator}第一卷'),
      );
      expect(await out.readAsString(), '　　正文\n');
    });

    test('重名导出自动加 (2)', () async {
      for (int i = 0; i < 2; i++) {
        await exports.exportChapter(
          bookTitle: '测试书',
          volumeTitle: '第一卷',
          chapterTitle: '第一章',
          text: '正文$i',
          customDir: '${temp.path}/out',
        );
      }
      final File second = File('${temp.path}/out/测试书/第一卷/第一章 (2).txt');
      expect(await second.exists(), isTrue);
      expect(await second.readAsString(), '正文1\n');
    });

    test('整卷与整书合并出分隔行', () {
      final String volume = exports.composeVolume(
        '第一卷',
        <({String title, String text})>[
          (title: '第一章', text: '甲'),
          (title: '第二章', text: '乙'),
        ],
      );
      expect(volume, contains('──── 卷：第一卷 ────'));
      expect(volume, contains('──── 章：第一章 ────\n\n甲\n'));
      expect(volume.endsWith('\n'), isTrue);

      final String book = exports.composeBook(<
        ({String volumeTitle, List<({String title, String text})> chapters})
      >[
        (
          volumeTitle: '第一卷',
          chapters: <({String title, String text})>[(title: '第一章', text: '甲')],
        ),
        (
          volumeTitle: '第二卷',
          chapters: <({String title, String text})>[(title: '第一章', text: '乙')],
        ),
      ]);
      expect(book.indexOf('──── 卷：第一卷 ────'), greaterThan(-1));
      expect(
        book.indexOf('──── 卷：第一卷 ────'),
        lessThan(book.indexOf('──── 卷：第二卷 ────')),
      );
    });
  });
}
