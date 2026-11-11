import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/platform/platform_services_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('窗口命令走原生关闭而非销毁，外部窗口状态同步', () async {
    const channel = MethodChannel('window_manager');
    final calls = <String>[];
    var maximized = false;
    var fullScreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isFullScreen':
              return fullScreen;
            case 'maximize':
              maximized = true;
            case 'unmaximize':
              maximized = false;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final platform = IoPlatformServices();
    await platform.minimizeWindow();
    await platform.startWindowDrag();
    await platform.toggleWindowMaximized();
    expect(platform.windowState.value.maximized, isTrue);
    await platform.toggleWindowMaximized();
    expect(platform.windowState.value.maximized, isFalse);
    maximized = true;
    platform.onWindowMaximize();
    await Future<void>.delayed(Duration.zero);
    expect(platform.windowState.value.maximized, isTrue);
    fullScreen = true;
    platform.onWindowEnterFullScreen();
    await Future<void>.delayed(Duration.zero);
    expect(platform.windowState.value.fullScreen, isTrue);
    final maximizeCount = calls
        .where((c) => c == 'maximize' || c == 'unmaximize')
        .length;
    await platform.toggleWindowMaximized();
    expect(
      calls.where((c) => c == 'maximize' || c == 'unmaximize').length,
      maximizeCount,
    );
    await platform.requestWindowClose();
    expect(calls, containsAll(['minimize', 'startDragging', 'close']));
    expect(calls, isNot(contains('destroy')));
  });

  test('桌面显示前隐藏原生标题栏且不移除原生缩放框架', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isMaximized' ||
              call.method == 'isFullScreen' ||
              call.method == 'isMinimized') {
            return false;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await IoPlatformServices().initialize();
    final hidden = calls
        .where((call) => call.method == 'setTitleBarStyle')
        .toList();
    expect(hidden, hasLength(1));
    expect(hidden.single.arguments, {
      'titleBarStyle': 'hidden',
      'windowButtonVisibility': false,
    });
    expect(
      calls.indexOf(hidden.single),
      lessThan(calls.indexWhere((call) => call.method == 'show')),
    );
    expect(calls.where((call) => call.method == 'setAsFrameless'), isEmpty);
  });
}
