import 'dart:io';

import 'package:flutter/foundation.dart';

import 'builtin_packs.dart';
import 'language_pack.dart';

/// i18n 状态中枢：注册语言包、跟踪当前语言、提供带回退的翻译查找。
///
/// - 内置 `zh-CN`（默认与回退）与 `en`；
/// - 外部语言包从应用数据目录的 `languages/` 子目录扫描 JSON 注册；
/// - [translate] 查找顺序：当前语言 → `zh-CN` → key 本身。
class I18nController extends ChangeNotifier {
  I18nController() {
    for (final source in builtinPackSources) {
      _packs[source.code] = LanguagePack(
        code: source.code,
        name: source.name,
        strings: source.strings,
      );
      _builtinOrder.add(source.code);
    }
  }

  /// 回退语言（也是默认语言）。
  static const String fallbackCode = 'zh-CN';

  final Map<String, LanguagePack> _packs = <String, LanguagePack>{};
  final List<String> _builtinOrder = <String>[];
  final Set<String> _externalCodes = <String>{};
  final List<String> _loadErrors = <String>[];
  String _currentCode = fallbackCode;

  /// 全部已注册语言包：内置在前（声明序），外部包按 code 排序在后。
  List<LanguagePack> get packs {
    final List<LanguagePack> external = <LanguagePack>[
      for (final String code in _externalCodes) _packs[code]!,
    ]..sort(
        (LanguagePack a, LanguagePack b) => a.code.compareTo(b.code),
      );
    return List<LanguagePack>.unmodifiable(
      <LanguagePack>[
        for (final String code in _builtinOrder) _packs[code]!,
        ...external,
      ],
    );
  }

  /// 最近一次外部语言包加载的错误清单（文件名 + 原因）。
  List<String> get loadErrors => List<String>.unmodifiable(_loadErrors);

  String get currentCode => _currentCode;

  LanguagePack get current =>
      _packs[_currentCode] ?? _packs[fallbackCode]!;

  LanguagePack? byCode(String code) => _packs[code];

  /// 注册外部语言包；与已有包同 code 时不覆盖，返回 false。
  bool register(LanguagePack pack) {
    if (_packs.containsKey(pack.code)) return false;
    _packs[pack.code] = pack;
    _externalCodes.add(pack.code);
    notifyListeners();
    return true;
  }

  /// 切换当前语言；未注册的 code 返回 false 且不改变状态。
  bool setLanguage(String code) {
    if (!_packs.containsKey(code)) return false;
    if (code == _currentCode) return true;
    _currentCode = code;
    notifyListeners();
    return true;
  }

  /// 应用持久化的语言选择；为空或未注册时保持回退语言，返回是否生效。
  bool applySaved(String? code) {
    if (code == null || code.trim().isEmpty) return false;
    return setLanguage(code.trim());
  }

  /// 翻译查找：当前语言 → 回退 `zh-CN` → key 本身；然后填充 `{占位符}`。
  String translate(String key, [Map<String, String>? args]) {
    String text =
        current.strings[key] ??
        _packs[fallbackCode]!.strings[key] ??
        key;
    if (args != null && args.isNotEmpty) {
      for (final MapEntry<String, String> entry in args.entries) {
        text = text.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return text;
  }

  /// 扫描目录下的 `*.json` 语言包并注册；逐个容错，坏文件记入错误清单并跳过。
  ///
  /// 返回本次加载的错误清单（空列表 = 全部成功）；目录不存在视为空目录。
  Future<List<String>> loadExternal(Directory dir) async {
    _loadErrors.clear();
    final List<File> files = <File>[];
    try {
      final List<FileSystemEntity> entries = await dir
          .list(followLinks: false)
          .toList();
      files.addAll(entries.whereType<File>());
    } on FileSystemException {
      // 目录不存在 / 不可读：没有外部语言包，不算错误。
      return const <String>[];
    }
    files.removeWhere(
      (File file) => !file.path.toLowerCase().endsWith('.json'),
    );
    files.sort(
      (File a, File b) => a.path.compareTo(b.path),
    );
    for (final File file in files) {
      final String fileName = file.path.split(RegExp(r'[\\/]')).last;
      final (LanguagePack? pack, String? error) = await LanguagePack.tryLoad(
        file,
      );
      if (pack == null) {
        _loadErrors.add('$fileName：$error');
        continue;
      }
      if (!register(pack)) {
        _loadErrors.add('$fileName：语言代码 ${pack.code} 已存在，已跳过');
      }
    }
    return List<String>.unmodifiable(_loadErrors);
  }
}
