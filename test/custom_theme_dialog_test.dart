import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/ui/settings/custom_theme_dialog.dart';

void main() {
  testWidgets('独立主题对话框保留 HEX、预览与返回草稿，不直接改写设置', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CustomThemeDraft? result;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            return Button(
              onPressed: () async {
                result = await showDialog<CustomThemeDraft>(
                  context: context,
                  builder: (_) => const CustomThemeDialog(),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('正文预览 Aa'), findsOneWidget);
    await tester.enterText(find.byType(TextBox).at(0), '纸色');
    await tester.enterText(find.byType(TextBox).at(1), '#abc');
    await tester.pump();
    await tester.enterText(find.byType(TextBox).at(2), '123456');
    await tester.pump();
    // 无效输入只提示，不覆盖上一份合法颜色，也不丢失其他草稿字段。
    await tester.enterText(find.byType(TextBox).at(2), 'invalid');
    await tester.pump();
    expect(find.textContaining('HEX 无效'), findsOneWidget);
    await tester.tap(find.text('创建并应用'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.background, 0xFFAABBCC);
    expect(result!.accent, 0xFF123456);
    expect(result!.name, '纸色');
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立重命名对话框禁用空白名称，确认时修剪名称', (tester) async {
    String? result;
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            return Button(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const RenameThemeDialog(initial: '旧主题'),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), '   ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextBox), '  新主题  ');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, '新主题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('重命名输入区域在大窗口中保持单行紧凑高度', (tester) async {
    tester.view.physicalSize = const Size(1568, 1007);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            return Button(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => const RenameThemeDialog(initial: '旧主题'),
              ),
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(TextBox)).height, lessThanOrEqualTo(48));
  });
}
