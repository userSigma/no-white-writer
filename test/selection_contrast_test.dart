import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_white_writer/core/text/indenting_controller.dart';

void main() {
  for (final color in [Colors.black, Colors.white]) {
    testWidgets('编辑 controller 恢复 0.2 默认选字 span 且保留组词下划线：$color', (
      tester,
    ) async {
      final c = IndentingTextEditingController(
        autoIndent: () => false,
        blankLineBetween: () => false,
      );
      addTearDown(c.dispose);
      c.value = const TextEditingValue(
        text: '甲乙丙丁',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
        composing: TextRange(start: 1, end: 2),
      );
      late TextSpan span, original;
      final ordinary = TextEditingController.fromValue(c.value);
      addTearDown(ordinary.dispose);
      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) {
              span = c.buildTextSpan(
                context: context,
                style: TextStyle(color: color),
                withComposing: true,
              );
              original = ordinary.buildTextSpan(
                context: context,
                style: TextStyle(color: color),
                withComposing: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final leaves = <TextSpan>[];
      void visit(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) leaves.add(s);
          s.children?.forEach(visit);
        }
      }

      visit(span);
      expect(span.toPlainText(), '甲乙丙丁');
      final selected = leaves.where((s) => s.text == '乙').toList();
      expect(selected, hasLength(1));
      expect(
        span,
        original,
        reason: '不再按选区强制绘制黑白反色，沿用 0.2 TextEditingController',
      );
      expect(selected.single.style!.decoration, TextDecoration.underline);
      expect(c.value.composing, const TextRange(start: 1, end: 2));
      expect(c.selection, const TextSelection(baseOffset: 1, extentOffset: 3));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
