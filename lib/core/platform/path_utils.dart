import 'dart:io';

/// 路径拼接与文件名清洗（PLAN.md §5.3 / §4.9 第 6 条）。
/// 唯一允许出现路径分隔符实现细节的地方；其余模块一律走这里。
String pathJoin(String base, String name) {
  if (base.endsWith(Platform.pathSeparator)) return '$base$name';
  return '$base${Platform.pathSeparator}$name';
}

String fileNameOf(String filePath) {
  final int i = filePath.lastIndexOf(Platform.pathSeparator);
  return i < 0 ? filePath : filePath.substring(i + 1);
}

/// 去掉文件名里的非法字符（`\ / : * ? " < > |` 与控制字符），限制长度，保留扩展名由调用方处理。
String sanitizeFileName(String raw, {int maxRunes = 80}) {
  final String input = raw.trim().isEmpty ? '未命名' : raw.trim();
  final StringBuffer out = StringBuffer();
  int count = 0;
  for (final int rune in input.runes) {
    if (count >= maxRunes) break;
    final bool bad =
        rune < 0x20 || '\\/:*?"<>|'.codeUnits.contains(rune) || rune == 0x7f;
    out.writeCharCode(bad ? 0x5f : rune); // '_'
    count++;
  }
  String name = out.toString().trim();
  while (name.endsWith('.') || name.endsWith(' ')) {
    name = name.substring(0, name.length - 1);
  }
  return name.isEmpty ? '未命名' : name;
}

/// 同名文件加 ` (2)`、` (3)`…（PLAN.md §4.9）。
String uniqueFileName(String base, Set<String> taken) {
  String candidate = base;
  int n = 2;
  while (taken.contains(candidate.toLowerCase())) {
    candidate = '$base ($n)';
    n++;
  }
  return candidate;
}

Future<Directory> ensureDirectory(String path) async {
  final Directory dir = Directory(path);
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}
