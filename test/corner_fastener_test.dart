import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  test('подъёмное окно: нижние углы под скобу, верхние — круглые', () {
    const params = WindowParams(
      windowType: WindowType.lifting,
      fastenerType: FastenerType.frenchLocks,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
    );
    final spec = WindowSpec.of(params);
    final fastenerCorners = spec.layers.autoFastenerEyelets
        .where((eyelet) => eyelet.isCorner)
        .toList();
    expect(fastenerCorners, isNotEmpty);
    expect(
      fastenerCorners.every((eyelet) => eyelet.side == WindowSide.bottom),
      isTrue,
    );
    final topCorners = spec.layers.eyelets
        .where((eyelet) => eyelet.isCorner && eyelet.side == WindowSide.top)
        .toList();
    expect(topCorners, isNotEmpty);
  });
}
