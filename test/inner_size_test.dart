import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/inner_size.dart';

void main() {
  test('внутренний 1000×1000 + окантовка 100/200 → наружный', () {
    const params = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2000,
      rightHeight: 2000,
      rollBottom: 200,
      rollTop: 200,
      rollLeft: 100,
      rollRight: 100,
    );
    final outer = outerSizeFromInner(params, 1000, 1000);
    // Готовые полосы: низ/верх 100, лево/право 50.
    expect(outer.width, 1100);
    expect(outer.height, 1200);
  });

  _fourSides();

  test('обратный пересчёт даёт те же 1000×1000', () {
    const params = WindowParams(
      bottomWidth: 1100,
      topWidth: 1100,
      leftHeight: 1200,
      rightHeight: 1200,
      rollBottom: 200,
      rollTop: 200,
      rollLeft: 100,
      rollRight: 100,
    );
    final inner = innerSizeFromOuter(params);
    expect(inner.width, 1000);
    expect(inner.height, 1000);
  });
}

void _fourSides() {
  test('четыре внутренние стороны пересчитываются каждая отдельно', () {
    const params = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2000,
      rightHeight: 2000,
      rollBottom: 200,
      rollTop: 200,
      rollLeft: 100,
      rollRight: 200,
    );
    final outer = outerSidesFromInner(
      params,
      (
        topWidth: 1000,
        bottomWidth: 1200,
        leftHeight: 2000,
        rightHeight: 2200,
      ),
    );
    // Готовые полосы: лево 50, право 100, верх/низ 100.
    expect(outer.topWidth, 1150);
    expect(outer.bottomWidth, 1350);
    expect(outer.leftHeight, 2200);
    expect(outer.rightHeight, 2400);
  });

  test('скрин: внутренние стороны совпадают с наружными', () {
    const params = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 1500,
      topWidth: 1400,
      leftHeight: 2000,
      rightHeight: 2100,
    );
    final outer = outerSidesFromInner(
      params,
      (
        topWidth: 1400,
        bottomWidth: 1500,
        leftHeight: 2000,
        rightHeight: 2100,
      ),
    );
    expect(outer.topWidth, 1400);
    expect(outer.bottomWidth, 1500);
    expect(outer.leftHeight, 2000);
    expect(outer.rightHeight, 2100);
  });
}
