import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/inner_size.dart';

/// Трапеция с разными высотами: верх вводится как длина наклонной кромки.
///
/// Пример заказчика: низ 170 см, лево 290 см, право 252 см. Верх по горизонтали
/// тоже 170 см, но фактическая длина наклонной кромки — гипотенуза
/// √(1700² + 380²) ≈ 1741,95 мм.
void main() {
  const params = WindowParams(
    bottomWidth: 1700,
    topWidth: 1700,
    leftHeight: 2900,
    rightHeight: 2520,
  );

  test('верх 170 по горизонтали → наклонная кромка ≈ 1741,95 мм', () {
    final spec = WindowSpec.of(params);
    expect(spec.geometry.topEdgeLength, closeTo(1741.95, 0.1));
    // Горизонтальная проекция осталась прежней.
    expect(spec.geometry.topWidth, closeTo(1700, 0.01));
  });

  test('обратный пересчёт: длина кромки 1741,95 → проекция 1700', () {
    final spec = WindowSpec.of(params);
    final length = spec.geometry.topEdgeLength;
    final run = math.sqrt(length * length - 380 * 380);
    expect(run, closeTo(1700, 0.01));
  });

  test('прямоугольник: длина верхней кромки равна ширине', () {
    const rect = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2000,
      rightHeight: 2000,
    );
    expect(WindowSpec.of(rect).geometry.topEdgeLength, 1500);
    expect(rect.topEdgeSlantMm, 0);
  });

  test('перепад верха зависит от режима «Ровно»', () {
    const bottom = WindowParams(
      leftHeight: 2900,
      rightHeight: 2520,
      levelEdge: LevelEdge.bottom,
    );
    const top = WindowParams(
      leftHeight: 2900,
      rightHeight: 2520,
      levelEdge: LevelEdge.top,
    );
    const none = WindowParams(
      leftHeight: 2900,
      rightHeight: 2520,
      levelEdge: LevelEdge.none,
    );
    expect(bottom.topEdgeSlantMm, closeTo(-380, 1e-9));
    expect(top.topEdgeSlantMm, 0);
    expect(none.topEdgeSlantMm, closeTo(-190, 1e-9));
  });

  test('внутренний верх тоже считается по наклонной', () {
    const window = WindowParams(
      bottomWidth: 1700,
      topWidth: 1700,
      leftHeight: 2900,
      rightHeight: 2520,
      rollBottom: 100,
      rollTop: 100,
      rollLeft: 100,
      rollRight: 100,
    );
    final inner = innerSidesFromOuter(window);
    // Полосы окантовки по 50 мм с каждой стороны; проекция внутреннего верха
    // 1700 − 50 − 50 = 1600, перепад 380 → гипотенуза ≈ 1644,5.
    final expected = math.sqrt(1600 * 1600 + 380 * 380);
    expect(inner.topWidth, closeTo(expected, 0.05));
    // Обратный пересчёт возвращает наружную проекцию 1700.
    final outer = outerSidesFromInner(window, inner);
    expect(outer.topWidth, closeTo(1700, 0.05));
  });

  test('«Верх ровно»: наклонён низ, внутренний низ — по кромке', () {
    const window = WindowParams(
      bottomWidth: 1700,
      topWidth: 1700,
      leftHeight: 2900,
      rightHeight: 2520,
      levelEdge: LevelEdge.top,
      rollBottom: 100,
      rollTop: 100,
      rollLeft: 100,
      rollRight: 100,
    );
    expect(window.topEdgeSlantMm, 0);
    expect(window.bottomEdgeSlantMm, closeTo(380, 1e-9));
    final spec = WindowSpec.of(window);
    // Верх горизонтален, низ наклонён на 380.
    expect(spec.geometry.topEdgeLength, closeTo(1700, 0.01));
    final bottomSide = spec.geometry.sideLengths[0];
    expect(bottomSide, closeTo(math.sqrt(1700 * 1700 + 380 * 380), 0.1));

    final inner = innerSidesFromOuter(window);
    final innerBottomRun = 1700.0 - 50 - 50;
    expect(
      inner.bottomWidth,
      closeTo(math.sqrt(innerBottomRun * innerBottomRun + 380 * 380), 0.05),
    );
    // Верх горизонтален — внутренний верх равен проекции.
    expect(inner.topWidth, closeTo(1700 - 50 - 50, 0.05));
  });

  test('«Нет ровно»: наклонены и верх, и низ', () {
    const window = WindowParams(
      bottomWidth: 1700,
      topWidth: 1700,
      leftHeight: 2900,
      rightHeight: 2520,
      levelEdge: LevelEdge.none,
    );
    expect(window.topEdgeSlantMm, closeTo(-190, 1e-9));
    expect(window.bottomEdgeSlantMm, closeTo(190, 1e-9));
    final spec = WindowSpec.of(window);
    final expectedTop = math.sqrt(1700 * 1700 + 190 * 190);
    expect(spec.geometry.topEdgeLength, closeTo(expectedTop, 0.1));
    expect(spec.geometry.sideLengths[0], closeTo(expectedTop, 0.1));
  });
}
