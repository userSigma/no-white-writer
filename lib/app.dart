import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:fluent_ui/fluent_ui.dart';

import 'app_context.dart';
import 'core/chapter_display.dart';
import 'core/i18n/i18n.dart';
import 'core/models.dart';
import 'core/logging/app_logger.dart';
import 'core/platform/platform_services.dart';
import 'state/editor_controller.dart';
import 'ui/shelf_page.dart';
import 'ui/theme/live_theme_scope.dart';
import 'ui/theme/tokens.dart';

/// 应用根：主题、中文 locale、窗口标题同步、退出拦截（PLAN.md §6.1 / §7.5）。
class NoWhiteWriterApp extends StatefulWidget {
  const NoWhiteWriterApp({super.key, required this.app, this.home});

  final AppContext app;

  /// 覆盖起始页（验收/截图与以后的 deep-link 用）；为空时进书架。
  final Widget? home;

  @override
  State<NoWhiteWriterApp> createState() => _NoWhiteWriterAppState();
}

class _NoWhiteWriterAppState extends State<NoWhiteWriterApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  ThemeMode _themeMode = ThemeMode.system;
  AppThemeData? _customTheme;
  String? _exitMessage;

  /// 语言切换即时生效：监听 i18n 并重建（builder 里的 I18nScope 由此更新）。
  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  AppContext get app => widget.app;

  @override
  void initState() {
    super.initState();
    // 读一次 held：保证锁对象与文件句柄在 AOT 下也被真实保留（单实例依赖它）。
    AppLogger.instance.info('app.instance.held', <String, Object?>{
      'held': widget.app.instanceLock.held,
    });
    _applyThemeMode();
    app.settings.addListener(_applyThemeMode);
    app.i18n.addListener(_onLanguageChanged);
    app.editor.addListener(_syncTitle);
    app.library.addListener(_syncTitle);
    _lifecycle = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onStateChange: _onLifecycleState,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTitle());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    app.settings.removeListener(_applyThemeMode);
    app.i18n.removeListener(_onLanguageChanged);
    app.editor.removeListener(_syncTitle);
    app.library.removeListener(_syncTitle);
    super.dispose();
  }

  void _applyThemeMode() {
    final AppSettings settings = app.settings.settings;
    ThemeMode next = ThemeMode.system;
    AppThemeData? custom;
    if (settings.themeMode.startsWith('custom:')) {
      final String id = settings.themeMode.substring('custom:'.length);
      for (final CustomTheme t in settings.customThemes) {
        if (t.id == id) {
          custom = AppThemeData.fromCustom(t);
          // 自定义主题自带明暗：走 light 槽位让 themeMode 保持稳定。
          next = ThemeMode.light;
          break;
        }
      }
    } else {
      next = switch (settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }
    if (mounted && (next != _themeMode || custom != _customTheme)) {
      setState(() {
        _themeMode = next;
        _customTheme = custom;
      });
    }
  }

  Future<void> _syncTitle() async {
    final EditorController editor = app.editor;
    final String? bookTitle = editor.book?.title;
    // 索引提交会先通知 library，再由结构操作 finally 重绑 editor.volume。
    // 展示始终按实际目录归属取号，不能在该窗口使用旧路径绑定。
    final currentVolume = editor.chapter == null
        ? null
        : editor.book?.volumeOfChapter(editor.chapter!.id);
    final String? chapterTitle = editor.chapter == null || currentVolume == null
        ? null
        : displayChapterTitle(
            editor.book!,
            currentVolume,
            editor.chapter!,
            rawTitle: editor.title.text,
          );
    final String title = (bookTitle != null && chapterTitle != null)
        ? '不白写作 — $bookTitle · $chapterTitle'
        : '不白写作';
    await app.platform.setWindowTitle(title);
  }

  Future<void> _onLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // 隐藏/暂停不是作者提交候选：普通保存会等待在途快照并保留 composing。
      // 原生退出另走显式的草稿/组词门禁，不在这里强制截断输入法。
      await app.editor.saveNow();
      await app.settings.flush();
    }
  }

  /// 关闭窗口：先强制保存，失败时给「重试 / 导出后退出 / 取消」。
  Future<AppExitResponse> _onExitRequested() async {
    AppLogger.instance.info('app.exit.requested');
    if (app.exporter.busy ||
        app.editor.isComposing ||
        !await app.uiGuards.flush()) {
      AppLogger.instance.warn('app.exit.cancelled.busy-or-draft');
      if (mounted) {
        setState(
          () => _exitMessage = app.exporter.busy
              ? '正在导出，请完成后再关闭。'
              : '草稿尚未完成保存或仍在输入法组词，已取消关闭。',
        );
      }
      return AppExitResponse.cancel;
    }
    while (true) {
      final bool ok = await app.editor.flushForExit();
      if (ok) break;
      final String? choice = await _askSaveFailure();
      if (choice == 'retry') continue;
      if (choice == 'export') {
        final bool exported = await app.editor.exportEmergencyDraft() != null;
        if (exported) break;
        continue;
      }
      AppLogger.instance.warn('app.exit.cancelled');
      return AppExitResponse.cancel;
    }
    await _rememberGeometry();
    await app.settings.flush();
    AppLogger.instance.info('app.exit.accepted');
    return AppExitResponse.exit;
  }

  Future<String?> _askSaveFailure() {
    final BuildContext? context = _navigatorKey.currentContext;
    if (context == null) return Future<String?>.value('export');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => ContentDialog(
        title: const Text('这一章还没保存成功'),
        content: Text(app.editor.errorMessage ?? '写磁盘失败了。'),
        actions: <Widget>[
          Button(
            onPressed: () => Navigator.of(context).pop('retry'),
            child: const Text('重试'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop('export'),
            child: const Text('导出到文档后退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('取消退出'),
          ),
        ],
      ),
    );
  }

  Future<void> _rememberGeometry() async {
    try {
      final WindowGeometry geometry = await app.platform.currentGeometry();
      app.settings.rememberGeometry(
        geometry.x,
        geometry.y,
        geometry.width,
        geometry.height,
        maximized: geometry.maximized,
      );
    } catch (error) {
      AppLogger.instance.warn('window.geometry.save.failed', '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeData? custom = _customTheme;
    return FluentApp(
      navigatorKey: _navigatorKey,
      title: '不白写作',
      // 自定义主题激活时占用 light/dark 两个槽位（themeMode 固定 light），
      // 保证 AnimatedFluentTheme 之下的路由与实时 scope 读到同一份数据。
      theme: custom != null
          ? buildFluentTheme(custom)
          : buildFluentTheme(AppThemeData.light),
      darkTheme: custom != null
          ? buildFluentTheme(custom)
          : buildFluentTheme(AppThemeData.dark),
      themeMode: _themeMode,
      // 语言包切换即时生效：locale 跟随当前语言包（zh-CN → zh，en → en）。
      locale: localeOfLanguageCode(app.i18n.currentCode),
      localizationsDelegates: FluentLocalizations.localizationsDelegates,
      supportedLocales: FluentLocalizations.supportedLocales,
      builder: (context, child) {
        // 实时主题 scope：builder 插入的 widget 是 Navigator 的祖先，
        // 普通 InheritedWidget 不会被 InheritedTheme.capture 冻结，
        // 菜单/气泡等 overlay 路由内容由此拿到切换后的主题。
        final AppThemeData effective =
            custom ??
            AppThemeData.builtinFor(
              _themeMode == ThemeMode.light
                  ? Brightness.light
                  : _themeMode == ThemeMode.dark
                  ? Brightness.dark
                  : MediaQuery.platformBrightnessOf(context),
            );
        return LiveFluentThemeScope(
          themeData: buildFluentTheme(effective),
          appTheme: effective,
          // i18n scope：Navigator 与 overlay 路由（菜单/浮窗）都从这取词，
          // 与 LiveFluentThemeScope 同层保证语言切换后弹层也换词。
          child: I18nScope(
            controller: app.i18n,
            languageCode: app.i18n.currentCode,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ?child,
                if (_exitMessage != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: InfoBar(
                          title: Text(_exitMessage!),
                          severity: InfoBarSeverity.warning,
                          action: Button(
                            onPressed: () =>
                                setState(() => _exitMessage = null),
                            child: const Text('知道了'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      home:
          widget.home ??
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
          ),
    );
  }
}
