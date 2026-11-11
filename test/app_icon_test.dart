import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Uint8List largestIcon(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final count = data.getUint16(4, Endian.little);
  for (var index = 0; index < count; index++) {
    final entry = 6 + index * 16;
    if (bytes[entry] == 0) {
      final length = data.getUint32(entry + 8, Endian.little);
      final offset = data.getUint32(entry + 12, Endian.little);
      return Uint8List.sublistView(bytes, offset, offset + length);
    }
  }
  throw StateError('The Windows icon must include a 256px frame.');
}

Future<ByteData> decode(WidgetTester tester, Uint8List bytes) async =>
    (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 256);
          expect(frame.image.height, 256);
          return await frame.image.toByteData();
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }))!;

void main() {
  testWidgets('Windows图标保留各DPI尺寸并使用用户SVG的黑白标识', (tester) async {
    final bytes = File('windows/runner/resources/app_icon.ico')
        .readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint16(2, Endian.little), 1);
    final count = data.getUint16(4, Endian.little);
    final sizes = <int>[];
    for (var index = 0; index < count; index++) {
      final entry = 6 + index * 16;
      sizes.add(bytes[entry] == 0 ? 256 : bytes[entry]);
    }
    expect(sizes, [16, 24, 32, 48, 64, 128, 256]);
    final rgba = await decode(tester, largestIcon(bytes));
    expect(rgba.getUint8(3), 0, reason: '圆角外保留透明背景');
    var dark = 0, white = 0, chromatic = 0;
    for (var i = 0; i < rgba.lengthInBytes; i += 4) {
      if (rgba.getUint8(i + 3) < 128) continue;
      final r = rgba.getUint8(i);
      final g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      if (r < 80 && g < 80 && b < 80) dark++;
      if (r > 230 && g > 230 && b > 230) white++;
      final maximum = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minimum = [r, g, b].reduce((a, b) => a < b ? a : b);
      if (maximum - minimum > 4) chromatic++;
    }
    expect(dark, greaterThan(10000));
    expect(white, greaterThan(15000));
    expect(chromatic, lessThan(100), reason: '替换旧棕红折页图标，保留SVG灰阶');
  });

  testWidgets('保留SVG源稿且PNG预览与ICO最大帧完全一致', (tester) async {
    final source = File('assets/branding/app_icon.svg');
    expect(source.existsSync(), isTrue, reason: '源稿应保存在仓库内以便重建');
    final svg = source.readAsStringSync();
    expect(svg, contains('viewBox="0 0 840 855"'));
    expect(svg, contains('id="bu-shape"'));
    expect(svg, contains('id="bai-shape"'));
    expect(svg, contains('feTurbulence'));
    final preview = File('assets/branding/app_icon.png');
    expect(preview.existsSync(), isTrue);
    final actual = await decode(
      tester,
      largestIcon(
        File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      ),
    );
    final expected = await decode(tester, preview.readAsBytesSync());
    expect(actual.buffer.asUint8List(), expected.buffer.asUint8List());
  });
}
