import 'package:flutter/services.dart';

/// 是否处于 IME 组词（拼音/注音未上屏）状态：composing 区间有效且非折叠。
///
/// 组词期间禁止结构性磁盘操作与文本覆盖，防止拼音串被异步读盘/裁剪破坏
/// （PLAN.md：输入法安全）。全工程统一用这一个谓词，不得手抄条件。
bool isComposingValue(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;
