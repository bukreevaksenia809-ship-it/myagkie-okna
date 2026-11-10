// Эталон заказчика для режима «Шаг + остаток»:
//   • низ  — старт в левом углу, первый промежуток — остаток, слева → направо;
//   • верх — старт в левом углу, первый промежуток — остаток, слева → направо;
//   • лево — старт в нижнем углу, первый промежуток — остаток, снизу → вверх;
//   • право — старт в нижнем углу, первый промежуток — остаток, снизу → вверх.
// Последняя точка попадает ровно в дальний угол: usable = остаток + k × шаг.
//
// Окантовка здесь нулевая, чтобы линия люверсов совпала с кромкой изделия и
// числа совпадали с эталоном заказчика (0, 200, 500, …). Для реального окна
// линия смещена к середине окантовки, но алгоритм тот же.
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

WindowParams _window({
  double bottom = 1700,
  double top = 1700,
  double left = 2900,
  double right = 2900,
  double step = 300,
  bool even = false,
}) => WindowParams(
  bottomWidth: bottom,
  topWidth: top,
  leftHeight: left,
  rightHeight: right,
  rollBottom: 0,
  rollRight: 0,
  rollTop: 0,
  rollLeft: 0,
  weldOverlapMm: 0,
  eyeletStep: step,
  eyeletEvenSpacing: even,
  pvcHeightAllowanceEnabled: false,
);

List<double> _xsAt(WindowSpec spec, double y) => spec.layers.eyelets
    .where((eyelet) => (eyelet.center.dy - y).abs() < 0.5)
    .map((eyelet) => eyelet.center.dx)
    .toList()
  ..sort();

List<double> _ysAt(WindowSpec spec, double x) => spec.layers.eyelets
    .where((eyelet) => (eyelet.center.dx - x).abs() < 0.5)
    .map((eyelet) => eyelet.center.dy)
    .toList()
  ..sort();

List<double> _gaps(List<double> values) => [
  for (var i = 1; i < values.length; i++) values[i] - values[i - 1],
];

void main() {
  const crossEdge = [0.0, 200.0, 500.0, 800.0, 1100.0, 1400.0, 1700.0];
  const sideEdge = [
    0.0,
    200.0,
    500.0,
    800.0,
    1100.0,
    1400.0,
    1700.0,
    2000.0,
    2300.0,
    2600.0,
    2900.0,
  ];

  test('низ и верх 1700: 0, 200, 500, …, 1700 — остаток в начале', () {
    final spec = WindowSpec.of(_window());
    expect(_xsAt(spec, 0), crossEdge);
    expect(_xsAt(spec, 2900), crossEdge);
  });

  test('лево и право 2900: 0, 200, 500, …, 2900 — остаток в начале', () {
    final spec = WindowSpec.of(_window());
    expect(_ysAt(spec, 0), sideEdge);
    expect(_ysAt(spec, 1700), sideEdge);
  });

  test('верх и низ одинаковой ширины дают одинаковые промежутки', () {
    final spec = WindowSpec.of(_window());
    final bottom = _gaps(_xsAt(spec, 0));
    final top = _gaps(_xsAt(spec, 2900));
    expect(top, hasLength(bottom.length));
    for (var i = 0; i < bottom.length; i++) {
      expect(top[i], closeTo(bottom[i], 1e-9));
    }
    expect(bottom.first, closeTo(200, 1e-9));
    expect(bottom.skip(1), everyElement(closeTo(300, 1e-9)));
  });

  test('шаг 250 при ширине 1000 делится без остатка', () {
    final spec = WindowSpec.of(_window(bottom: 1000, step: 250));
    expect(_xsAt(spec, 0), [0.0, 250.0, 500.0, 750.0, 1000.0]);
    expect(WindowSpec.of(_window(bottom: 1000, step: 250)).eyeletStepLabel,
        contains('250'));
  });

  test('шаг больше стороны — ровно две точки в углах', () {
    final spec = WindowSpec.of(
      _window(bottom: 500, top: 500, left: 500, right: 500, step: 1000),
    );
    expect(_xsAt(spec, 0), [0.0, 500.0]);
    expect(_xsAt(spec, 500), [0.0, 500.0]);
  });

  test('подпись фактического шага: «300, остаток 200»', () {
    final spec = WindowSpec.of(_window());
    final label = spec.eyeletStepLabel;
    expect(label, contains('300'));
    expect(label, contains('200'));
    expect(label.toLowerCase(), contains('остаток'));
  });

  test('режим «равномерно» не изменился: факт не больше заданного', () {
    final spec = WindowSpec.of(_window(even: true));
    final bottom = _gaps(_xsAt(spec, 0));
    expect(bottom, hasLength(6));
    for (final gap in bottom) {
      expect(gap, greaterThan(0));
      expect(gap, lessThanOrEqualTo(300 + 1e-9));
    }
    expect(bottom.every((gap) => (gap - bottom.first).abs() < 1e-9), isTrue);
  });

  test('ручная расстановка не меняется режимом', () {
    final manual = _window().copyWith(
      manualEyeletSides: const [EdgeSide.bottom],
      eyeletPositions: const [
        EyeletPosition(
          side: EdgeSide.bottom,
          fraction: 0.1,
          kind: MarkerKind.roundEyelet,
        ),
        EyeletPosition(
          side: EdgeSide.bottom,
          fraction: 0.9,
          kind: MarkerKind.roundEyelet,
        ),
      ],
    );
    final spec = WindowSpec.of(manual);
    // Ручные точки стоят ровно там, где их поставили (доля 0,1 и 0,9 ребра).
    final xs = spec.layers.eyelets
        .where((eyelet) => eyelet.side == WindowSide.bottom)
        .map((eyelet) => eyelet.center.dx)
        .toList()
      ..sort();
    expect(xs, hasLength(2));
    expect(xs.first, closeTo(170, 1e-6));
    expect(xs.last, closeTo(1530, 1e-6));
  });
}
