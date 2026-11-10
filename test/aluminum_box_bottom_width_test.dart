import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

const _rectangle = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _trapezoid = WindowParams(
  bottomWidth: 1500,
  topWidth: 1000,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _house = WindowParams(
  windowType: WindowType.house,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _tWindow = WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
  tEnabled: true,
  tWidth: 700,
  tHeight: 600,
);

const _composite = WindowParams(
  windowType: WindowType.composite,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

EstimateLine _line(WindowParams window) {
  final estimate = Estimate.of(
    OrderProject(windows: [window]),
    const PriceList.defaults().copyWith(aluminumBoxPerM: 500),
  );
  return estimate.lines.firstWhere(
    (line) => line.title == 'Алюминиевый бокс',
  );
}

void main() {
  test('прямоугольник 1500 × 2000: 1,5 м по нижней ширине', () {
    final line = _line(_rectangle);
    expect(line.quantity, closeTo(1.5, 1e-9));
    expect(line.unitPrice, 500);
    expect(line.amount, closeTo(750, 1e-9));
    expect(line.note, contains('по нижней ширине'));
  });

  test('трапеция: ни верх, ни бока не входят', () {
    expect(_line(_trapezoid).quantity, closeTo(1.5, 1e-9));
  });

  test('домик: считается нижняя ширина, а не периметр', () {
    expect(_line(_house).quantity, closeTo(1.5, 1e-9));
  });

  test('Т-окно: нижняя ширина основного полотна', () {
    expect(_line(_tWindow).quantity, closeTo(1.5, 1e-9));
  });

  test('составное окно: нижняя ширина основного полотна', () {
    expect(_line(_composite).quantity, closeTo(1.5, 1e-9));
  });

  test('заказ из нескольких окон суммирует низ каждого', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [_rectangle, _trapezoid, _composite]),
      const PriceList.defaults().copyWith(aluminumBoxPerM: 500),
    );
    final line = estimate.lines.firstWhere(
      (line) => line.title == 'Алюминиевый бокс',
    );
    expect(line.quantity, closeTo(4.5, 1e-9));
  });

  test('нулевая цена — позиция не начисляется', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [_rectangle]),
      const PriceList.defaults(),
    );
    expect(
      estimate.lines.where((line) => line.title == 'Алюминиевый бокс'),
      isEmpty,
    );
  });
}
