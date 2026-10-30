import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/state/ui_operation_guards.dart';

void main() {
  test('草稿守卫按注册顺序运行，拒绝后不执行后续守卫', () async {
    final guards = UiOperationGuards();
    final calls = <int>[];
    guards.register(() async {
      calls.add(1);
      return true;
    });
    final refusing = guards.register(() async {
      calls.add(2);
      return false;
    });
    guards.register(() async {
      calls.add(3);
      return true;
    });
    expect(await guards.flush(), isFalse);
    expect(calls, [1, 2]);
    guards.remove(refusing);
    calls.clear();
    expect(await guards.flush(), isTrue);
    expect(calls, [1, 3]);
  });

  test('检查时被卸载的页面不会继续执行，新增守卫留待下一次', () async {
    final guards = UiOperationGuards();
    final calls = <String>[];
    late Object removed;
    guards.register(() async {
      calls.add('first');
      guards.remove(removed);
      guards.register(() async {
        calls.add('new');
        return true;
      });
      return true;
    });
    removed = guards.register(() async {
      calls.add('removed');
      return false;
    });
    expect(await guards.flush(), isTrue);
    expect(calls, ['first']);
    calls.clear();
    expect(await guards.flush(), isTrue);
    expect(calls, ['first', 'new']);
  });

  test('守卫异常取消跨页面操作，不泄漏异常', () async {
    final guards = UiOperationGuards();
    final token = guards.register(() async => throw StateError('draft fault'));
    expect(await guards.flush(), isFalse);
    guards.remove(token);
    expect(await guards.flush(), isTrue);
  });
}
