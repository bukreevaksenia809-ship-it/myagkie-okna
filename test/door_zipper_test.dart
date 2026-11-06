import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  test('дверь — две молнии, ширина и смещение', () {
    const params = WindowParams(bottomWidth: 2000, topWidth: 2000);
    final door = params.withDoor(
      filmWidth: 1900,
      enabled: true,
      widthMm: 800,
      offsetMm: 100,
    );
    expect(door.doorEnabled, isTrue);
    expect(door.zippers, hasLength(2));
    expect(door.doorWidthMm, 800);
    expect(door.doorOffsetMm, 100);
    expect(
      door.zippers[1].offsetMm - door.zippers[0].offsetMm,
      closeTo(800, 0.01),
    );
    final spec = WindowSpec.of(door);
    expect(spec.layers.zipperBands, hasLength(2));
    expect(spec.doorSummary, contains('800'));
    expect(spec.doorSummary, contains('+100'));
  });

  test('выключение двери убирает две молнии', () {
    const params = WindowParams();
    final door = params.withDoor(
      filmWidth: 1900,
      enabled: true,
      widthMm: 800,
      offsetMm: 0,
    );
    final off = door.withDoor(
      filmWidth: 1900,
      enabled: false,
      widthMm: door.doorWidthMm,
      offsetMm: door.doorOffsetMm,
    );
    expect(off.doorEnabled, isFalse);
    expect(off.zippers, isEmpty);
  });
}
