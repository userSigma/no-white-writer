import 'dart:io';

import '../logging/app_logger.dart';

/// 损坏 JSON 的统一留存：改名为 `<path>.corrupt-<millis>` 交给人排查。
/// 改名失败不阻断启动（调用方各自走「重建/默认值」路径）。
Future<void> keepCorrupt(File file, String stem) async {
  try {
    final String suffix = DateTime.now().millisecondsSinceEpoch.toString();
    await file.rename('${file.path}.corrupt-$suffix');
    AppLogger.instance.warn('storage.corrupt.kept', <String, Object?>{
      'file': file.path,
      'backup': '${file.path}.corrupt-$suffix',
      'stem': stem,
    });
  } catch (_) {
    // 保存失败不阻断启动。
  }
}
