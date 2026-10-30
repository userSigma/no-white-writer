import 'package:no_white_writer/app_context.dart';
import 'package:no_white_writer/core/models.dart';
import 'package:no_white_writer/ui/editor_page.dart';
import 'package:no_white_writer/ui/shelf_page.dart';

// Test composition root: production pages never receive the application container.
ShelfPage shelfPage({required AppContext app, bool autoOpenSettings = false}) =>
    ShelfPage(
      library: app.library,
      editor: app.editor,
      exporter: app.exporter,
      settings: app.settings,
      i18n: app.i18n,
      platform: app.platform,
      paths: app.paths,
      uiGuards: app.uiGuards,
      recoveredChapterCount: app.recoveredChapterCount,
      autoOpenSettings: autoOpenSettings,
    );

EditorPage editorPage({
  required AppContext app,
  required BookIndex book,
  Volume? volume,
  ChapterMeta? chapter,
}) => EditorPage(
  library: app.library,
  editor: app.editor,
  exporter: app.exporter,
  settings: app.settings,
  i18n: app.i18n,
  platform: app.platform,
  paths: app.paths,
  uiGuards: app.uiGuards,
  recoveredChapterCount: app.recoveredChapterCount,
  book: book,
  volume: volume,
  chapter: chapter,
);
