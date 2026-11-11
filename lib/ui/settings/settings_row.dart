import 'package:fluent_ui/fluent_ui.dart';

import '../theme/tokens.dart';

/// 分区共用的响应式标签列：宽屏顶端对齐，小窗口纵向排列。
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          label,
          style: TextStyle(fontSize: 13, color: bodyTextColor(context)),
        );
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[title, const SizedBox(height: 8), child],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 96, child: title),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        );
      },
    ),
  );
}
