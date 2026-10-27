import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme.dart';

/// 应用级「实时主题」scope。
///
/// 这是一个普通 [InheritedWidget]（不是 [InheritedTheme]），因此
/// `InheritedTheme.capture` / `CapturedThemes.wrap` 无法把它冻结进路由：
/// 菜单、气泡等 overlay 路由内容始终从这里读到当前生效的主题，
/// 主题切换（含「跟随系统」的系统明暗变化与自定义主题激活）时立即重建。
///
/// 注入位置：`FluentApp.builder`（lib/app.dart）——builder 插入的 widget 是
/// Navigator 的祖先，对根/任意 overlay 路由可见。
class LiveFluentThemeScope extends InheritedWidget {
  const LiveFluentThemeScope({
    super.key,
    required this.themeData,
    required this.appTheme,
    required super.child,
  });

  /// 当前生效的应用级主题（与 FluentApp 实际选择的 theme/darkTheme 相同来源）。
  final FluentThemeData themeData;

  /// 当前生效的参数化主题模型（背景/强调/派生色的唯一来源）。
  final AppThemeData appTheme;

  /// 读取实时 FluentThemeData。未注入时退回 [FluentTheme.of]。
  static FluentThemeData of(BuildContext context) {
    final LiveFluentThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<LiveFluentThemeScope>();
    if (scope != null) return scope.themeData;
    return FluentTheme.of(context);
  }

  /// 读取实时主题模型。未注入时按 [FluentTheme] 明暗回退内置主题。
  static AppThemeData appThemeOf(BuildContext context) {
    final LiveFluentThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<LiveFluentThemeScope>();
    if (scope != null) return scope.appTheme;
    return AppThemeData.builtinFor(FluentTheme.of(context).brightness);
  }

  @override
  bool updateShouldNotify(LiveFluentThemeScope oldWidget) =>
      themeData != oldWidget.themeData || appTheme != oldWidget.appTheme;
}

/// 与 tokens.dart 的 paperOrInk 等价，但从 [LiveFluentThemeScope] 解析，
/// 供 flyout / 子菜单表面使用：即使路由内的 FluentTheme 被冻结也能实时换色。
Color paperOrInkLive(BuildContext context) =>
    LiveFluentThemeScope.appThemeOf(context).background;

/// 与 tokens.dart 的 bodyTextColor 等价，从 [LiveFluentThemeScope] 解析。
Color bodyTextColorLive(BuildContext context) =>
    LiveFluentThemeScope.appThemeOf(context).bodyText;
