import 'package:flutter/painting.dart';

/// 应用界面（非编辑区）使用的系统默认字体。
///
/// Windows 11 的界面正文用「Segoe UI Variable Text」排拉丁字母，中文经字体
/// 链接落到「Microsoft YaHei UI」；Windows 10 没有变量字体时按
/// [kSystemUiFontFallback] 退到「Segoe UI」再落到雅黑界面字。
///
/// 界面文本因此显式调用系统字体，而不是依赖 Flutter 引擎的隐式默认族；
/// 编辑区（章节正文）仍显式使用内置的 LXGWWenKaiGB，不受这里影响。
const String kSystemUiFontFamily = 'Segoe UI Variable Text';

/// 界面字体回退链：变量字体缺失时依次尝试。
const List<String> kSystemUiFontFallback = <String>[
  'Segoe UI',
  'Microsoft YaHei UI',
];

/// 界面默认文本样式：只声明字体族，字号与颜色仍由各处样式决定。
const TextStyle kSystemUiTextStyle = TextStyle(
  fontFamily: kSystemUiFontFamily,
  fontFamilyFallback: kSystemUiFontFallback,
);
