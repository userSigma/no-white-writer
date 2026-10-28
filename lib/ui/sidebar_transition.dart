import 'package:fluent_ui/fluent_ui.dart';

/// 侧栏过渡的唯一时钟：宽屏折叠、窄屏浮层都用这一组参数。
const Duration sidebarTransitionLength = Duration(milliseconds: 200);
const Curve sidebarTransitionCurve = Curves.easeInOutCubic;

/// 系统开启“减少动画”时立即到位，不播放中间帧。
Duration sidebarTransitionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : sidebarTransitionLength;

/// 用同一个动画值驱动多个布局属性（侧栏宽度、正文左缘、遮罩透明度），
/// 避免两个独立时钟造成的错位。每次 build 都给出新的 tween，
/// TweenAnimationBuilder 会从当前值 retarget，因此可以随时反向。
class SidebarValueBuilder extends StatelessWidget {
  const SidebarValueBuilder({
    super.key,
    required this.expanded,
    required this.builder,
  });

  final bool expanded;
  final Widget Function(BuildContext context, double value) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: expanded ? 1 : 0, end: expanded ? 1 : 0),
    duration: sidebarTransitionDuration(context),
    curve: sidebarTransitionCurve,
    builder: (BuildContext context, double value, Widget? _) =>
        builder(context, value),
  );
}
