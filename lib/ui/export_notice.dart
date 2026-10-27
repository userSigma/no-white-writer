import 'package:fluent_ui/fluent_ui.dart';

/// 只呈现导出结果，不做任何文件 IO；打开目录由调用方注入。
Future<void> showExportNotice(
  BuildContext context, {
  required String title,
  String? message,
  String? filePath,
  Future<void> Function(String path)? openDirectory,
  VoidCallback? onRetry,
}) => showDialog<void>(
  context: context,
  builder: (context) => _ExportNoticeDialog(
    title: title,
    message: message,
    filePath: filePath,
    openDirectory: openDirectory,
    onRetry: onRetry,
  ),
);

class _ExportNoticeDialog extends StatefulWidget {
  const _ExportNoticeDialog({
    required this.title,
    this.message,
    this.filePath,
    this.openDirectory,
    this.onRetry,
  });
  final String title;
  final String? message;
  final String? filePath;
  final Future<void> Function(String path)? openDirectory;
  final VoidCallback? onRetry;

  @override
  State<_ExportNoticeDialog> createState() => _ExportNoticeDialogState();
}

class _ExportNoticeDialogState extends State<_ExportNoticeDialog> {
  String? _openError;
  bool _opening = false;

  Future<void> _open() async {
    final path = widget.filePath;
    final open = widget.openDirectory;
    if (path == null || open == null || _opening) return;
    setState(() => _opening = true);
    try {
      await open(path);
    } catch (error) {
      if (mounted) setState(() => _openError = '$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final path = widget.filePath;
    final openError = _openError;
    final retry = widget.onRetry;
    return ContentDialog(
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message != null) SelectableText(message),
          if (path != null) ...[
            const SizedBox(height: 8),
            SelectableText(path, key: const ValueKey('export-result-path')),
          ],
          if (openError != null) ...[
            const SizedBox(height: 8),
            Text(
              '打开文件夹失败：$openError',
              key: const ValueKey('export-open-error'),
            ),
          ],
        ],
      ),
      actions: [
        if (path != null && widget.openDirectory != null)
          Button(
            key: const ValueKey('export-open-directory'),
            onPressed: _opening ? null : _open,
            child: const Text('打开文件夹'),
          ),
        if (retry != null)
          Button(
            key: const ValueKey('export-retry'),
            onPressed: () {
              Navigator.pop(context);
              retry();
            },
            child: const Text('重试'),
          ),
        FilledButton(
          key: const ValueKey('export-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
