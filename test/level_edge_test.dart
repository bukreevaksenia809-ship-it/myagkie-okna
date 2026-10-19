// Тесты режима «Ровно»: какая кромка остаётся горизонтальной при разных
// высотах сторон. Окно 1200 × 1000/1400, окантовка 100 мм (готовая 50),
// запайка 5 мм, авто-припуск к высоте отключён.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

WindowParams levelWindow({
  LevelEdge level = LevelEdge.bottom,
  double bottom = 1200,
  double top = 1200,
}) => WindowParams(
  bottomWidth: bottom,
  topWidth: top,
  leftHeight: 1000,
  rightHeight: 1400,
  levelEdge: level,
  pvcHeightAllowanceEnabled: false,
);

void main() {
  group('Ровно: высоты 1000/1400, ширины 1200', () {
    test('низ ровно: нижняя кромка горизонтальна, верх наклонён', () {
      final spec = WindowSpec.of(levelWindow());
      final geometry = spec.geometry;
      expect(geometry.bottomLeft, const Offset(0, 0));
      expect(geometry.bottomRight, const Offset(1200, 0));
      expect(geometry.topLeft, const Offset(0, 1000));
      expect(geometry.topRight, const Offset(1200, 1400));
      expect(geometry.bottomLeft.dy, geometry.bottomRight.dy);
      expect(geometry.topLeft.dy, isNot(geometry.topRight.dy));
      // Боковые стороны вертикальны и равны замерам.
      expect(geometry.leftEdgeLength, closeTo(1000, 1e-9));
      expect(geometry.rightEdgeLength, closeTo(1400, 1e-9));
      expect(geometry.areaM2, closeTo(1.44, 1e-9));
      expect(
        geometry.perimeter,
        closeTo(1200 + 1000 + 1400 + math.sqrt(1200 * 1200 + 400 * 400), 1e-6),
      );
    });

    test('верх ровно: верхняя кромка на 1400, нижняя наклонена', () {
      final spec = WindowSpec.of(levelWindow(level: LevelEdge.top));
      final geometry = spec.geometry;
      expect(geometry.topLeft, const Offset(0, 1400));
      expect(geometry.topRight, const Offset(1200, 1400));
      expect(geometry.bottomLeft, const Offset(0, 400));
      expect(geometry.bottomRight, const Offset(1200, 0));
      expect(geometry.topLeft.dy, geometry.topRight.dy);
      expect(geometry.bottomLeft.dy, isNot(geometry.bottomRight.dy));
      expect(geometry.leftEdgeLength, closeTo(1000, 1e-9));
      expect(geometry.rightEdgeLength, closeTo(1400, 1e-9));
      expect(geometry.areaM2, closeTo(1.44, 1e-9));
      // Габаритная высота — по верхней кромке.
      expect(geometry.maxY, closeTo(1400, 1e-9));
      expect(geometry.minY, closeTo(0, 1e-9));
    });

    test('нет: перепад делится поровну — верх +200, низ −200', () {
      final spec = WindowSpec.of(levelWindow(level: LevelEdge.none));
      final geometry = spec.geometry;
      expect(geometry.bottomLeft.dy, 0);
      expect(geometry.bottomRight.dy, closeTo(-200, 1e-9));
      expect(geometry.topLeft.dy, 1000);
      expect(geometry.topRight.dy, closeTo(1200, 1e-9));
      // Обе кромки наклонены, разница поделена пополам.
      expect(
        geometry.bottomRight.dy - geometry.bottomLeft.dy,
        closeTo(-200, 1e-9),
      );
      expect(geometry.topRight.dy - geometry.topLeft.dy, closeTo(200, 1e-9));
      expect(geometry.leftEdgeLength, closeTo(1000, 1e-9));
      expect(geometry.rightEdgeLength, closeTo(1400, 1e-9));
      expect(geometry.areaM2, closeTo(1.44, 1e-9));
      expect(geometry.overallHeight, closeTo(1400, 1e-9));
    });
  });

  group('Ровно: ширины 1200/1000', () {
    WindowParams wide(LevelEdge level) => WindowParams(
      bottomWidth: 1200,
      topWidth: 1000,
      leftHeight: 1200,
      rightHeight: 1200,
      levelEdge: level,
      pvcHeightAllowanceEnabled: false,
    );

    test('выбранная горизонтальная кромка не наклоняется', () {
      for (final level in LevelEdge.values) {
        final spec = WindowSpec.of(wide(level));
        final geometry = spec.geometry;
        // При равных высотах обе кромки горизонтальны при любом режиме.
        expect(geometry.bottomLeft.dy, geometry.bottomRight.dy);
        expect(geometry.topLeft.dy, geometry.topRight.dy);
        // Разница ширин уходит в боковые кромки (верх по центру).
        expect(geometry.topOffset, closeTo(100, 1e-9));
        expect(geometry.areaM2, closeTo(1.32, 1e-9));
        expect(geometry.bottomWidth, 1200);
        expect(geometry.topWidth, 1000);
      }
    });

    test('низ ровно и верх ровно при разных высотах и ширинах', () {
      final bottom = WindowSpec.of(
        wide(LevelEdge.bottom).copyWith(leftHeight: 1000, rightHeight: 1400),
      ).geometry;
      expect(bottom.bottomLeft.dy, bottom.bottomRight.dy);
      expect(bottom.topRight.dy - bottom.topLeft.dy, closeTo(400, 1e-9));

      final top = WindowSpec.of(
        wide(LevelEdge.top).copyWith(leftHeight: 1000, rightHeight: 1400),
      ).geometry;
      expect(top.topLeft.dy, top.topRight.dy);
      expect(top.bottomRight.dy - top.bottomLeft.dy, closeTo(-400, 1e-9));
      // Верхняя кромка — на максимальной высоте, обе части ширины в габарите.
      expect(top.topLeft.dy, closeTo(1400, 1e-9));
      expect(top.spanX, closeTo(1200, 1e-9));
    });
  });

  group('Ровно: производные расчёты', () {
    test('расход окантовки, люверсы и заготовка идут по новому контуру', () {
      final bottom = WindowSpec.of(levelWindow());
      final top = WindowSpec.of(levelWindow(level: LevelEdge.top));
      final none = WindowSpec.of(levelWindow(level: LevelEdge.none));

      // Площадь изделия не зависит от того, как поделён перепад.
      for (final spec in [bottom, top, none]) {
        expect(spec.productAreaM2, closeTo(1.44, 1e-9));
        expect(spec.eyeletCount, greaterThan(0));
        expect(
          spec.edgeConsumption[100.0],
          closeTo(spec.geometry.perimeter, 1e-9),
        );
      }
      // Верх ровно: нижняя кромка длиннее (наклон), верх — 1200.
      expect(top.geometry.sideLengths[0], greaterThan(1200));
      expect(top.geometry.sideLengths[2], closeTo(1200, 1e-9));
      // Низ ровно: наоборот.
      expect(bottom.geometry.sideLengths[0], closeTo(1200, 1e-9));
      expect(bottom.geometry.sideLengths[2], greaterThan(1200));
      // Нет: наклонены обе, длины нижней и верхней больше ширины.
      expect(none.geometry.sideLengths[0], greaterThan(1200));
      expect(none.geometry.sideLengths[2], greaterThan(1200));

      // Заготовка кроится по фактическому контуру, габарит — по нему же.
      for (final spec in [bottom, top, none]) {
        final piece = CutPiece.ofSpec(spec);
        expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
        expect(piece.widthMm, closeTo(spec.filmCutWidthWithShrinkage, 1e-9));
        expect(piece.heightMm, closeTo(spec.filmCutHeightWithShrinkage, 1e-9));
      }
    });

    test('смета и техкарта считаются для всех режимов', () {
      final prices = PriceList.defaults();
      for (final level in LevelEdge.values) {
        final params = levelWindow(level: level);
        final estimate = Estimate.ofWindow(params, prices);
        expect(estimate.total, greaterThan(0));
        final summary = CostsSummary(OrderProject(windows: [params]));
        expect(summary.productAreaM2, closeTo(1.44, 1e-9));
        final card = TechCard.forWindow(params);
        expect(card.operations, isNotEmpty);
      }
    });
  });

  group('Ровно: JSON', () {
    test('режим переживает round-trip', () {
      for (final level in LevelEdge.values) {
        final params = levelWindow(level: level);
        final json = windowToJson(params);
        expect(json['levelEdge'], level.name);
        expect(windowFromJson(json).levelEdge, level);
      }
      final project = orderFromJson(
        orderToJson(OrderProject(windows: [levelWindow(level: LevelEdge.top)])),
      );
      expect(project.windows.first.levelEdge, LevelEdge.top);
    });

    test('старый заказ без поля читается как «низ ровно»', () {
      // bottom — в точности прежняя геометрия (низ горизонтален, верх
      // наклонён), поэтому старые расчёты не меняются.
      expect(
        windowFromJson(const <String, dynamic>{}).levelEdge,
        LevelEdge.bottom,
      );
    });

    test('Т-образное окно: режим хранится, но контур прямоугольный', () {
      final base = WindowParams(
        windowType: WindowType.tShape,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        tSide: TShapeSide.right,
        tWidth: 800,
        tHeight: 600,
        tOffset: 200,
        pvcHeightAllowanceEnabled: false,
      );
      final bottom = WindowSpec.of(base).geometry;
      final top = WindowSpec.of(
        base.copyWith(levelEdge: LevelEdge.top),
      ).geometry;
      expect(top.corners, bottom.corners);
      expect(top.areaM2, closeTo(bottom.areaM2, 1e-9));
      // Значение сохраняется в JSON — если позже Т-окно научится наклонять
      // основное полотно, настройка уже есть.
      expect(
        windowFromJson(
          windowToJson(base.copyWith(levelEdge: LevelEdge.top)),
        ).levelEdge,
        LevelEdge.top,
      );
    });
  });
}
