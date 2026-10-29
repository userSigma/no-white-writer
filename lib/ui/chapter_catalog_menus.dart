import 'package:fluent_ui/fluent_ui.dart';

import '../core/i18n/i18n.dart';
import '../core/models.dart';
import '../core/text/composing.dart';
import '../state/export_controller.dart';
import '../state/workspace_controller.dart';
import 'chapter_drag_interaction.dart';
import 'chapter_volume_name_editor.dart';
import 'context_menu.dart';
import 'export_notice.dart';
import 'numbering_settings_dialog.dart';

/// Menus capture stable export IDs and dispatch edits through the workspace.
class ChapterCatalogMenus {
  ChapterCatalogMenus({
    required this.context,
    required this.workspace,
    required this.nameEditor,
    required this.drag,
    this.exporter,
    this.revealPath,
    this.onCreated,
  });
  final BuildContext context;
  final WorkspaceController workspace;
  final ChapterVolumeNameEditor nameEditor;
  final ChapterDragInteraction drag;
  final ExportController? exporter;
  final Future<bool> Function(String path)? revealPath;
  final VoidCallback? onCreated;
  WorkspaceController get w => workspace;
  BookIndex get book => w.book;
  Future<void> _appendVolume(BuildContext context) async {
    if (!await nameEditor.submit() || !context.mounted) return;
    await _ask(
      context,
      t(context, 'volume.new.title'),
      t(context, 'volume.new.hint'),
      onSave: (name) async {
        final saveFailed = t(context, 'volume.save.failed');
        final ok = await w.appendVolume(name);
        if (!ok) {
          throw StateError(w.error ?? saveFailed);
        }
      },
    );
  }

  /// 书名菜单（任务3）：取代侧栏顶部独立的「新建卷」按钮。
  /// 菜单项：新建卷（复用 [_appendVolume]）、自动章节序号设置（任务4
  /// 全局层入口）；书名行右键/长按与右端 more 按钮打开同一菜单，
  /// 预留后续扩展（在此追加 MenuAction 即可）。
  Future<void> bookMenu(BuildContext context, Offset position) async {
    if (w.editingLocked ||
        w.moving ||
        w.editor.isComposing ||
        nameEditor.composing) {
      return;
    }
    final action = await showContextMenu(context, position, [
      MenuAction('newVolume', t(context, 'sidebar.newVolume')),
      MenuAction('numbering', t(context, 'sidebar.numberingSettings')),
    ]);
    if (!context.mounted) return;
    switch (action) {
      case 'newVolume':
        await _appendVolume(context);
      case 'numbering':
        if (!await nameEditor.submit() || !context.mounted) return;
        await showDialog<bool>(
          context: context,
          builder: (_) => NumberingSettingsDialog(workspace: w),
        );
    }
  }

  Future<void> appendChapter(Volume volume) async {
    if (!await nameEditor.submit()) return;
    final ok = await w.appendChapter(volume);
    if (ok && context.mounted) onCreated?.call();
  }

