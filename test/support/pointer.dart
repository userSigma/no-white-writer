import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Moves a desktop pointer over an action before clicking it, as a user would.
/// In particular, row controls may intentionally ignore input until hovered.
Future<void> tapWithMouse(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(target));
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 150));
  await mouse.down(tester.getCenter(target));
  await mouse.up();
  await mouse.removePointer();
}
