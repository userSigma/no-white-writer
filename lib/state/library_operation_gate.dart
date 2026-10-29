import 'dart:async';

/// 书库写屏障：普通书库写入、导出预约与关闭状态共用的唯一协调边界。
///
/// 约定：
/// - [write] 按调用顺序串行执行。每次写入的失败只交给该调用的 future，
///   队列尾永不进入失败态，因此任何一次异常都不会毒化后续写入或导出。
/// - [reserveExport] 在等待之前同步生效：预约后新到的 [write] 在入口就被拒绝；
///   已受理的写入继续完成，导出用 [waitForWrites] 等它们全部结束后再读快照，
///   所以快照不会看到写了一半的磁盘状态，也不会有写入越过导出读取。
/// - [close] 之后 [write] 与 [reserveExport] 都明确失败；排队中的写入在出队时
///   失败退出并递减在途计数，等待方不会被永久挂起。
/// - 在同一个写入内部再次调用 [write]（例如事务内的辅助步骤）直接内联执行，
///   既保持原子顺序也不会自锁；其他并发调用仍排在队尾，串行性不受影响。
class LibraryOperationGate {
  // Each gate owns a Zone key so A → B → A still sees A's active token.
  final Object _zoneKey = Object();

  Future<void> _tail = Future<void>.value();
  Completer<void>? _idle;
  Object? _activeToken;
  int _pending = 0;
  bool _reserved = false;
  bool _closed = false;

  bool get isExportReserved => _reserved;
  bool get isClosed => _closed;
  int get pendingWrites => _pending;

  static StateError _closedError() => StateError('书库已关闭，不能再修改作品。');

  static StateError _busyError() => StateError('正在导出，暂不能修改作品。');

  bool get _insideWrite =>
      _activeToken != null && identical(Zone.current[_zoneKey], _activeToken);

  /// 串行执行一次书库变更；返回值与异常都只属于本次调用。
  Future<T> write<T>(Future<T> Function() action) {
    if (_closed) return Future<T>.error(_closedError());
    if (_insideWrite) {
      // Reentrant work belongs to the accepted transaction, even after export
      // reserves its snapshot. Convert synchronous errors to the same Future API.
      return Future<T>.sync(action);
    }
    if (_reserved) return Future<T>.error(_busyError());
    // An idle tail must not retain the previous caller's microtask scheduler
    // (for example a paused widget-test Zone). There is no work left to await.
    if (_pending == 0) _tail = Future<void>.value();
    _pending++;
    final Completer<T> completer = Completer<T>();
    // 队列尾只承接完成信号：失败已在下面捕获并转交给 [completer]。
    _tail = _tail.then((_) async {
      final Object token = Object();
      try {
        if (_closed) throw _closedError();
        _activeToken = token;
        completer.complete(
          await runZoned(
            action,
            zoneValues: <Object?, Object?>{_zoneKey: token},
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _activeToken = null;
        _pending--;
        if (_pending == 0) {
          final Completer<void>? idle = _idle;
          _idle = null;
          idle?.complete();
        }
      }
    });
    return completer.future;
  }

  /// 先受理预约，再等待既有写入；等待发生在调用方 [waitForWrites] 中。
  ///
  /// 同步抛错，让调用方能在预约失败时不发出「已预约」通知。
  void reserveExport() {
    if (_insideWrite) throw StateError('不能在书库写入内部预约导出。');
    if (_closed) throw StateError('书库已关闭，不能再导出。');
    if (_reserved) throw StateError('正在导出，请稍候。');
    _reserved = true;
  }

  /// 等待预约受理前进入队列的写入全部结束。
  Future<void> waitForWrites() {
    if (_insideWrite) {
      return Future<void>.error(StateError('不能在书库写入内部等待自身结束。'));
    }
    if (_pending == 0) return Future<void>.value();
    final Completer<void> idle = _idle ??= Completer<void>();
    return idle.future;
  }

  void releaseExport() {
    _reserved = false;
  }

  /// 关闭后不再受理写入与导出预约；在途写入仍按真实落盘结果结束。
  void close() {
    _closed = true;
  }
}