  Future<void> volumeMenu(
    BuildContext context,
    Volume volume,
    Offset position,
  ) async {
    if (w.editingLocked ||
        w.moving ||
        w.editor.isComposing ||
        nameEditor.composing) {
      return;
    }
    final exporter = this.exporter;
    final volumeId = volume.id;
    final mode = volume.numberingMode;
    final action = await showContextMenu(context, position, [
      MenuAction('rename', t(context, 'volume.rename')),
      MenuAction('add', t(context, 'volume.newChapter')),
      MenuAction(
        'numbering',
        t(context, 'volume.numbering'),
        children: [
          MenuAction(
            'numbering-follow-global',
            t(context, 'volume.numbering.followGlobal'),
            checked: mode == VolumeNumberingMode.followGlobal,
          ),
          MenuAction(
            'numbering-independent',
            t(context, 'volume.numbering.independent'),
            checked: mode == VolumeNumberingMode.independent,
          ),
          MenuAction(
            'numbering-none',
            t(context, 'volume.numbering.none'),
            checked: mode == VolumeNumberingMode.none,
          ),
          MenuAction(
            'numbering-edit',
            t(context, 'volume.numbering.editRule'),
            enabled: mode == VolumeNumberingMode.independent,
          ),
        ],
      ),
      MenuAction('move', t(context, 'volume.move')),
      if (exporter != null) MenuAction('export', t(context, 'volume.export')),
      MenuAction('delete', t(context, 'volume.delete')),
    ]);
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await nameEditor.start(volume);
      case 'move':
        await drag.enterMove(true);
      case 'add':
        await appendChapter(volume);
      case 'export':
        if (exporter == null) return;
        if (!await nameEditor.submit() || !context.mounted) return;
        await _export(
          () => ExportTarget.volume(w.book.id, volumeId),
          t(context, 'volume.export'),
        );
      case 'numbering-follow-global':
        await w.setVolumeNumberingMode(
          volume,
          VolumeNumberingMode.followGlobal,
        );
      case 'numbering-independent':
        // 选择「卷内独立编号」：先落模式（沿用/默认规则镜像开启），
        // 再直接打开规则编辑浮窗精调；取消编辑也保持该模式。
        final ok = await w.setVolumeNumberingMode(
          volume,
          VolumeNumberingMode.independent,
        );
        if (ok && context.mounted) {
          await showDialog<bool>(
            context: context,
            builder: (_) =>
                NumberingSettingsDialog(workspace: w, volume: volume),
          );
        }
      case 'numbering-none':
        await w.setVolumeNumberingMode(volume, VolumeNumberingMode.none);
      case 'numbering-edit':
        if (!await nameEditor.submit() || !context.mounted) return;
        await showDialog<bool>(
          context: context,
          builder: (_) => NumberingSettingsDialog(workspace: w, volume: volume),
        );
      case 'delete':
        if (!await nameEditor.submit() || !context.mounted) return;
        if (await _confirm(
          context,
          t(context, 'volume.delete.confirm', {
            'name': volume.title,
            'count': '${volume.chapters.length}',
          }),
        )) {
          await w.deleteVolume(volume);
        }
    }
  }

  Future<void> chapterMenu(
    BuildContext context,
    Volume volume,
    ChapterMeta chapter,
    Offset position,
  ) async {
    if (w.editingLocked ||
        w.moving ||
        w.editor.isComposing ||
        nameEditor.composing) {
      return;
    }
    final exporter = this.exporter;
    final chapterId = chapter.id;
    final action = await showContextMenu(context, position, [
      MenuAction('rename', t(context, 'chapter.rename')),
      MenuAction('move', t(context, 'chapter.move')),
      if (exporter != null) MenuAction('export', t(context, 'chapter.export')),
      MenuAction('delete', t(context, 'chapter.delete')),
    ]);
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await _ask(
          context,
          t(context, 'chapter.rename'),
          t(context, 'chapter.hint'),
          initial: w.chapter?.id == chapter.id
              ? w.editor.title.text
              : chapter.title,
          onSave: (name) async {
            final saveFailed = t(context, 'chapter.save.failed');
            final ok = await w.renameChapter(chapter, name);
            if (!ok) {
              throw StateError(w.error ?? saveFailed);
            }
          },
        );
      case 'move':
        await drag.enterMove(false);
      case 'export':
        if (exporter == null) return;
        if (!await nameEditor.submit() || !context.mounted) return;
        await _export(
          () => ExportTarget.chapter(w.book.id, volume.id, chapterId),
          t(context, 'chapter.export'),
        );
      case 'delete':
        if (await _confirm(
          context,
          t(context, 'chapter.delete.confirm', {'name': chapter.title}),
        )) {
          await w.deleteChapter(volume, chapter);
        }
    }
  }

  /// 以菜单打开时捕获的稳定 ID 导出；失败保留重试入口，不吃掉异常。
  Future<void> _export(ExportTarget Function() target, String label) async {
    final exporter = this.exporter;
    if (exporter == null) return;
    if (exporter.busy) {
      await _showNotice(label, t(context, 'export.busy'));
      return;
    }
    try {
      final file = await exporter.export(target());
      if (!context.mounted) return;
      if (file == null) {
        await _showNotice(
          label,
          exporter.message ?? t(context, 'export.empty'),
        );
        return;
      }
      final dir = file.parent.path;
      final reveal = revealPath;
      final openDirFailed = t(context, 'export.openDir.failed');
      await showExportNotice(
        context,
        title: t(context, 'export.done.title', {'label': label}),
        message: t(context, 'export.done.body'),
        filePath: file.path,
        openDirectory: reveal == null
            ? null
            : (_) async {
                if (!await reveal(dir)) {
                  throw StateError(openDirFailed);
                }
              },
      );
    } catch (error) {
      if (!context.mounted) return;
      await showExportNotice(
        context,
        title: t(context, 'export.failed.title', {'label': label}),
        message: '$error',
        onRetry: () {
          if (context.mounted) _export(target, label);
        },
      );
    }
  }

  Future<void> _showNotice(String title, String message) async {
    if (!context.mounted) return;
    await _confirmMessage(context, title, message);
  }
}

Future<String?> _ask(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  required Future<void> Function(String) onSave,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _NameDialog(title: title, hint: hint, initial: initial, onSave: onSave),
);
Future<void> _confirmMessage(
  BuildContext context,
  String title,
  String message,
) async => showDialog<void>(
  context: context,
  builder: (context) => ContentDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      FilledButton(
        key: const ValueKey('export-notice-close'),
        onPressed: () => Navigator.pop(context),
        child: Text(t(context, 'common.ok')),
      ),
    ],
  ),
);

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(title),
        content: Text(t(context, 'delete.confirm.body')),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(context, 'common.delete')),
          ),
        ],
      ),
    ) ??
    false;

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.onSave,
  });
  final String title, hint, initial;
  final Future<void> Function(String) onSave;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;
  bool get composing => isComposingValue(controller.value);
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (_saving || composing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(controller.text);
      if (mounted) Navigator.pop(context, controller.text);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    // FluentDialogRoute's default DismissAction calls pop directly and bypasses
    // PopScope. Consume Escape here while IME or the save is still in progress.
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          if (!_saving && !composing) Navigator.pop(context);
          return null;
        },
      ),
    },
    child: PopScope(
      canPop: !_saving && !composing,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 500),
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextBox(
              key: const ValueKey('name-input'),
              controller: controller,
              autofocus: true,
              enabled: !_saving,
              maxLines: 1,
              placeholder: widget.hint,
              onEditingComplete: () {},
              onSubmitted: (_) => submit(),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
        actions: [
          Button(
            onPressed: _saving || composing
                ? null
                : () => Navigator.pop(context),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: _saving || composing ? null : submit,
            child: Text(t(context, 'common.confirm')),
          ),
        ],
      ),
    ),
  );
}
