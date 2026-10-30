import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

WindowParams _window() => const WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  rollBottom: 100,
  rollTop: 100,
  rollLeft: 100,
  rollRight: 100,
);

void main() {
  test('отступ крепежа по умолчанию — середина полосы, 25 мм', () {
    final params = _window();
    expect(params.fastenerBandFor(EdgeSide.bottom), 50);
    expect(params.fastenerOffsetMmFor(EdgeSide.bottom), 25);
  });

  test('отступ хранится в миллиметрах и двигает линию люверсов', () {
    final params = _window().copyWith(
      fastenerOffsetsMm: const {EdgeSide.bottom: 10},
    );
    final spec = WindowSpec.of(params);
    final bottomYs = spec.layers.eyeletLine
        .where((point) => point.dy < 100)
        .map((point) => point.dy);
    // Внутренний край полосы — 50 мм от наружного; отступ 10 мм от
    // внутреннего края оставляет 40 мм от наружного.
    expect(bottomYs.reduce((a, b) => a < b ? a : b), closeTo(40, 0.01));
  });

  test('JSON сохраняет миллиметры и читает старую долю полосы', () {
    final params = _window().copyWith(
      fastenerOffsetsMm: const {EdgeSide.left: 12.5},
    );
    final restored = windowFromJson(windowToJson(params));
    expect(restored.fastenerOffsetMmFor(EdgeSide.left), 12.5);

    final legacy = windowToJson(_window());
    legacy.remove('fastenerOffsetsMm');
    legacy['fastenerOffsets'] = {'left': 0.2};
    final old = windowFromJson(legacy);
    expect(old.fastenerOffsetMmFor(EdgeSide.left), closeTo(10, 0.001));
  });
}
