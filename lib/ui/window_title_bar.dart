import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../core/platform/platform_services.dart';
import 'theme/tokens.dart';

const double windowTitleBarHeight = 36;
const double _buttonWidth = 46;

/// Keep one set of window buttons above Navigator's modal barriers. Page-local
/// bars reserve that space, so dialogs never make the native window unclosable.
class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.platform, required this.child});
  final PlatformServices platform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!platform.supportsCustomTitleBar) return child;
    return _HostedWindowControls(
      child: Overlay.wrap(
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            ValueListenableBuilder<DesktopWindowState>(
              valueListenable: platform.windowState,
              builder: (context, state, _) => state.fullScreen
                  ? const SizedBox.shrink()
                  : Positioned(
                      top: 0,
                      right: 0,
                      child: WindowControls(platform: platform),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostedWindowControls extends InheritedWidget {
  const _HostedWindowControls({required super.child});
  @override
  bool updateShouldNotify(_HostedWindowControls oldWidget) => false;
}

/// Page navigation/actions are siblings of, never descendants of, the drag area.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    required this.platform,
    required this.leading,
    this.actions,
    this.draggableLeading = false,
  });
  final PlatformServices platform;
  final Widget leading;
  final Widget? actions;
  final bool draggableLeading;

  Widget _drag(Widget child, {Key? key}) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onPanStart: platform.supportsCustomTitleBar
        ? (_) => unawaited(platform.startWindowDrag())
        : null,
    onDoubleTap: platform.supportsCustomTitleBar
        ? () => unawaited(platform.toggleWindowMaximized())
        : null,
    child: child,
  );

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<DesktopWindowState>(
    valueListenable: platform.windowState,
    builder: (context, state, _) {
      if (platform.supportsCustomTitleBar && state.fullScreen) {
        return const SizedBox.shrink();
      }
      final hosted =
          context.dependOnInheritedWidgetOfExactType<_HostedWindowControls>() !=
          null;
      return Container(
        key: const ValueKey('window-title-bar'),
        height: windowTitleBarHeight,
        decoration: BoxDecoration(
          color: paperOrInk(context),
          border: Border(bottom: BorderSide(color: hairlineColor(context))),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: draggableLeading ? _drag(leading) : leading,
            ),
            Expanded(
              child: _drag(
                const SizedBox.expand(),
                key: const ValueKey('window-drag-area'),
              ),
            ),
            ?actions,
            if (actions != null) const SizedBox(width: 12),
            if (platform.supportsCustomTitleBar)
              if (hosted)
                const SizedBox(width: _buttonWidth * 3)
              else
                WindowControls(platform: platform),
          ],
        ),
      );
    },
  );
}

class WindowControls extends StatelessWidget {
  const WindowControls({super.key, required this.platform});
  final PlatformServices platform;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DesktopWindowState>(
        valueListenable: platform.windowState,
        builder: (context, state, _) => DecoratedBox(
          // The hosted controls paint above the page/Navigator. Draw the rule
          // in the foreground so opaque normal, hover and pressed fills cannot
          // erase the final 138 logical pixels of the caption divider.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: hairlineColor(context))),
          ),
          child: ColoredBox(
            color: paperOrInk(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(
                  context,
                  'minimize',
                  '最小化',
                  FluentIcons.chrome_minimize,
                  platform.minimizeWindow,
                ),
                _button(
                  context,
                  'maximize',
                  state.maximized ? '还原' : '最大化',
                  state.maximized
                      ? FluentIcons.chrome_restore
                      : WindowsIcons.chrome_maximize,
                  platform.toggleWindowMaximized,
                ),
                _button(
                  context,
                  'close',
                  '关闭窗口',
                  FluentIcons.chrome_close,
                  platform.requestWindowClose,
                  danger: true,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _button(
    BuildContext context,
    String id,
    String label,
    IconData icon,
    Future<void> Function() action, {
    bool danger = false,
  }) => Tooltip(
    message: label,
    child: SizedBox(
      width: _buttonWidth,
      height: windowTitleBarHeight,
      child: Semantics(
        label: label,
        button: true,
        child: Button(
          key: ValueKey('window-$id'),
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.isPressed) {
                return danger
                    ? const Color(0xFFC42B1C)
                    : bodyTextColor(context).withValues(alpha: .12);
              }
              if (states.isHovered) {
                return danger
                    ? const Color(0xFFE81123)
                    : bodyTextColor(context).withValues(alpha: .07);
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => danger && (states.isHovered || states.isPressed)
                  ? Colors.white
                  : bodyTextColor(context),
            ),
          ),
          onPressed: () => unawaited(action()),
          child: Icon(icon, size: 10),
        ),
      ),
    ),
  );
}

/// Vector version of the application's folded-page icon; no extra asset bundle.
class WindowBrand extends StatelessWidget {
  const WindowBrand({super.key, this.title = '不白写作'});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('window-brand'),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CustomPaint(size: Size(22, 22), painter: _BrandPainter()),
        const SizedBox(width: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: bodyTextColor(context),
          ),
        ),
      ],
    ),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 256, size.height / 256);
    final paint = Paint()..color = const Color(0xFF8C3A2B);
    canvas.drawRRect(
      RRect.fromLTRBR(8, 8, 248, 248, const Radius.circular(48)),
      paint,
    );
    paint.color = const Color(0xFFFFFCF5);
    canvas.drawRRect(
      RRect.fromLTRBR(58, 42, 198, 214, const Radius.circular(12)),
      paint,
    );
    paint.color = const Color(0xFF8C3A2B);
    canvas.drawPath(
      Path()
        ..moveTo(164, 42)
        ..lineTo(198, 76)
        ..lineTo(198, 42)
        ..close(),
      paint,
    );
    paint.color = const Color(0xFFB76B5C);
    canvas.drawPath(
      Path()
        ..moveTo(164, 42)
        ..lineTo(164, 76)
        ..lineTo(198, 76)
        ..close(),
      paint,
    );
    paint.color = const Color(0xFF8C3A2B);
    for (final line in [(108.0, 174.0), (137.0, 174.0), (166.0, 146.0)]) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          82,
          line.$1,
          line.$2,
          line.$1 + 10,
          const Radius.circular(5),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) => false;
}
