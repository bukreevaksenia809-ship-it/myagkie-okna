import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  const base = WindowParams(
    windowType: WindowType.lifting,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    liftStrapOffsets: [500, 1500],
  );

  test('вертикальный ремень выше ширины и идёт вниз', () {
    final straps = WindowSpec.of(base).layers.liftStraps;
    expect(straps, hasLength(2));
    for (final rect in straps) {
      expect(rect.width, liftStrapWidth);
      expect(rect.height, liftStrapLength);
    }
  });

  test('горизонтальный ремень лежит вдоль верхней кромки', () {
    final straps = WindowSpec.of(
      base.copyWith(liftStrapOrientation: LiftStrapOrientation.horizontal),
    ).layers.liftStraps;
    expect(straps, hasLength(2));
    for (final rect in straps) {
      expect(rect.width, liftStrapLength);
      expect(rect.height, liftStrapWidth);
    }
  });

  test('ориентация сохраняется в JSON', () {
    final restored = windowFromJson(
      windowToJson(
        base.copyWith(liftStrapOrientation: LiftStrapOrientation.horizontal),
      ),
    );
    expect(restored.liftStrapOrientation, LiftStrapOrientation.horizontal);
  });
}
