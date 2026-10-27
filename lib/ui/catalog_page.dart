import 'package:fluent_ui/fluent_ui.dart';

import '../app_context.dart';
import '../core/models.dart';
import '../core/text/word_count.dart';
import 'editor_page.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// 书内目录：卷与章的两级列表，所有改动直接改内存里的 [BookIndex] 再落盘。
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.app,
    required this.summary,
    required this.book,
  });

  final AppContext app;
  final BookSummary summary;
  final BookIndex book;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  BookIndex get book => widget.book;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: paperOrInk(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 28, 12),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(FluentIcons.back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: bodyTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${book.volumes.length} 卷 · ${book.allChapters.length} 章 · '
                        '${formatWordCount(book.totalWordCount)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: mutedTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Button(
                  onPressed: () => _renameBookDialog(),
                  child: const Text('改书名'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _appendVolume(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(FluentIcons.add),
                      SizedBox(width: 6),
                      Text('新建卷'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            style: DividerThemeData(
              horizontalMargin: const EdgeInsetsDirectional.symmetric(
                horizontal: 24,
              ),
              thickness: 1,
              decoration: BoxDecoration(color: hairlineColor(context)),
            ),
          ),
          Expanded(
            child: book.volumes.isEmpty
                ? _EmptyCatalog(onCreate: _appendVolume)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: <Widget>[
                      for (final Volume volume in book.volumes)
                        _VolumeSection(
                          app: widget.app,
                          book: book,
                          volume: volume,
                          onOpenChapter: _openChapter,
                          onChanged: () => setState(() {}),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _appendVolume() async {
    final String? title = await _askText('新建卷', '卷名（留空按序号命名）');
    if (title == null || !mounted) return;
    await widget.app.library.appendVolume(book, title: title);
    setState(() {});
  }

  Future<void> _openChapter(Volume volume, ChapterMeta chapter) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (BuildContext context, _, _) => EditorPage(
          app: widget.app,
          book: book,
          volume: volume,
          chapter: chapter,
        ),
        transitionsBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              _,
              Widget child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _renameBookDialog() async {
    final String? title = await _askText('改书名', '书名', initial: book.title);
    if (title == null || title.trim().isEmpty || !mounted) return;
    book.title = title.trim();
    widget.summary.title = title.trim();
    await widget.app.library.saveBook(book);
    setState(() {});
  }

  Future<String?> _askText(String title, String hint, {String initial = ''}) {
    final TextEditingController controller = TextEditingController(
      text: initial,
    );
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => ContentDialog(
        title: Text(title),
        content: TextBox(
          controller: controller,
          autofocus: true,
          placeholder: hint,
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('还没有卷', style: TextStyle(color: bodyTextColor(context))),
          const SizedBox(height: 12),
          Button(onPressed: onCreate, child: const Text('新建第一卷')),
        ],
      ),
    );
  }
}

class _VolumeSection extends StatelessWidget {
  const _VolumeSection({
    required this.app,
    required this.book,
    required this.volume,
    required this.onOpenChapter,
    required this.onChanged,
  });

  final AppContext app;
  final BookIndex book;
  final Volume volume;
  final void Function(Volume volume, ChapterMeta chapter) onOpenChapter;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: paperOrInk(context),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Expander(
        initiallyExpanded: true,
        header: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                volume.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: bodyTextColor(context),
                ),
              ),
            ),
            Text(
              '${volume.chapters.length} 章 · ${formatWordCount(volume.wordCount)}',
              style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.more),
              onPressed: () => _volumeMenu(context),
            ),
          ],
        ),
        content: Column(
          children: <Widget>[
            for (final ChapterMeta chapter in volume.chapters)
              ListTile(
                onPressed: () => onOpenChapter(volume, chapter),
                leading: const Icon(FluentIcons.text_document, size: 16),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatWordCount(chapter.wordCount)} · '
                  '${relativeTime(chapter.updatedAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: mutedTextColor(context),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(FluentIcons.more, size: 14),
                  onPressed: () => _chapterMenu(context, chapter),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  onPressed: () => _appendChapter(context),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(FluentIcons.add, size: 14),
                      SizedBox(width: 6),
                      Text('新建章'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _volumeMenu(BuildContext context) async {
    final String? action = await _showActions(context, <String, String>{
      'rename': '重命名卷',
      'append': '在本卷新建章',
      'up': '上移卷',
      'down': '下移卷',
      'delete': '删除卷',
    });
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'rename':
        final String? title = await _askText(
          context,
          '重命名卷',
          '卷名',
          initial: volume.title,
        );
        if (title != null) {
          await app.library.renameVolume(book, volume, title);
        }
        break;
      case 'append':
        await _appendChapter(context);
        break;
      case 'up':
        await app.library.moveVolume(book, volume, -1);
        break;
      case 'down':
        await app.library.moveVolume(book, volume, 1);
        break;
      case 'delete':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => ContentDialog(
            title: Text('删除《${volume.title}》？'),
            content: const Text('整卷章节会移到 trash，不立刻消失。'),
            actions: <Widget>[
              Button(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (ok == true) await app.library.deleteVolume(book, volume);
        break;
    }
    onChanged();
  }

  Future<void> _chapterMenu(BuildContext context, ChapterMeta chapter) async {
    final String? action = await _showActions(context, <String, String>{
      'open': '打开',
      'rename': '重命名章',
      'up': '上移章',
      'down': '下移章',
      'delete': '删除章',
    });
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'open':
        onOpenChapter(volume, chapter);
        return;
      case 'rename':
        final String? title = await _askText(
          context,
          '重命名章',
          '章名',
          initial: chapter.title,
        );
        if (title != null) {
          await app.library.renameChapter(book, chapter, title);
        }
        break;
      case 'up':
        await app.library.moveChapter(book, volume, chapter, -1);
        break;
      case 'down':
        await app.library.moveChapter(book, volume, chapter, 1);
        break;
      case 'delete':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => ContentDialog(
            title: Text('删除《${chapter.title}》？'),
            content: const Text('正文会移到 trash，不立刻消失。'),
            actions: <Widget>[
              Button(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (ok == true) await app.library.deleteChapter(book, volume, chapter);
        break;
    }
    onChanged();
  }

  Future<void> _appendChapter(BuildContext context) async {
    final String? title = await _askText(context, '新建章', '章名（留空按序号命名）');
    if (title == null) return;
    await app.library.appendChapter(book, volume, title: title);
    onChanged();
  }
}

Future<String?> _showActions(
  BuildContext context,
  Map<String, String> actions,
) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => ContentDialog(
      title: const Text('操作'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final MapEntry<String, String> entry in actions.entries)
            Button(
              onPressed: () => Navigator.of(context).pop(entry.key),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(entry.value),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
}) {
  final TextEditingController controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => ContentDialog(
      title: Text(title),
      content: TextBox(
        controller: controller,
        autofocus: true,
        placeholder: hint,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
