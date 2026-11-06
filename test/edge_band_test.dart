// Полоса окантовки на косом окне: ОДИН четырёхугольник на сторону.
//
// Раньше на наклонной стороне полоса могла собираться из сегментов: на
// каждом куске заново рисовались градиент, тканевая фактура и строчка, и на
// чертеже появлялся «частокол» коричневых полос. Тест фиксирует контракт:
// edgeBandQuads возвращает ровно по одному четырёхугольнику на сторону, а их
// длины и углы совпадают со сторонами изделия.
//
// Запуск: flutter test test/edge_band_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

/// Трапеция: низ 2000, верх 1000, высоты 1000/1000, окантовка 100.
const _trapezoid = WindowParams(
  projectName: 'Косое окно',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
);

/// Окно с разными высотами: левая 1000, правая 1400, ширины 1200/1200.
const _differentHeights = WindowParams(
  projectName: 'Косое окно',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
);

void _expectOneQuadPerSide(WindowParams params) {
  final spec = WindowSpec.of(params);
  final quads = edgeBandQuads(spec);
  final sides = spec.geometry.sideLengths;

  expect(quads, hasLength(4), reason: 'четыре стороны — четыре полосы');
  expect(
    {for (final quad in quads) quad.edgeIndex},
    {0, 1, 2, 3},
    reason: 'ни одна сторона не разбита на несколько сегментов',
  );

  for (final quad in quads) {
    expect(quad.points, hasLength(4));
    expect(
      quad.lengthMm,
      closeTo(sides[quad.edgeIndex], 1e-6),
      reason: 'длина стороны ${quad.edgeIndex}',
    );
    expect(quad.innerLengthMm, greaterThan(0));
    // Внутренняя линия параллельна наружной: на наклонной стороне полоса
    // не «заваливается» и не требует сегментов.
    expect(
      math.sin(quad.innerAngle - quad.angle).abs(),
      lessThan(1e-9),
      reason: 'внутренняя линия параллельна наружной, сторона ${quad.edgeIndex}',
    );
    // Угол равен углу фактической стороны изделия.
    final outer = spec.geometry.corners;
    final expected = math.atan2(
      outer[(quad.edgeIndex + 1) % outer.length].dy -
          outer[quad.edgeIndex].dy,
      outer[(quad.edgeIndex + 1) % outer.length].dx -
          outer[quad.edgeIndex].dx,
    );
    expect(
      math.sin(quad.angle - expected).abs(),
      lessThan(1e-9),
      reason: 'угол стороны ${quad.edgeIndex}',
    );
    expect(polygonArea(quad.points).abs(), greaterThan(1));
  }
}

void main() {
  test('трапеция: ровно 4 четырёхугольника, длины и углы по сторонам', () {
    _expectOneQuadPerSide(_trapezoid);
  });

  test('окно с разными высотами: ровно 4 четырёхугольника', () {
    _expectOneQuadPerSide(_differentHeights);
  });

  test('наклонная верхняя сторона остаётся одной полосой', () {
    final spec = WindowSpec.of(_differentHeights);
    final quads = edgeBandQuads(spec);
    // Верхняя сторона (индекс 2) наклонена: её угол не 0 и не ±π/2.
    final top = quads[2];
    expect(top.angle.abs(), greaterThan(0.05));
    expect(top.angle.abs(), lessThan(math.pi - 0.05));
    expect(
      top.lengthMm,
      closeTo(math.sqrt(1200 * 1200 + 400 * 400), 1e-6),
      reason: 'длина наклонной верхней стороны',
    );
    // На один четырёхугольник приходится вся полоса шириной 50 мм.
    expect(top.widthMm, closeTo(50, 1e-9));
    expect(quads.where((quad) => quad.edgeIndex == 2), hasLength(1));
  });

  test('ширины полос можно задать явно — по одной на сторону', () {
    final spec = WindowSpec.of(_trapezoid);
    final quads = edgeBandQuads(spec, widths: [40, 60, 80, 100]);
    expect(quads, hasLength(4));
    expect([for (final quad in quads) quad.widthMm], [40, 60, 80, 100]);
  });
}
