import 'package:fluent_ui/fluent_ui.dart';

import '../../core/models.dart';
import 'tokens.dart';

/// 可参数化主题模型：全应用取色的唯一来源。
///
/// 内置两套（[light] / [dark]，与 0.2 设计 token 视觉一致），
/// 其余来自用户在 settings.json 里持久化的 [CustomTheme]。
///
/// 派生色（正文/发丝线/弱化文字）按背景亮度选明/暗基色板推导，
/// 保证自定义背景下的可读性；强调色沿用 cinnabar 现在的用法
/// （选中高亮、按钮强调、光标等）。
class AppThemeData {
  const AppThemeData({
    required this.id,
    required this.name,
    required this.background,
    required this.accent,
    this.builtin = false,
  });

  /// 稳定 id：内置为 `light` / `dark`，自定义为 `custom:<CustomTheme.id>`。
  final String id;
  final String name;
  final Color background;
  final Color accent;
  final bool builtin;

  /// 内置浅色：纯白背景 + 朱砂强调（原 AppColors 常量原样）。
  static const AppThemeData light = AppThemeData(
    id: 'light',
    name: '浅色',
    background: AppColors.paper,
    accent: AppColors.cinnabar,
    builtin: true,
  );

  /// 内置深色：纯黑背景 + 朱砂强调。
  static const AppThemeData dark = AppThemeData(
    id: 'dark',
    name: '深色',
    background: AppColors.ink,
    accent: AppColors.cinnabar,
    builtin: true,
  );

  /// 按明暗取内置主题（无 scope 时的回退路径）。
  static AppThemeData builtinFor(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  /// 从持久化模型构造自定义主题。
  factory AppThemeData.fromCustom(CustomTheme theme) => AppThemeData(
    id: 'custom:${theme.id}',
    name: theme.name,
    background: Color(theme.background),
    accent: Color(theme.accent),
  );

  @override
  bool operator ==(Object other) =>
      other is AppThemeData &&
      other.id == id &&
      other.name == name &&
      other.background == background &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(id, name, background, accent);

  /// 背景亮度（相对亮度 >= 0.5 视为浅色基）。
  Brightness get brightness =>
      background.computeLuminance() >= 0.5 ? Brightness.light : Brightness.dark;

  Color _pick(Color onLight, Color onDark) =>
      brightness == Brightness.light ? onLight : onDark;

  /// 正文色：浅基底沿用暖黑，深基底沿用米白。
  Color get bodyText => _pick(AppColors.textOnPaper, AppColors.textOnInk);

  /// 发丝线：浅基底米棕，深基底炭灰。
  Color get hairline => _pick(
    AppColors.hairlineOnPaper,
    AppColors.hairlineOnInk,
  );

  /// 弱化文字。
  Color get mutedText => _pick(AppColors.mutedOnPaper, AppColors.mutedOnInk);

  /// 强调色的柔化变体（保存中状态点等）。
  ///
  /// 内置主题精确沿用 cinnabarSoft；自定义主题把强调色向背景轻混，
  /// 得到与该主题协调的柔和档。
  Color get accentSoft =>
      builtin && accent == AppColors.cinnabar
          ? AppColors.cinnabarSoft
          : Color.lerp(accent, background, 0.25)!;
}

/// 由主题模型构建 FluentThemeData：明暗、强调色板、脚手架底色。
///
/// 菜单表面三字段（menuColor / acrylicBackgroundColor /
/// acrylicFallbackColor）全部取主题背景：FlyoutContent 在 `color: null`
/// 时把 `menuColor` 以 0.65 透明度叠在 acrylic 基底上，两层同色时合成
/// 实心背景；更重要的是 fluent_ui 的 `MenuFlyoutSubItem.show()` 会把父级
/// MenuFlyout 的显式 `color` 值捕获进闭包且之后不再刷新——只有让显式色
/// 保持 null、由 FluentTheme 实时查表，子菜单表面才能随主题即时换色
/// （配合 settings_menu.dart 的 DisableAcrylic 关掉亚克力混合）。
FluentThemeData buildFluentTheme(AppThemeData theme) {
  return FluentThemeData(
    brightness: theme.brightness,
    accentColor: _accentSwatch(theme.accent, builtin: theme.builtin),
    scaffoldBackgroundColor: theme.background,
    menuColor: theme.background,
    acrylicBackgroundColor: theme.background,
    acrylicFallbackColor: theme.background,
  );
}

/// 朱砂的精确官方色板（保持内置主题与现状逐值一致）。
AccentColor _cinnabarSwatch() => AccentColor.swatch(const <String, Color>{
  'normal': AppColors.cinnabar,
  'light1': AppColors.cinnabarSoft,
  'light2': Color(0xFFD9A28D),
  'dark1': Color(0xFF8E3524),
  'dark2': Color(0xFF6E291C),
});

/// 强调色板：内置朱砂用精确常量；自定义色按 HSL 明度推导五档。
AccentColor _accentSwatch(Color accent, {required bool builtin}) {
  if (builtin && accent == AppColors.cinnabar) return _cinnabarSwatch();
  final HSLColor hsl = HSLColor.fromColor(accent);
  Color shift(double delta) => hsl
      .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
      .toColor();
  return AccentColor.swatch(<String, Color>{
    'normal': accent,
    'light1': shift(0.12),
    'light2': shift(0.24),
    'dark1': shift(-0.10),
    'dark2': shift(-0.20),
  });
}
