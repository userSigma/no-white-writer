import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/ui/settings/custom_theme_section.dart';

import 'support/widget_harness.dart';

void main() {
  testWidgets('主题分区协调模态状态并创建后应用自定义主题', (tester) async {
    final h = await widgetHarness(tester);
    final modalChanges = <bool>[];
    String? notice;
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: CustomThemeSection(
            settings: h.app.settings,
            blocked: false,
            onModalChanged: modalChanges.add,
            notice: (text, {error = false}) => notice = text,
          ),
        ),
      ),
    );

    await tester.tap(find.text('新建自定义主题…'));
    await tester.pumpAndSettle();
    expect(modalChanges, [true]);
    expect(find.text('正文预览 Aa'), findsOneWidget);

    await tester.enterText(find.byType(TextBox).at(0), '纸色');
    await tester.enterText(find.byType(TextBox).at(1), '#abc');
    await tester.pump();
    await tester.enterText(find.byType(TextBox).at(2), '123456');
    await tester.pump();
    await tester.tap(find.text('创建并应用'));
    await tester.pumpAndSettle();

    expect(modalChanges, [true, false]);
    expect(h.app.settings.settings.customThemes, hasLength(1));
    final theme = h.app.settings.settings.customThemes.single;
    expect(theme.name, '纸色');
    expect(theme.background, 0xFFAABBCC);
    expect(theme.accent, 0xFF123456);
    expect(h.app.settings.themeMode, 'custom:${theme.id}');
    expect(notice, contains('纸色'));
    expect(tester.takeException(), isNull);
    await finishWidget(tester, h);
  });
}
