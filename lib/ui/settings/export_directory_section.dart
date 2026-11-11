import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/i18n/i18n.dart';
import '../../core/storage/app_paths.dart';
import '../../state/settings_controller.dart';
import '../theme/tokens.dart';
import 'settings_row.dart';

/// 浮窗私有的目录选择会话；保留 P2 分区边界，目录由原生选择器提交。
/// 保存失败保留已选路径及控制器错误，关闭或重试时再次提交，不回滚用户选择。
class ExportDirectoryDraft extends ChangeNotifier {
  ExportDirectoryDraft({
    required this.settings,
    required this.paths,
    required this.selectDirectory,
    required this.revealDirectory,
    required this.notice,
  }) : path = TextEditingController(
         text: paths.exportRoot(settings.settings.exportDirectory),
       ) {
    settings.addListener(_syncPath);
  }

  final SettingsController settings;
  final AppPaths paths;
  final Future<String?> Function({String? initialDirectory}) selectDirectory;
  final Future<bool> Function(String) revealDirectory;
  final void Function(String?, bool) notice;
  final TextEditingController path;
  bool working = false;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _syncPath() {
    if (_disposed) return;
    final effective = paths.exportRoot(settings.settings.exportDirectory);
    if (path.text != effective) path.text = effective;
    _changed();
  }

  Future<bool> prepareClose(BuildContext context) async {
    if (working || _disposed) return false;
    try {
      await settings.flush();
      return true;
    } catch (error) {
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.saveError', {'error': '$error'}), true);
      }
      return false;
    }
  }

  Future<void> change(BuildContext context, {bool useDefault = false}) async {
    if (working || _disposed) return;
    working = true;
    notice(null, false);
    _changed();
    try {
      final selected = useDefault
          ? null
          : await selectDirectory(initialDirectory: path.text);
      if (_disposed || !context.mounted || (!useDefault && selected == null)) {
        return;
      }
      settings.setExportDirectory(selected);
      await settings.flush();
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.exportDir.saved'), false);
      }
    } catch (error) {
      // 持久化错误由 SettingsController 持有；原生选择器错误单独展示。
      if (!_disposed && context.mounted && settings.saveError == null) {
        notice('$error', true);
      }
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> retry(BuildContext context) async {
    if (working || _disposed) return;
    working = true;
    _changed();
    try {
      await settings.flush();
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.saved'), false);
      }
    } catch (error) {
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.saveError', {'error': '$error'}), true);
      }
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> openDirectory(BuildContext context, String directory) async {
    if (working || _disposed) return;
    working = true;
    _changed();
    try {
      final opened = await revealDirectory(directory);
      if (!_disposed && context.mounted) {
        notice(
          t(
            context,
            opened ? 'settings.openDir.opened' : 'settings.openDir.failed',
          ),
          !opened,
        );
      }
    } catch (error) {
      if (!_disposed && context.mounted) notice('$error', true);
    } finally {
      working = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_syncPath);
    path.dispose();
    super.dispose();
  }
}

/// 只读路径和原生选择按钮；不触达应用依赖容器。
class ExportDirectorySection extends StatelessWidget {
  const ExportDirectorySection({
    super.key,
    required this.draft,
    required this.paths,
  });

  final ExportDirectoryDraft draft;
  final AppPaths paths;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsRow(
          label: t(context, 'settings.exportDir'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextBox(
                      key: const ValueKey('settings-export-path'),
                      controller: draft.path,
                      readOnly: true,
                      enabled: !draft.working,
                      maxLines: 2,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    key: const ValueKey('settings-change-export-path'),
                    onPressed: draft.working
                        ? null
                        : () => unawaited(draft.change(context)),
                    child: Text(t(context, 'settings.exportDir.change')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Button(
                    onPressed: draft.working
                        ? null
                        : () => unawaited(
                            draft.openDirectory(context, draft.path.text),
                          ),
                    child: Text(t(context, 'settings.exportDir.open')),
                  ),
                  Button(
                    key: const ValueKey('settings-export-reset'),
                    onPressed: draft.working
                        ? null
                        : () => unawaited(
                            draft.change(context, useDefault: true),
                          ),
                    child: Text(t(context, 'settings.exportDir.reset')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(height: 1, color: hairlineColor(context)),
        ),
        SettingsRow(
          label: t(context, 'settings.systemDir'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Button(
                onPressed: draft.working
                    ? null
                    : () => unawaited(
                        draft.openDirectory(context, paths.dataRootPath),
                      ),
                child: Text(t(context, 'settings.dataDir')),
              ),
              Button(
                onPressed: draft.working
                    ? null
                    : () => unawaited(
                        draft.openDirectory(context, paths.logsDir),
                      ),
                child: Text(t(context, 'settings.logsDir')),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
