import 'package:fluent_ui/fluent_ui.dart';

/// The resting surface has no stroke. Keyboard focus remains a separate layer.
const borderlessMenuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4)),
  side: BorderSide.none,
);

ButtonStyle borderlessRowStyle({Color? background, Color? foreground}) =>
    ButtonStyle(
      shape: const WidgetStatePropertyAll(borderlessMenuShape),
      backgroundColor: background == null
          ? null
          : WidgetStatePropertyAll(background),
      foregroundColor: foreground == null
          ? null
          : WidgetStatePropertyAll(foreground),
    );
