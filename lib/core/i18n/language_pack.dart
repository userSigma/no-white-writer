import 'dart:convert';
import 'dart:io';

/// 一份语言包：语言代码、界面显示名与字符串表。
///
/// 代码约定形如 `zh-CN` / `en`；字符串表是扁平的 key → 文案映射，
/// 文案里可用 `{name}` 形式的占位符，由 `I18nController.translate` 填充。
class LanguagePack {
  const LanguagePack({
    required this.code,
    required this.name,
    required this.strings,
  });

  final String code;
  final String name;
  final Map<String, String> strings;

  /// 合法语言代码：字母开头，2-24 位字母/数字/`-`/`_`。
  static final RegExp _codePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,23}$');

  /// 解析语言包 JSON 文本。约定结构：
  ///
  /// ```json
  /// { "code": "ja", "name": "日本語", "strings": { "key": "文案" } }
  /// ```
  ///
  /// 返回 `(pack, null)` 或 `(null, 错误说明)`；任何解析失败都不抛异常，
  /// 由调用方决定如何上报与跳过。
  static (LanguagePack?, String?) tryParse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (error) {
      return (null, '不是合法的 JSON：$error');
    }
    if (decoded is! Map<String, dynamic>) {
      return (null, '顶层必须是 JSON 对象');
    }
    final Object? rawCode = decoded['code'];
    if (rawCode is! String || rawCode.trim().isEmpty) {
      return (null, '缺少非空字符串字段 "code"');
    }
    final String code = rawCode.trim();
    if (!_codePattern.hasMatch(code)) {
      return (
        null,
        '"code"（$code）只应为 2-24 位字母、数字、-、_，且以字母或数字开头',
      );
    }
    final Object? rawName = decoded['name'];
    if (rawName is! String || rawName.trim().isEmpty) {
      return (null, '缺少非空字符串字段 "name"（语言显示名）');
    }
    final Object? rawStrings = decoded['strings'];
    if (rawStrings is! Map) {
      return (null, '缺少对象字段 "strings"（字符串表）');
    }
    final Map<String, String> strings = <String, String>{};
    for (final MapEntry<dynamic, dynamic> entry in rawStrings.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        return (null, '"strings" 的键必须都是非空字符串');
      }
      if (entry.value is! String) {
        return (null, '"strings" 的值必须都是字符串（"${entry.key}" 不是）');
      }
      strings[entry.key as String] = entry.value as String;
    }
    return (
      LanguagePack(code: code, name: rawName.trim(), strings: strings),
      null,
    );
  }

  /// 读取并解析一个语言包文件；IO 或解析失败返回 `(null, 错误)`。
  static Future<(LanguagePack?, String?)> tryLoad(File file) async {
    String source;
    try {
      source = await file.readAsString();
    } catch (error) {
      return (null, '文件读取失败：$error');
    }
    return tryParse(source);
  }
}
