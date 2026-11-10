import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

const _window = WindowParams(
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

PriceList _prices({bool enabled = true, double centimeters = 120}) =>
    const PriceList.defaults().copyWith(
      tentConsumptionEnabled: enabled,
      tentConsumptionCm: centimeters,
    );

EstimateLine? _tentLine(Estimate estimate) {
  for (final line in estimate.lines) {
    if (line.title == 'Расход тента') return line;
  }
  return null;
}

void main() {
  test('по умолчанию расход тента в смету не входит', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [_window, _window, _window]),
      const PriceList.defaults(),
    );
    expect(_tentLine(estimate), isNull);
  });

  test('120 см × 3 окна = 3,6 м', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [_window, _window, _window]),
      _prices(),
    );
    final line = _tentLine(estimate);
    expect(line, isNotNull);
    expect(line!.quantity, closeTo(3.6, 1e-9));
    expect(line.unit, 'м');
    expect(line.group, EstimateGroup.materials);
    expect(line.note, contains('1,2 м'));
    expect(line.note, contains('3 окна'));
    // Цена — из прайса тента 100 мм (стандартная ширина заказа).
    expect(line.unitPrice, _prices().edgePerMeterForWidth(100));
  });

  test('150 см × 3 окна = 4,5 м', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [_window, _window, _window]),
      _prices(centimeters: 150),
    );
    expect(_tentLine(estimate)!.quantity, closeTo(4.5, 1e-9));
  });

  test('одно окно — 1,2 м, пять окон — 6 м', () {
    expect(
      _tentLine(
        Estimate.of(const OrderProject(windows: [_window]), _prices()),
      )!.quantity,
      closeTo(1.2, 1e-9),
    );
    expect(
      _tentLine(
        Estimate.of(
          const OrderProject(
            windows: [_window, _window, _window, _window, _window],
          ),
          _prices(),
        ),
      )!.quantity,
      closeTo(6, 1e-9),
    );
  });

  test('Т-окно и составное окно считаются как одно окно', () {
    final tEstimate = Estimate.of(
      const OrderProject(windows: [_tWindow, _tWindow]),
      _prices(),
    );
    expect(_tentLine(tEstimate)!.quantity, closeTo(2.4, 1e-9));
    final composite = Estimate.of(
      const OrderProject(windows: [_composite]),
      _prices(),
    );
    expect(_tentLine(composite)!.quantity, closeTo(1.2, 1e-9));
  });

  test('выключение убирает строку и возвращает итог', () {
    const project = OrderProject(windows: [_window, _window, _window]);
    final on = Estimate.of(project, _prices());
    final off = Estimate.of(project, _prices(enabled: false));
    expect(_tentLine(on), isNotNull);
    expect(_tentLine(off), isNull);
    expect(off.total, lessThan(on.total));
  });

  test('настройка сохраняется в JSON прайса', () {
    final prices = _prices(centimeters: 150);
    final restored = PriceList.fromJson(prices.toJson());
    expect(restored.tentConsumptionEnabled, isTrue);
    expect(restored.tentConsumptionCm, 150);
  });
}
