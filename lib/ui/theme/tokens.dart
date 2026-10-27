import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme.dart';
import 'live_theme_scope.dart';

export 'app_theme.dart' show AppThemeData, buildFluentTheme;

/// 沿用 0.2 设计 token；内置主题从这里取值，视觉与重构前一致。
class AppColors {
  const AppColors._();

  static const Color paper = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF000000);
  static const Color textOnPaper = Color(0xFF2B2A27);
  static const Color textOnInk = Color(0xFFEDE8DF);
  static const Color cinnabar = Color(0xFFA6402B);
  static const Color cinnabarSoft = Color(0xFFC9795F);
  static const Color hairlineOnPaper = Color(0xFFE3DACB);
  static const Color hairlineOnInk = Color(0xFF2B2D31);
  static const Color mutedOnPaper = Color(0xFF7A7267);
  static const Color mutedOnInk = Color(0xFF9A948A);
}

/// 当前生效的主题：优先实时 scope（对 overlay 路由也可见、不被冻结），
/// 未注入时按 FluentTheme 明暗回退到内置主题（静态提示页等场景）。
AppThemeData appThemeOf(BuildContext context) =>
    LiveFluentThemeScope.appThemeOf(context);

/// 内容底色（原 paper/ink 二选一，现为主题背景色）。
Color paperOrInk(BuildContext context) => appThemeOf(context).background;

/// 正文色。
Color bodyTextColor(BuildContext context) => appThemeOf(context).bodyText;

/// 发丝线色。
Color hairlineColor(BuildContext context) => appThemeOf(context).hairline;

/// 弱化文字色。
Color mutedTextColor(BuildContext context) => appThemeOf(context).mutedText;

/// 强调色（选中高亮、按钮强调、光标等，原 cinnabar 的用法）。
Color accentColor(BuildContext context) => appThemeOf(context).accent;

/// 强调色的柔化变体（原 cinnabarSoft 的用法）。
Color accentSoftColor(BuildContext context) => appThemeOf(context).accentSoft;

/// 书脊渐变：色相由封面种子决定，保证同一本书颜色稳定。
LinearGradient spineGradient(int seed) {
  final double hue = (seed.abs() % 360).toDouble();
  final Color a = HSLColor.fromAHSL(1, hue, 0.34, 0.42).toColor();
  final Color b = HSLColor.fromAHSL(1, (hue + 26) % 360, 0.30, 0.28).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[a, b],
  );
}
