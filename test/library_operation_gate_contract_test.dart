import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/state/library_operation_gate.dart';

// An event-queue boundary drains already scheduled microtasks without a timer
// duration or depending on how fast a machine executes an action.
Future<void> _drainMicrotasks() => Future<void>(() {});

void main() {
  test('idle queue starts in the new caller scheduling zone', () async {
    late LibraryOperationGate gate;
    final oldMicrotasks = <void Function()>[];
    runZoned(
      () {
        gate = LibraryOperationGate();
        return gate.write<void>(() async {});
      },
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, task) {
          oldMicrotasks.add(() => zone.run(task));
        },
      ),
    );
    while (oldMicrotasks.isNotEmpty) {
      oldMicrotasks.removeAt(0)();
    }
    expect(gate.pendingWrites, 0);
    var entered = false;
    final next = gate.write<void>(() async => entered = true);
    await _drainMicrotasks();
    expect(entered, isTrue, reason: 'idle queue must not need the old zone');
    expect(oldMicrotasks, isEmpty);
    await next;
  });

  test('accepted writes count immediately and execute FIFO', () async {
    final gate = LibraryOperationGate();
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <int>[];
    final first = gate.write(() async {
      order.add(1);
      entered.complete();
      await release.future;
      order.add(2);
      return 'first';
    });
    final second = gate.write(() async {
      order.add(3);
      return 'second';
    });
    expect(gate.pendingWrites, 2);
    await entered.future;
    expect(order, [1]);
    release.complete();
    expect(await Future.wait([first, second]), ['first', 'second']);
    await gate.waitForWrites();
    expect(order, [1, 2, 3]);
    expect(gate.pendingWrites, 0);
  });

  test('export reservation rejects later writes before waiting', () async {
    final gate = LibraryOperationGate();
    final release = Completer<void>();
    final order = <String>[];
    final first = gate.write(() async {
      await release.future;
      order.add('first');
    });
    final second = gate.write(() async => order.add('second'));
    gate.reserveExport();
    var drained = false;
    final waiting = gate.waitForWrites().then((_) => drained = true);
    await expectLater(
      gate.write(() async => order.add('rejected')),
      throwsA(isA<StateError>()),
    );
    expect(gate.pendingWrites, 2);
    expect(drained, isFalse);
    expect(gate.reserveExport, throwsA(isA<StateError>()));
    expect(gate.isExportReserved, isTrue);
    release.complete();
    await Future.wait([first, second, waiting]);
    expect(order, ['first', 'second']);
    gate.releaseExport();
    await gate.write(() async => order.add('after export'));
    expect(order.last, 'after export');
  });

  test(
    'sync and async failures retain identity without poisoning queue',
    () async {
      final gate = LibraryOperationGate();
      final syncError = StateError('synchronous failure');
      final asyncError = StateError('asynchronous failure');
      final syncStack = StackTrace.fromString('sync action stack');
      final asyncStack = StackTrace.fromString('async action stack');
      final sync = gate.write<void>(
        () => Error.throwWithStackTrace(syncError, syncStack),
      );
      final syncCheck = expectLater(sync, throwsA(same(syncError)));
      final async = gate.write<void>(
        () => Future<void>.error(asyncError, asyncStack),
      );
      final asyncCheck = expectLater(async, throwsA(same(asyncError)));
      final last = gate.write(() async => 42);
      await Future.wait([syncCheck, asyncCheck]);
      expect(await last, 42);
      gate.reserveExport();
      await gate.waitForWrites();
      expect(gate.pendingWrites, 0);
      gate.releaseExport();
    },
  );

  test('active nested writes remain inside the accepted transaction', () async {
    final gate = LibraryOperationGate();
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    final first = gate.write(() async {
      entered.complete();
      await release.future;
      expect(gate.pendingWrites, 2);
      await gate.write(() async => order.add('nested'));
      order.add('outer');
    });
    await entered.future;
    final second = gate.write(() async => order.add('queued'));
    gate.reserveExport();
    release.complete();
    await Future.wait([first, second, gate.waitForWrites()]);
    expect(order, ['nested', 'outer', 'queued']);
    expect(gate.pendingWrites, 0);
    gate.releaseExport();
  });

  test(
    'nested synchronous action errors are returned through the future',
    () async {
      final gate = LibraryOperationGate();
      final error = StateError('nested failure');
      await gate.write(() async {
        Future<void>? nested;
        expect(() {
          nested = gate.write<void>(() => throw error);
        }, returnsNormally);
        await expectLater(nested!, throwsA(same(error)));
      });
      expect(await gate.write(() async => 7), 7);
    },
  );

  test(
    'same-gate export reservation is rejected without leaving a reservation',
    () async {
      final gate = LibraryOperationGate();
      await gate.write(() async {
        expect(gate.reserveExport, throwsA(isA<StateError>()));
        expect(gate.isExportReserved, isFalse);
      });
      gate.reserveExport();
      await gate.waitForWrites();
      gate.releaseExport();
    },
  );

  test('same-gate wait fails instead of waiting for its own write', () async {
    final gate = LibraryOperationGate();
    await gate.write(() async {
      Object? outcome;
      final waiting = gate.waitForWrites().then<Object?>(
        (_) => 'completed',
        onError: (Object error) => error,
      );
      unawaited(waiting.then((value) => outcome = value));
      await _drainMicrotasks();
      expect(outcome, isA<StateError>());
      expect(await waiting, isA<StateError>());
    });
    await gate.waitForWrites();
  });

  test('gate context survives nesting through a different gate', () async {
    final first = LibraryOperationGate();
    final second = LibraryOperationGate();
    await first.write(() async {
      await second.write(() async {
        var entered = false;
        final nested = first.write(() async => entered = true);
        await _drainMicrotasks();
        expect(entered, isTrue);
        await nested;
      });
    });
    expect(first.pendingWrites, 0);
    expect(second.pendingWrites, 0);
  });

  test('another gate may reserve export while this gate is writing', () async {
    final first = LibraryOperationGate();
    final second = LibraryOperationGate();
    await first.write(() async {
      second.reserveExport();
      await second.waitForWrites();
      second.releaseExport();
    });
  });

  test('a completed write zone cannot bypass a later reservation', () async {
    final gate = LibraryOperationGate();
    final releaseDetached = Completer<void>();
    late Future<Object?> detached;
    await gate.write(() async {
      detached = releaseDetached.future
          .then((_) {
            return gate.write(() async => 'must not run');
          })
          .then<Object?>((value) => value, onError: (Object error) => error);
    });
    gate.reserveExport();
    releaseDetached.complete();
    expect(await detached, isA<StateError>());
    gate.releaseExport();
  });

  test(
    'close drains the active write and rejects queued and later writes',
    () async {
      final gate = LibraryOperationGate();
      final entered = Completer<void>();
      final release = Completer<void>();
      var queuedRan = false;
      final active = gate.write(() async {
        entered.complete();
        await release.future;
        return 'committed';
      });
      await entered.future;
      final queued = gate.write(() async => queuedRan = true);
      final queuedCheck = expectLater(queued, throwsA(isA<StateError>()));
      final idle = gate.waitForWrites();
      gate.close();
      gate.close();
      await expectLater(gate.write(() async {}), throwsA(isA<StateError>()));
      expect(gate.reserveExport, throwsA(isA<StateError>()));
      release.complete();
      expect(await active, 'committed');
      await queuedCheck;
      await idle;
      expect(queuedRan, isFalse);
      expect(gate.pendingWrites, 0);
    },
  );

  test(
    'close also rejects nested writes in an already active action',
    () async {
      final gate = LibraryOperationGate();
      await gate.write(() async {
        gate.close();
        await expectLater(gate.write(() async {}), throwsA(isA<StateError>()));
      });
      expect(gate.pendingWrites, 0);
    },
  );
}
