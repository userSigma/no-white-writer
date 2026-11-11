import 'package:fluent_ui/fluent_ui.dart';

/// Keeps row actions discoverable by mouse, keyboard and narrow-screen touch.
/// Focusable children remain mounted even while their pointer target is hidden.
class HoverActionRegion extends StatefulWidget {
  const HoverActionRegion({super.key, required this.child});

  final Widget child;

  @override
  State<HoverActionRegion> createState() => _HoverActionRegionState();
}

class _HoverActionRegionState extends State<HoverActionRegion> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: _ActionVisibility(
        visible:
            _hovered || _focused || MediaQuery.sizeOf(context).width < 1000,
        child: widget.child,
      ),
    ),
  );
}

class _ActionVisibility extends InheritedWidget {
  const _ActionVisibility({required this.visible, required super.child});

  final bool visible;

  @override
  bool updateShouldNotify(_ActionVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class HoverAction extends StatelessWidget {
  const HoverAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible =
        context
            .dependOnInheritedWidgetOfExactType<_ActionVisibility>()
            ?.visible ??
        true;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 100),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(ignoring: !visible, child: child),
    );
  }
}
