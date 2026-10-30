import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/i18n/i18n.dart';
import '../../core/storage/app_paths.dart';
import '../../core/text/composing.dart';
import '../../state/settings_controller.dart';
import 'settings_row.dart';

/// 浮窗私有的目录编辑会话：保存失败保留输入，退出前处理组词与丢弃确认。
/// 不拥有 SettingsController，也不在销毁时隐式保存或丢弃草稿。
class ExportDirectoryDraft extends ChangeNotifier {
  ExportDirectoryDraft({
    required this.settings,
    required this.revealDirectory,
    required this.notice,
  }) : path = TextEditingController(
         text: settings.settings.exportDirectory ?? '',
       ) {
    path.addListener(_changed);
  }

  final SettingsController settings;
  final Future<bool> Function(String) revealDirectory;
  final void Function(String?, bool) notice;
  final TextEditingController path;
  bool working = false;
  bool confirming = false;
  bool _disposed = false;

  bool get composing => isComposingValue(path.value);
  bool get dirty =>
      path.text.trim() != (settings.settings.exportDirectory ?? '');

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> prepareClose(BuildContext context) async {
    if (working || composing || confirming || _disposed) return false;
    if (dirty) {
      confirming = true;
      final bool? discard;
      try {
        discard = await showDialog<bool>(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(t(context, 'settings.exportDir.confirm.title')),
            content: Text(t(context, 'settings.exportDir.confirm.body')),
            actions: [
              Button(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t(context, 'settings.exportDir.confirm.keep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t(context, 'settings.exportDir.confirm.discard')),
              ),
            ],
          ),
        );
      } finally {
        confirming = false;
      }
      if (_disposed || !context.mounted || discard != true) return false;
      path.text = settings.settings.exportDirectory ?? '';
    }
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

  Future<void> save(BuildContext context, {bool useDefault = false}) async {
    if (working || composing || _disposed) return;
    working = true;
    // 清除上一条即时消息；持久化错误仍由控制器持有。
    notice(null, false);
    _changed();
    final previous = settings.settings.exportDirectory;
    if (useDefault) path.text = '';
    final text = path.text.trim();
    settings.setExportDirectory(text.isEmpty ? null : text);
    try {
      await settings.flush();
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.exportDir.saved'), false);
      }
    } catch (_) {
      // 只恢复已确认的偏好，不覆盖失败输入；重试必须再次提交当前草稿。
      settings.settings.exportDirectory = previous;
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> retry(BuildContext context) async {
    if (working || composing || _disposed) return;
    if (dirty) return save(context);
    try {
      await settings.flush();
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.saved'), false);
      }
    } catch (error) {
      if (!_disposed && context.mounted) {
        notice(t(context, 'settings.saveError', {'error': '$error'}), true);
      }
    }
  }

  Future<void> openDirectory(BuildContext context, String directory) async {
    if (working || composing || _disposed) return;
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
    path.removeListener(_changed);
    path.dispose();
    super.dispose();
  }
}

/// 目录字段和相关操作只依赖该编辑会话与路径，不触达应用依赖容器。
class ExportDirectorySection extends StatelessWidget {
  const ExportDirectorySection({
    super.key,
    required this.draft,
    required this.paths,
  });

  final ExportDirectoryDraft draft;
  final AppPaths paths;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SettingsRow(
        label: t(context, 'settings.exportDir'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextBox(
              key: const ValueKey('settings-export-path'),
              controller: draft.path,
              enabled: !draft.working,
              placeholder: t(context, 'settings.exportDir.hint'),
              onEditingComplete: () {},
              onSubmitted: (_) {
                if (!draft.composing) unawaited(draft.save(context));
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Button(
                  onPressed: draft.working || draft.composing
                      ? null
                      : () => unawaited(draft.save(context)),
                  child: Text(t(context, 'common.save')),
                ),
                Button(
                  onPressed: draft.working || draft.composing
                      ? null
                      : () => unawaited(draft.save(context, useDefault: true)),
                  child: Text(t(context, 'settings.exportDir.reset')),
                ),
                Button(
                  onPressed: draft.working || draft.composing
                      ? null
                      : () {
                          if (draft.dirty) {
                            draft.notice(
                              t(context, 'settings.exportDir.pending'),
                              true,
                            );
                            return;
                          }
                          unawaited(
                            draft.openDirectory(
                              context,
                              paths.exportRoot(
                                draft.settings.settings.exportDirectory,
                              ),
                            ),
                          );
                        },
                  child: Text(t(context, 'settings.exportDir.open')),
                ),
              ],
            ),
          ],
        ),
      ),
      SettingsRow(
        label: '',
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
                  : () =>
                        unawaited(draft.openDirectory(context, paths.logsDir)),
              child: Text(t(context, 'settings.logsDir')),
            ),
          ],
        ),
      ),
    ],
  );
}
