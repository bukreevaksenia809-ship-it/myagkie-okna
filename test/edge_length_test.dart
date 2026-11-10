// Четыре размера трапеции: верх/низ, противоположный «Ровно», — это длина
// кромки (гипотенуза), а не горизонтальная проекция. Проверяем эталонные
// примеры заказчика, согласованность проекции/topOffset и внутренние размеры.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/inner_size.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

WindowParams _window({
  required double bottom,
  required double top,
  double left = 2000,
  double right = 1800,
  LevelEdge level = LevelEdge.bottom,
}) => WindowParams(
  bottomWidth: bottom,
  topWidth: top,
  leftHeight: left,
  rightHeight: right,
  levelEdge: level,
  pvcHeightAllowanceEnabled: false,
);

void main() {
  test('«Ровно низ» 800 × 2000/1800: верх 824,6 мм', () {
    final params = _window(bottom: 800, top: 800);
    expect(params.topEdgeSlantMm.abs(), closeTo(200, 1e-9));
    expect(params.topEdgeLengthMm, closeTo(math.sqrt(800 * 800 + 200 * 200), 1e-9));
    expect(params.topEdgeLengthMm, closeTo(824.621, 0.001));

    final geometry = WindowSpec.of(params).geometry;
    expect(geometry.topWidth, 800);
    expect(geometry.topOffset, 0);
    expect(geometry.topEdgeLength, closeTo(824.621, 0.001));
    expect(geometry.sideLengths[0], 800);
    expect(geometry.sideLengths[3], 2000);
    expect(geometry.sideLengths[1], 1800);
  });

  test('«Ровно низ» 400 × 1000/1500: верх 640,3 мм', () {
    final params = _window(
      bottom: 400,
      top: 400,
      left: 1000,
      right: 1500,
    );
    expect(params.topEdgeLengthMm, closeTo(math.sqrt(400 * 400 + 500 * 500), 1e-9));
    expect(params.topEdgeLengthMm, closeTo(640.312, 0.001));
  });

  test('«Ровно верх»: низ — длина нижней кромки 824,6 мм', () {
    final params = _window(
      bottom: 800,
      top: 800,
      level: LevelEdge.top,
    );
    expect(params.topEdgeSlantMm, 0);
    expect(params.bottomEdgeSlantMm, closeTo(200, 1e-9));
    expect(params.bottomEdgeLengthMm, closeTo(824.621, 0.001));
    expect(params.topEdgeLengthMm, 800);

    final geometry = WindowSpec.of(params).geometry;
    // Верх горизонтален на максимальной высоте, низ наклонён.
    expect(geometry.topLeft, const Offset(0, 2000));
    expect(geometry.topRight, const Offset(800, 2000));
    expect(geometry.bottomLeft, const Offset(0, 0));
    expect(geometry.bottomRight, const Offset(800, 200));
    expect(geometry.sideLengths[0], closeTo(824.621, 0.001));
    expect(geometry.sideLengths[2], 800);
  });

  test('«Нет»: верх и низ — по 806,2 мм', () {
    final params = _window(
      bottom: 800,
      top: 800,
      level: LevelEdge.none,
    );
    expect(params.topEdgeSlantMm, closeTo(-100, 1e-9));
    expect(params.bottomEdgeSlantMm, closeTo(100, 1e-9));
    final expected = math.sqrt(800 * 800 + 100 * 100);
    expect(params.topEdgeLengthMm, closeTo(expected, 1e-9));
    expect(params.bottomEdgeLengthMm, closeTo(expected, 1e-9));
    expect(expected, closeTo(806.226, 0.001));

    final geometry = WindowSpec.of(params).geometry;
    expect(geometry.sideLengths[0], closeTo(expected, 1e-6));
    expect(geometry.sideLengths[2], closeTo(expected, 1e-6));
  });

  test('ручная длина кромки пересчитывает проекцию и topOffset по центру', () {
    final params = _window(bottom: 800, top: 700);
    final geometry = WindowSpec.of(params).geometry;
    // Проекция 700, перепад 200 → кромка √(700² + 200²).
    expect(geometry.topEdgeLength, closeTo(math.sqrt(700 * 700 + 200 * 200), 1e-9));
    // Выравнивание по центру: (800 − 700) / 2.
    expect(geometry.topOffset, 50);
    expect(geometry.topLeft, const Offset(50, 2000));
    expect(geometry.topRight, const Offset(750, 1800));
  });

  test('внутренние размеры считаются по длинам кромок', () {
    final params = _window(bottom: 800, top: 800);
    final inner = innerSidesFromOuter(params);
    expect(inner.bottomWidth, closeTo(700, 1e-9));
    expect(inner.topWidth, closeTo(math.sqrt(700 * 700 + 200 * 200), 1e-9));
    expect(inner.topWidth, closeTo(728.011, 0.001));
    expect(inner.leftHeight, closeTo(1900, 1e-9));
    expect(inner.rightHeight, closeTo(1700, 1e-9));
  });

  test('подписи «вн.» совпадают с диалогом внутреннего размера', () {
    final params = _window(bottom: 800, top: 800);
    final spec = WindowSpec.of(params);
    final inner = innerSidesFromOuter(params);
    final innerEdges = innerPvcSideLengthsMm(spec.layers);
    // Порядок: низ, право, верх, лево.
    expect(innerEdges, hasLength(4));
    expect(formatMm(innerEdges[0]), formatMm(inner.bottomWidth));
    expect(formatMm(innerEdges[1]), formatMm(inner.rightHeight));
    expect(formatMm(innerEdges[2]), formatMm(inner.topWidth));
    expect(formatMm(innerEdges[3]), formatMm(inner.leftHeight));
  });

  test('«Ровно верх»: внутренние низ и верх согласованы со стрелками', () {
    final params = _window(bottom: 800, top: 800, level: LevelEdge.top);
    final spec = WindowSpec.of(params);
    final inner = innerSidesFromOuter(params);
    final innerEdges = innerPvcSideLengthsMm(spec.layers);
    expect(inner.bottomWidth, closeTo(728.011, 0.001));
    expect(inner.topWidth, closeTo(700, 1e-9));
    expect(formatMm(innerEdges[0]), formatMm(inner.bottomWidth));
    expect(formatMm(innerEdges[2]), formatMm(inner.topWidth));
  });

  test('«Нет»: обе внутренние кромки — по половине перепада', () {
    final params = _window(bottom: 800, top: 800, level: LevelEdge.none);
    final inner = innerSidesFromOuter(params);
    final expected = math.sqrt(700 * 700 + 100 * 100);
    expect(inner.topWidth, closeTo(expected, 1e-9));
    expect(inner.bottomWidth, closeTo(expected, 1e-9));
    expect(formatMm(inner.topWidth), formatMm(inner.bottomWidth));
  });

  test('длина кромки не может быть меньше перепада', () {
    // Валидация живёт в панели; на модели проверяем формулу: длина 200 при
    // перепаде 200 даёт нулевую проекцию и не падает.
    final params = _window(bottom: 800, top: 0);
    expect(params.topEdgeLengthMm, closeTo(params.topEdgeSlantMm.abs(), 1e-9));
  });
}
