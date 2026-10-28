import 'dart:io';

import '../logging/app_logger.dart';

/// 单实例锁（PLAN.md §5.6）。OS 级文件锁，进程退出自动释放，崩溃不会留死锁。
class InstanceLock {
  InstanceLock(this.filePath);

  /// 持有锁的实例必须一直可达：句柄一旦被 GC 回收，OS 会释放锁，单实例就失效了。
  static InstanceLock? _active;

  final String filePath;
  RandomAccessFile? _handle;

  bool get held => _handle != null;

  Future<bool> tryAcquire() async {
    try {
      final File file = File(filePath);
      await file.parent.create(recursive: true);
      final RandomAccessFile raf = await file.open(mode: FileMode.append);
      try {
        // 非阻塞：第二个实例必须立刻失败并给出提示，不能卡在 lock 上。
        await raf.lock(FileLock.exclusive);
      } on FileSystemException {
        await raf.close();
        return false;
      }
      await raf.truncate(0);
      await raf.writeString('$pid ${DateTime.now().toIso8601String()}\n');
      await raf.flush();
      _handle = raf;
      _active = this;
      AppLogger.instance.info('app.instance.acquired', <String, Object?>{
        'pid': pid,
      });
      return true;
    } on FileSystemException catch (error) {
      AppLogger.instance.warn('app.instance.lock.failed', <String, Object?>{
        'error': '$error',
        'pid': pid,
      });
      return false;
    }
  }

  Future<void> release() async {
    final RandomAccessFile? handle = _handle;
    _handle = null;
    if (identical(_active, this)) _active = null;
    if (handle == null) return;
    try {
      await handle.unlock();
    } catch (_) {}
    try {
      await handle.close();
    } catch (_) {}
  }
}
