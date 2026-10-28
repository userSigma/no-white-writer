import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'theme/tokens.dart';
import 'menu_surface.dart';

class MenuAction {
  const MenuAction(this.id, this.label, {this.enabled = true});
  final String id;
  final String label;
  final bool enabled;
}

/// 真正的指针锚定菜单；透明模态屏障仍拦截背景，边界内可滚动。
Future<String?> showContextMenu(
  BuildContext context,
  Offset position,
  List<MenuAction> actions,
) {
  if (actions.isEmpty) return Future<String?>.value();
  // 不做 InheritedTheme.capture：应用只有 app 级唯一 FluentTheme（无嵌套），
  // 路由内容经 Overlay 直接读取实时主题，主题切换时打开中的菜单立即重配色。
  return Navigator.of(context, rootNavigator: true).push<String>(
    _ContextRoute(position: position, actions: actions),
  );
}

class _ContextRoute extends PopupRoute<String> {
  _ContextRoute({required this.position, required this.actions});
  final Offset position;
  final List<MenuAction> actions;
  @override
  Color get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '关闭菜单';
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
    LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 16).clamp(1.0, 220.0);
        final height = (actions.length * 38.0 + 12).clamp(
          1.0,
          box.maxHeight - 16,
        );
        final x = position.dx.clamp(
          8.0,
          (box.maxWidth - width - 8).clamp(8.0, double.infinity),
        );
        final y = position.dy.clamp(
          8.0,
          (box.maxHeight - height - 8).clamp(8.0, double.infinity),
        );
        return Stack(
          children: [
            Positioned(
              left: x,
              top: y,
              width: width,
              height: height,
              child: _Menu(actions: actions),
            ),
          ],
        );
      },
    );
}

class _Menu extends StatefulWidget {
  const _Menu({required this.actions});
  final List<MenuAction> actions;
  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  late int selected;
  final _scroll = ScrollController();
  bool _keyboard = true;

  @override
  void initState() {
    super.initState();
    selected = widget.actions.indexWhere((action) => action.enabled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _step(int delta) {
    if (selected < 0) return;
    setState(() {
      _keyboard = true;
      for (int i = 0; i < widget.actions.length; i++) {
        selected = (selected + delta) % widget.actions.length;
        if (widget.actions[selected].enabled) break;
      }
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (selected * 38.0 - (_scroll.position.viewportDimension - 38) / 2).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bg = theme.menuColor, fg = bodyTextColor(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          final backwards =
              event.logicalKey == LogicalKeyboardKey.arrowUp ||
              (event.logicalKey == LogicalKeyboardKey.tab &&
                  HardwareKeyboard.instance.isShiftPressed);
          _step(backwards ? -1 : 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (selected >= 0 && widget.actions[selected].enabled) {
            Navigator.pop(context, widget.actions[selected].id);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        namesRoute: true,
        label: '上下文菜单',
        child: Container(
          key: const ValueKey('context-menu'),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ListView(
            controller: _scroll,
            itemExtent: 38,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (int i = 0; i < widget.actions.length; i++)
                SizedBox(
                  height: 38,
                  child: MouseRegion(
                    onEnter: (_) {
                      if (widget.actions[i].enabled) {
                        setState(() {
                          selected = i;
                          _keyboard = false;
                        });
                      }
                    },
                    child: FocusBorder(
                      focused: _keyboard && i == selected,
                      child: Button(
                        style: borderlessRowStyle(
                          background: i == selected
                              ? theme.resources.subtleFillColorSecondary
                              : Colors.transparent,
                          foreground: widget.actions[i].enabled
                              ? fg
                              : theme.resources.textFillColorDisabled,
                        ),
                        onPressed: widget.actions[i].enabled
                            ? () => Navigator.pop(context, widget.actions[i].id)
                            : null,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(widget.actions[i].label),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
