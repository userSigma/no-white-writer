import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/core/storage/app_paths.dart';
import 'package:no_white_writer/core/storage/atomic_file_writer.dart';
import 'package:no_white_writer/core/storage/book_store.dart';
import 'package:no_white_writer/core/storage/chapter_store.dart';
import 'package:no_white_writer/core/storage/chapter_move_store.dart';

void main() {
  late Directory root;
  late AppPaths paths;
  late BookStore books;
  late BookIndex book;
  late ChapterMeta chapter;
  const txt = [239, 187, 191, 65, 13, 10, 228, 184, 173, 0];
  const bak = [66, 13, 10, 195, 169];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nww-move-');
    paths = AppPaths(dataRoot: root, documentsRoot: root);
    await paths.ensureLayout();
    books = BookStore(paths, const AtomicFileWriter(), ChapterStore(paths));
    chapter = ChapterMeta(id: 'c', title: '原始章名', order: 0);
    book = BookIndex(
      id: 'b',
      title: '原书',
      volumes: [
        Volume(id: 'source', title: '源', order: 0, chapters: [chapter]),
        Volume(id: 'target', title: '目标', order: 1),
      ],
    );
    await books.save(book);
    final source = paths.chapterFile('b', 'source', 'c');
    await source.parent.create(recursive: true);
    await source.writeAsBytes(txt, flush: true);
    await File('${source.path}.bak').writeAsBytes(bak, flush: true);
    await File('${source.path}.bak').setLastModified(DateTime(2000));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> commit() async {
    book.volumes[0].chapters.remove(chapter);
    book.volumes[1].chapters.add(chapter);
    await books.save(book);
  }

  test('跨卷保留原始txt和bak字节及章ID，仅提交后删除源', () async {
    final store = ChapterMoveStore(paths, const AtomicFileWriter());
    await store.move(
      bookId: 'b',
      sourceId: 'source',
      targetId: 'target',
      chapterId: 'c',
      commitIndex: commit,
    );
    expect(await paths.chapterFile('b', 'target', 'c').readAsBytes(), txt);
    expect(
      await File('${paths.chapterFile('b', 'target', 'c').path}.bak')
          .readAsBytes(),
      bak,
    );
    expect(await paths.chapterFile('b', 'source', 'c').exists(), isFalse);
    expect(book.volumeOfChapter('c')?.id, 'target');
    expect(await store.recordFile('b').exists(), isFalse);
    expect(
      await ChapterStore(paths).recover(book),
      isEmpty,
      reason: '完整启动顺序不能把刚复制的旧bak当更新正文',
    );
    expect(await paths.chapterFile('b', 'target', 'c').readAsBytes(), txt);
  });

  for (final phase in [
    'beforeRecord',
    'record',
    'txt',
    'bak',
    'verified',
    'index',
    'summary',
    'cleanup',
  ]) {
    test('$phase 中断重启按实际索引恢复，源或目标至少一份完整', () async {
      bool reached = false;
      final store = ChapterMoveStore(
        paths,
        const AtomicFileWriter(),
        onPhase: (name) async {
          if (name == phase) {
            reached = true;
            throw StateError('inject:$phase');
          }
        },
      );
      await expectLater(
        store.move(
          bookId: 'b',
          sourceId: 'source',
          targetId: 'target',
          chapterId: 'c',
          commitIndex: commit,
          commitSummary: () async {},
        ),
        throwsStateError,
      );
      expect(reached, isTrue, reason: '必须实际到达 $phase 故障点');
      final fresh = ChapterMoveStore(paths, const AtomicFileWriter());
      await fresh.recover('b');
      final raw = jsonDecode(
        await paths.bookFile('b').readAsString(),
      ) as Map<String, dynamic>;
      final persisted = BookIndex.fromJson(raw);
      expect(
        await ChapterStore(paths).recover(persisted),
        isEmpty,
        reason: '迁移恢复之后继续执行普通章节恢复也不能把旧bak覆盖正文',
      );
      final owner = persisted.volumeOfChapter('c')!;
      expect(
        owner.id,
        ['index', 'summary', 'cleanup'].contains(phase) ? 'target' : 'source',
      );
      expect(persisted.allChapters.where((c) => c.id == 'c').length, 1);
      expect(await paths.chapterFile('b', owner.id, 'c').readAsBytes(), txt);
      expect(
        await File('${paths.chapterFile('b', owner.id, 'c').path}.bak')
            .readAsBytes(),
        bak,
      );
      final other = owner.id == 'source' ? 'target' : 'source';
      expect(await paths.chapterFile('b', other, 'c').exists(), isFalse);
      expect(await fresh.recordFile('b').exists(), isFalse);
      await fresh.recover('b'); // 幂等，不按时间戳二次猜测。
    });
  }

  for (final phase in ['record', 'index']) {
    test('$phase 后残留的半成品tmp可按持久化归属恢复', () async {
      final store = ChapterMoveStore(
        paths,
        const AtomicFileWriter(),
        onPhase: (name) async {
          if (name == phase) throw StateError('inject:$phase');
        },
      );
      await expectLater(
        store.move(
          bookId: 'b',
          sourceId: 'source',
          targetId: 'target',
          chapterId: 'c',
          commitIndex: commit,
        ),
        throwsStateError,
      );
      final target = paths.chapterFile('b', 'target', 'c');
      final partial = File('${target.path}.tmp');
      await partial.parent.create(recursive: true);
      await partial.writeAsString('partial');

      final fresh = ChapterMoveStore(paths, const AtomicFileWriter());
      await fresh.recover('b');

      final raw = jsonDecode(await paths.bookFile('b').readAsString());
      final persisted = BookIndex.fromJson(raw as Map<String, dynamic>);
      final expectedOwner = phase == 'index' ? 'target' : 'source';
      final owner = persisted.volumeOfChapter('c')!;
      expect(owner.id, expectedOwner);
      expect(await paths.chapterFile('b', owner.id, 'c').readAsBytes(), txt);
      expect(await partial.exists(), isFalse);
      expect(await fresh.recordFile('b').exists(), isFalse);
      await fresh.recover('b');
    });
  }

  test('不覆盖预存目标，缺源或未解决tmp时停止且不提交', () async {
    final store = ChapterMoveStore(paths, const AtomicFileWriter());
    final target = paths.chapterFile('b', 'target', 'c');
    await target.parent.create(recursive: true);
    await target.writeAsString('无关稿件');
    await expectLater(
      store.move(
        bookId: 'b',
        sourceId: 'source',
        targetId: 'target',
        chapterId: 'c',
        commitIndex: commit,
      ),
      throwsStateError,
    );
    expect(await target.readAsString(), '无关稿件');
    await target.delete();
    final source = paths.chapterFile('b', 'source', 'c');
    await File('${source.path}.tmp').writeAsString('未恢复草稿');
    await expectLater(
      store.move(
        bookId: 'b',
        sourceId: 'source',
        targetId: 'target',
        chapterId: 'c',
        commitIndex: commit,
      ),
      throwsStateError,
    );
    await File('${source.path}.tmp').delete();
    await source.delete();
    await expectLater(
      store.move(
        bookId: 'b',
        sourceId: 'source',
        targetId: 'target',
        chapterId: 'c',
        commitIndex: commit,
      ),
      throwsStateError,
    );
    expect(book.volumeOfChapter('c')?.id, 'source');
  });

  test('源备份tmp也必须在记录与索引提交之前拒绝', () async {
    final pending = File(
      '${paths.chapterFile('b', 'source', 'c').path}.bak.tmp',
    );
    await pending.writeAsString('仍在恢复的备份');
    bool committed = false;
    final store = ChapterMoveStore(paths, const AtomicFileWriter());
    await expectLater(
      store.move(
        bookId: 'b',
        sourceId: 'source',
        targetId: 'target',
        chapterId: 'c',
        commitIndex: () async {
          committed = true;
          await commit();
        },
      ),
      throwsStateError,
    );
    expect(committed, isFalse);
    expect(await store.recordFile('b').exists(), isFalse);
    expect(await pending.readAsString(), '仍在恢复的备份');
    expect(await paths.chapterFile('b', 'source', 'c').readAsBytes(), txt);
  });

  test('损坏迁移记录阻止load和rebuild且不改变正文与索引', () async {
    final record = ChapterMoveStore(
      paths,
      const AtomicFileWriter(),
    ).recordFile('b');
    await record.writeAsString('{broken-journal');
    final indexBytes = await paths.bookFile('b').readAsBytes();
    final summary = BookSummary(
      id: 'b',
      title: '原书',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      coverSeed: 0,
    );
    await expectLater(books.load(summary), throwsStateError);
    await expectLater(books.rebuild(summary), throwsStateError);
    expect(await record.readAsString(), '{broken-journal');
    expect(await paths.bookFile('b').readAsBytes(), indexBytes);
    expect(await paths.chapterFile('b', 'source', 'c').readAsBytes(), txt);
    expect(
      await File('${paths.chapterFile('b', 'source', 'c').path}.bak')
          .readAsBytes(),
      bak,
    );
    expect(await paths.chapterFile('b', 'target', 'c').exists(), isFalse);
  });

  test('未知归属或不匹配的目标保留记录与源，禁止重建覆盖', () async {
    final store = ChapterMoveStore(
      paths,
      const AtomicFileWriter(),
      onPhase: (name) async {
        if (name == 'verified') throw StateError('crash');
      },
    );
    await expectLater(
      store.move(
        bookId: 'b',
        sourceId: 'source',
        targetId: 'target',
        chapterId: 'c',
        commitIndex: commit,
      ),
      throwsStateError,
    );
    await paths.chapterFile('b', 'target', 'c').writeAsString('外部修改');
    await expectLater(
      ChapterMoveStore(paths, const AtomicFileWriter()).recover('b'),
      throwsStateError,
    );
    expect(await paths.chapterFile('b', 'source', 'c').readAsBytes(), txt);
    expect(await store.recordFile('b').exists(), isTrue);
    await paths.bookFile('b').writeAsString('{bad');
    final summary = BookSummary(
      id: 'b',
      title: '原书',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      coverSeed: 0,
    );
    await expectLater(books.load(summary), throwsStateError);
    expect(await paths.bookFile('b').readAsString(), '{bad');
  });
}
