import 'package:flutter/widgets.dart';

import 'i18n_controller.dart';

export 'builtin_packs.dart' show builtinPackSources;
export 'i18n_controller.dart' show I18nController;
export 'language_pack.dart' show LanguagePack;

/// 未包 [I18nScope] 的环境（单元测试、预览）使用的兜底控制器：仅内置包。
final I18nController fallbackI18n = I18nController();

/// 把 [I18nController] 注入 widget 树。
///
/// [languageCode] 参与相等性判断：语言切换时重建 scope，让所有
/// `t(context, …)` 的依赖方随主题外层 `ListenableBuilder` 一并刷新。
class I18nScope extends InheritedWidget {
  const I18nScope({
    super.key,
    required this.controller,
    required this.languageCode,
    required super.child,
  });

  final I18nController controller;
  final String languageCode;

  @override
  bool updateShouldNotify(I18nScope oldWidget) =>
      languageCode != oldWidget.languageCode ||
      !identical(controller, oldWidget.controller);
}

/// 翻译函数：`t(context, 'key', {参数})`。
///
/// 查找顺序：当前语言包 → `zh-CN` → key 本身；随后替换文案中的
/// `{占位符}`。context 不在 [I18nScope] 内时使用内置兜底控制器。
String t(BuildContext context, String key, [Map<String, String>? args]) {
  final I18nScope? scope = context.dependOnInheritedWidgetOfExactType<
      I18nScope>();
  return (scope?.controller ?? fallbackI18n).translate(key, args);
}

/// 语言包 code → Flutter Locale（`zh-CN` → `zh_CN` 形式拆分）。
///
/// 用于让 FluentApp 的 locale 与当前语言包一致，保证内置控件
/// （对话框按钮文案等）跟随切换。未知细分后缀时退回主语言。
Locale localeOfLanguageCode(String code) {
  final List<String> parts = code.split(RegExp(r'[-_]'));
  final String language = parts.isNotEmpty && parts[0].isNotEmpty
      ? parts[0]
      : I18nController.fallbackCode.split('-').first;
  final String? region = parts.length > 1 && parts[1].isNotEmpty
      ? parts[1]
      : null;
  return Locale.fromSubtags(languageCode: language, countryCode: region);
}
