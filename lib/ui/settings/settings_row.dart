import 'package:fluent_ui/fluent_ui.dart';

import '../theme/tokens.dart';

/// 设置浮窗各分区共用的标签列，保留原来的间距和焦点顺序。
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: bodyTextColor(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    ),
  );
}
