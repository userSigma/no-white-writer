import 'dart:io';

/// 原子写（PLAN.md §4.6 / §15）：同一路径的所有写入共享一个串行队列。
///
/// 写 `<path>.tmp` → flush → rename。调用方收到原错误，队列不被失败毒化。
/// 静态尾链也协调不同 writer 实例，防止字符串/字节写入争用临时文件。
class AtomicFileWriter {
  const AtomicFileWriter();

  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  Future<void> writeAtomically(File target, String content) => _enqueue(
    target,
    () => _write(target, (RandomAccessFile f) => f.writeString(content)),
  );

  Future<void> writeBytesAtomically(File target, List<int> bytes) {
    final List<int> snapshot = List<int>.of(bytes);
    return _enqueue(
      target,
      () => _write(target, (RandomAccessFile f) => f.writeFrom(snapshot)),
    );
  }

  Future<void> _enqueue(File target, Future<void> Function() action) {
    final String absolute = target.absolute.path;
    final String key = Platform.isWindows ? absolute.toLowerCase() : absolute;
    final Future<void> result = (_tails[key] ?? Future<void>.value()).then(
      (_) => action(),
    );
    late final Future<void> tail;
    tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(_tails[key], tail)) _tails.remove(key);
        });
    _tails[key] = tail;
    return result;
  }

  Future<void> _write(
    File target,
    Future<RandomAccessFile> Function(RandomAccessFile) write,
  ) async {
    await target.parent.create(recursive: true);
    final File tmp = File('${target.path}.tmp');
    RandomAccessFile? raf;
    try {
      raf = await tmp.open(mode: FileMode.write);
      await write(raf);
      await raf.flush();
      await raf.close();
      raf = null;
      await tmp.rename(target.path);
    } finally {
      await raf?.close();
    }
  }
}
