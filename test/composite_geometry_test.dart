import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/fastener_spans.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

/// Геометрия составного окна: второй сегмент режется ВНУТРИ габаритов,
/// общий размер окна не меняется; прямой и диагональный шов, площади,
/// окантовка по материалам, заготовки частей.
void main() {
  WindowParams composite({
    CompositeSpec spec = const CompositeSpec(),
    double width = 1500,
    double height = 2000,
  }) =>
      WindowParams(
        windowType: WindowType.composite,
        bottomWidth: width,
        topWidth: width,
        leftHeight: height,
        rightHeight: height,
        composite: spec,
      );

  test('прямой шов справа: второй сегмент внутри, размер окна тот же', () {
    final params = composite(
      spec: const CompositeSpec(
        side: EdgeSide.right,
        depth: 500,
        material: FilmMaterial.screen,
      ),
    );
    final spec = WindowSpec.of(params);
    final layout = spec.compositeLayout!;
    expect(layout.diagonal, isFalse);
    // Полоса справа: 500 мм глубиной на всю высоту 2000.
    expect(layout.secondAreaMm2, closeTo(500 * 2000, 1e-6));
    // Основное полотно: (1500 − 500) × 2000.
    expect(layout.mainAreaMm2, closeTo(1000 * 2000, 1e-6));
    // Общая площадь — ровно введённые 1500 × 2000.
    expect(layout.totalAreaMm2, closeTo(1500 * 2000, 1e-6));
    expect(spec.productAreaM2, closeTo(3.0, 1e-9));
    expect(layout.seamLength, closeTo(2000, 1e-6));
    // Контур остался четырёхугольником введённого размера.
    expect(layout.outline.length, 4);
    expect(spec.geometry.areaM2, closeTo(3.0, 1e-9));
  });

  test('окантовка: ПВХ по свободным кромкам, скрин — без тента', () {
    final screenSpec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(side: EdgeSide.right, depth: 500),
      ),
    );
    final screenTotal =
        screenSpec.edgeConsumption.values.fold(0.0, (a, b) => a + b);
    // Второй сегмент — скрин: окантовки нет, только свободные кромки ПВХ
    // (низ 1000 + верх 1000 + лево 2000); шов не окантовывается.
    expect(screenTotal, closeTo(4000, 1e-6));

    final pvcSpec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.right,
          depth: 500,
          material: FilmMaterial.clearPvc,
        ),
      ),
    );
    final pvcTotal =
        pvcSpec.edgeConsumption.values.fold(0.0, (a, b) => a + b);
    // Обе части ПВХ: весь периметр 2 × (1500 + 2000) = 7000, шов внутри.
    expect(pvcTotal, closeTo(7000, 1e-6));
  });

  test('вынос больше полотна подрезается, размер не растёт', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(side: EdgeSide.right, depth: 5000),
      ),
    );
    final layout = spec.compositeLayout!;
    expect(layout.clamped, isTrue);
    expect(layout.seamLength, closeTo(2000, 1e-6));
    expect(
      layout.totalAreaMm2,
      closeTo(1500 * 2000, 1e-3),
      reason: 'общий размер окна не меняется никогда',
    );
  });

  test('косое ПВХ: второй сегмент тоже косой и повторяет кромку', () {
    const params = WindowParams(
      windowType: WindowType.composite,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2500,
      composite: CompositeSpec(side: EdgeSide.right, depth: 500),
    );
    final spec = WindowSpec.of(params);
    final layout = spec.compositeLayout!;
    final second = layout.secondPolygon;
    // Правая кромка окна наклонена (2000 → 2500), значит и второй сегмент
    // имеет наклонные верх/низ — это не прямоугольник.
    final ys = second.map((point) => point.dy).toSet();
    expect(ys.length, greaterThan(1), reason: 'второй сегмент косой');
    // Полоса x от 1500 до 2000: высота там 2375…2500, средняя 2437,5.
    expect(layout.secondAreaMm2, closeTo(500 * 2437.5, 1e-3));
    // Сумма частей равна введённому габариту.
    expect(layout.totalAreaMm2, closeTo(spec.geometry.areaMm2, 1e-3));
  });

  test('диагональный шов снизу режет угол честным многоугольником', () {
    const width = 2000.0;
    const height = 2000.0;
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.bottom,
          depth: 400,
          seam: CompositeSeam.diagonal,
          seamOffset: 0.5,
          seamAngleDeg: 30,
        ),
        width: width,
        height: height,
      ),
    );
    final layout = spec.compositeLayout!;
    expect(layout.diagonal, isTrue);
    // Шов от середины низа к правой кромке: 1000 / cos30 = 1154,7 мм.
    expect(layout.seamLength, closeTo(1000 / 0.8660254037844386, 1e-6));
    final cut = 0.5 * 1000 * (1000 * 0.5773502691896257);
    expect(layout.secondAreaMm2, closeTo(cut, 1e-3));
    expect(layout.mainAreaMm2, closeTo(width * height - cut, 1e-3));
    // Общий размер окна не изменился.
    expect(spec.productAreaM2, closeTo(width * height / 1000000, 1e-9));
    expect(layout.mainPolygon.length, 5);
    expect(layout.secondPolygon.length, 3);
    expect(
      layout.totalAreaMm2,
      closeTo(polygonArea(layout.outline).abs(), 1e-3),
    );
  });

  test('заготовки: две детали, у каждой свой контур', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.bottom,
          depth: 400,
          material: FilmMaterial.screen,
        ),
      ),
    );
    expect(spec.layers.filmPolygons.length, 2);
    expect(spec.layers.partBlankRects.length, 2);
    expect(spec.layers.blankAreaMm2, greaterThan(0));
    for (final polygon in spec.layers.filmPolygons) {
      expect(polygon.length, greaterThanOrEqualTo(3));
      expect(polygonArea(polygon).abs(), greaterThan(0));
    }
    // Второй сегмент скрина кроится с подворотом: заготовка больше изделия.
    final second = spec.layers.filmPolygons[1];
    expect(
      polygonArea(second).abs(),
      greaterThan(spec.compositeSecondAreaM2 * 1000000),
    );
  });

  test('заготовки ПВХ: второй сегмент подрезан под окантовку', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.right,
          depth: 500,
          material: FilmMaterial.clearPvc,
        ),
      ),
    );
    final second = spec.layers.filmPolygons[1];
    expect(
      polygonArea(second).abs(),
      lessThan(spec.compositeSecondAreaM2 * 1000000),
    );
  });

  test('крепёж не задваивается и не стоит на шве', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.right,
          depth: 500,
          material: FilmMaterial.screen,
        ),
      ),
    );
    final layout = spec.compositeLayout!;
    final seam = layout.seamEnd - layout.seamStart;
    final length = seam.distance;
    final unit = seam / length;
    double distanceToSeam(Offset point) =>
        (unit.dx * (point.dy - layout.seamStart.dy) -
                unit.dy * (point.dx - layout.seamStart.dx))
            .abs();
    expect(spec.layers.eyelets, isNotEmpty);
    for (final eyelet in spec.layers.eyelets) {
      expect(
        distanceToSeam(eyelet.center),
        greaterThan(0.5),
        reason: 'на стыке двух полотен люверса нет',
      );
    }
  });

  test('разметка длин: цепочка идёт по всей стороне, включая скрин', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.right,
          depth: 500,
          material: FilmMaterial.screen,
        ),
      ),
    );
    final bottom = fastenerChainLabels(spec)
        .where((label) => label.side == WindowSide.bottom)
        .toList();
    expect(bottom, isNotEmpty);
    expect(bottom.first.cumulativeMm, closeTo(0, 1e-6));
    // Окно 1500 шириной: цепочка заканчивается на правом внешнем углу.
    expect(bottom.last.cumulativeMm, closeTo(1500, 1e-6));
    expect(bottom.length, greaterThan(4));
    // Низ — слева направо.
    for (var i = 1; i < bottom.length; i++) {
      expect(bottom[i].pointMm.dx, greaterThan(bottom[i - 1].pointMm.dx));
    }
  });

  test('смета: материал скрина отдельно, без двойного счёта', () {
    final spec = WindowSpec.of(
      composite(
        spec: const CompositeSpec(
          side: EdgeSide.bottom,
          depth: 400,
          material: FilmMaterial.screen,
        ),
      ),
    );
    final areas = spec.compositeFilmPartAreasM2;
    expect(areas.length, 2);
    expect(areas[0] + areas[1], closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
  });
}
