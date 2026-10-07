import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

/// Пример заказчика: окно 1500 × 2520 мм, окантовка 100 мм (50 мм готовых).
const _example = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

/// Прямоугольное окно 2000 × 1500 мм, окантовка 100 мм (50 мм готовых).
const _rect = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
);

void main() {
  group('Геометрия полотна', () {
    test('прямоугольник: площадь и периметр', () {
      final geometry = WindowGeometry.of(_rect);

      expect(geometry.topOffset, 0);
      expect(geometry.areaM2, closeTo(3.0, 1e-9));
      expect(geometry.perimeter, closeTo(7000, 1e-9));
      expect(geometry.sideLengths, [2000, 1500, 2000, 1500]);
    });

    test('трапеция по центру: смещение верха и длины кромок', () {
      final geometry = WindowGeometry.of(const WindowParams(
        bottomWidth: 3000,
        topWidth: 2400,
        leftHeight: 2500,
        rightHeight: 2500,
      ));

      expect(geometry.topOffset, closeTo(300, 1e-9));
      expect(geometry.areaM2, closeTo(6.75, 1e-9));
      expect(geometry.leftEdgeLength, closeTo(2517.93, 0.02));
    });

    test('нулевые размеры заменяются безопасным значением', () {
      final geometry = WindowGeometry.of(const WindowParams(
        bottomWidth: 0,
        topWidth: -100,
        leftHeight: 0,
        rightHeight: 0,
      ));

      expect(geometry.bottomWidth, 100);
      expect(geometry.areaMm2, greaterThan(0));
    });
  });

  group('Материал полотна', () {
    test('доступные ширины рулонов по материалам', () {
      expect(FilmMaterial.clearPvc.rollWidths,
          [1400, 1800, 2000, 2400, 2600]);
      expect(FilmMaterial.tintedPvc.maxRollWidth, 2400);
      expect(FilmMaterial.mosquitoNet.maxRollWidth, 3000);
      expect(FilmMaterial.clearPvc.defaultRollWidth, 2000);
    });

    test('в заказе можно выбрать ширину рулона под материал', () {
      const project = OrderProject();
      final withTinted = project
          .updateSelected(_rect.copyWith(material: FilmMaterial.tintedPvc))
          .setRollWidth(FilmMaterial.tintedPvc, 2400);

      expect(withTinted.rollWidthFor(FilmMaterial.tintedPvc), 2400);
      // Ширина, которой нет в списке материала, заменяется на стандартную.
      final wrong = withTinted.setRollWidth(FilmMaterial.tintedPvc, 3000);
      expect(wrong.rollWidthFor(FilmMaterial.tintedPvc), 2000);
    });

    test('материалы заказа перечисляются без повторов', () {
      const project = OrderProject(windows: [
        _rect,
        WindowParams(
          material: FilmMaterial.mosquitoNet,
          bottomWidth: 1000,
          topWidth: 1000,
          leftHeight: 1000,
          rightHeight: 1000,
        ),
        _example,
      ]);

      expect(project.materialsInOrder,
          [FilmMaterial.clearPvc, FilmMaterial.mosquitoNet]);
    });
  });

  group('Окантовка и раскрой', () {
    test('рулон складывается пополам: 100 → 50, 200 → 100, 240 → 120', () {
      expect(EdgeRoll.roll100.finishedWidth, 50);
      expect(EdgeRoll.roll200.finishedWidth, 100);
      expect(EdgeRoll.roll240.finishedWidth, 120);
    });

    test('расход окантовки совпадает с примером заказчика (654 см + 150 см)', () {
      const params = WindowParams(
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: 2520,
        rightHeight: 2520,
        rollBottom: EdgeRoll.roll100,
        rollLeft: EdgeRoll.roll100,
        rollRight: EdgeRoll.roll100,
        rollTop: EdgeRoll.roll200,
      );
      final spec = WindowSpec.of(params);

      expect(spec.edgeConsumptionLabels,
          ['Тент 100 мм — 654 см', 'Тент 200 мм — 150 см']);
    });

    test('площадь готового изделия считается по наружному контуру', () {
      // Окно 1500 × 2520 мм → 3,78 м².
      final spec = WindowSpec.of(_example);
      expect(spec.productAreaM2, closeTo(3.78, 1e-9));

      // Трапеция: площадь по четырём углам, а не по габариту.
      const trapezoid = WindowParams(
        bottomWidth: 3000,
        topWidth: 2400,
        leftHeight: 2500,
        rightHeight: 2500,
      );
      final trapezoidSpec = WindowSpec.of(trapezoid);
      expect(trapezoidSpec.productAreaM2, closeTo(6.75, 1e-9));
      expect(trapezoidSpec.productAreaM2,
          lessThan(trapezoidSpec.geometry.spanX *
              trapezoidSpec.geometry.overallHeight /
              1000000));
    });

    test('напайка 25 мм и усадка увеличивают раскрой плёнки', () {
      final spec = WindowSpec.of(_rect);

      expect(spec.filmVisibleWidth, closeTo(1900, 0.01));
      expect(spec.filmCutWidth, closeTo(1950, 0.01));
      expect(spec.filmCutHeight, closeTo(1450, 0.01));
      expect(spec.filmCutWidthWithShrinkage, closeTo(1950 * 1.015, 0.02));
    });
  });

  group('Люверсы', () {
    test('идут от угла до угла, углы не дублируются', () {
      final layers = WindowLayers(_rect, WindowGeometry.of(_rect));

      expect(layers.eyeletCount, 24);
      final bySide = <WindowSide, int>{};
      for (final eyelet in layers.eyelets) {
        bySide[eyelet.side] = (bySide[eyelet.side] ?? 0) + 1;
      }
      expect(bySide[WindowSide.bottom], 8);
      expect(bySide[WindowSide.top], 7);
    });

    test('у глухого окна только круглые люверсы', () {
      const fixed = WindowParams(
        windowType: WindowType.fixed,
        eyeletType: EyeletType.oval42x22,
      );
      const lifting = WindowParams(
        windowType: WindowType.lifting,
        eyeletType: EyeletType.oval42x22,
      );

      expect(fixed.effectiveEyeletType, EyeletType.round10);
      expect(WindowSpec.of(lifting).eyeletType, EyeletType.oval42x22);
    });

    test('карман: угловые люверсы внизу убраны, боковые подняты на 50 мм', () {
      const withPocket = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        pocket: true,
      );
      final layers = WindowLayers(withPocket, WindowGeometry.of(withPocket));
      final bottom = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.bottom)
          .toList();
      final right = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.right)
          .toList();
      final left = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.left)
          .toList();

      // Нижняя сторона потеряла оба угловых люверса: было 8, стало 6,
      // а боковые нижние люверсы стали отдельными (поднялись на 50 мм).
      expect(bottom.length, 6);
      expect(layers.eyeletCount, 24);

      // Нижний люверс сбоку поднят на 50 мм от угла (25 + 50 = 75).
      final rightLowest =
          right.reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      final leftLowest = left.reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      expect(rightLowest.center.dy, closeTo(75, 0.02));
      expect(leftLowest.center.dy, closeTo(75, 0.02));
    });

    test('карман — продолжение нижнего тента вниз', () {
      const withPocket = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        pocket: true,
      );
      final geometry = WindowGeometry.of(withPocket);
      final layers = WindowLayers(withPocket, geometry);
      final rect = layers.pocketRect;

      expect(rect.isEmpty, isFalse);
      expect(rect.bottom, closeTo(0, 0.01), reason: 'накладка идёт от низа окна');
      expect(rect.top, closeTo(-pocketFinishedWidth, 0.01));
      expect(rect.height, closeTo(pocketFinishedWidth, 0.01));
      expect(rect.width, closeTo(2000, 0.01));
      // Нижняя граница листа опускается под карман.
      expect(geometry.minY, closeTo(-pocketFinishedWidth, 0.01));
      expect(geometry.spanY, closeTo(1500 + pocketFinishedWidth, 0.01));
    });
  });

  group('Молния', () {
    const withZipper = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      zipperEnabled: true,
    );

    test('молния всегда вертикальная и по центру по умолчанию', () {
      final layers = WindowLayers(withZipper, WindowGeometry.of(withZipper));
      final zipper = layers.zipper;

      expect(zipper, isNotNull);
      expect(zipper!.start.dx, closeTo(1000, 0.02));
      expect(zipper.start.dx, closeTo(zipper.end.dx, 1e-9),
          reason: 'вертикальная линия — одна и та же координата X');
      expect(zipper.start.dy, lessThan(zipper.end.dy));
    });

    test('спайка 50 мм и расстояния до кромок плёнки', () {
      final layers = WindowLayers(withZipper, WindowGeometry.of(withZipper));
      final gaps = layers.zipperGaps;

      expect(gaps, isNotNull);
      expect(gaps!.band, closeTo(defaultZipperBandWidth, 0.01));
      // Плёнка 1900 × 1400: спайка 50 по центру → 925 слева и справа.
      expect(gaps.left, closeTo(925, 0.02));
      expect(gaps.right, closeTo(925, 0.02));
      expect(layers.zipperBand!.width, closeTo(defaultZipperBandWidth, 0.01));
    });

    test('молнию можно двигать влево-вправо', () {
      final moved = withZipper.copyWith(
        zipperCentered: false,
        zipperOffsetMm: 400,
      );
      final layers = WindowLayers(moved, WindowGeometry.of(moved));
      final gaps = layers.zipperGaps!;

      expect(gaps.left, closeTo(375, 0.02));
      expect(gaps.right, closeTo(1475, 0.02));
      expect(gaps.band, closeTo(defaultZipperBandWidth, 0.01));
    });

    test('смещение зажимается в границах плёнки', () {
      final tooFar = withZipper.copyWith(
        zipperCentered: false,
        zipperOffsetMm: 5000,
      );
      final layers = WindowLayers(tooFar, WindowGeometry.of(tooFar));
      final gaps = layers.zipperGaps!;

      // Спайка остаётся внутри плёнки: расстояние до кромок не отрицательное.
      expect(gaps.left, greaterThanOrEqualTo(0));
      expect(gaps.right, greaterThanOrEqualTo(0));
      expect(gaps.left + gaps.band + gaps.right, closeTo(1900, 0.05));
    });

    test('заготовка спайки — полоса по высоте плёнки', () {
      final spec = WindowSpec.of(withZipper);
      final piece = spec.zipperBandPiece;

      expect(piece, isNotNull);
      expect(piece!.$1, closeTo(defaultZipperBandWidth, 0.01));
      expect(piece.$2, closeTo(1400, 0.01));
      expect(spec.zipperSummary, contains('вертикальная'));
    });

    test('без молнии элементов нет', () {
      final layers = WindowLayers(_rect, WindowGeometry.of(_rect));

      expect(layers.zipper, isNull);
      expect(layers.zipperBand, isNull);
      expect(layers.zipperGaps, isNull);
    });
  });

  group('Подъёмное окно', () {
    test('подъёмные ремни: 2 до 2 м, дальше +1 на метр', () {
      WindowParams lifting(double width) => WindowParams(
            windowType: WindowType.lifting,
            bottomWidth: width,
            topWidth: width,
          );

      expect(lifting(1500).liftStrapCount, 2);
      expect(lifting(2000).liftStrapCount, 2);
      expect(lifting(2001).liftStrapCount, 3);
      expect(lifting(3200).liftStrapCount, 4);
      expect(_rect.liftStrapCount, 0);
    });

    test('ремни висят сверху и разносятся по ширине', () {
      const params = WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: 2520,
        rightHeight: 2520,
      );
      final layers = WindowLayers(params, WindowGeometry.of(params));
      final straps = layers.liftStraps;

      expect(straps.length, 2);
      expect(
          straps.first.bottom, closeTo(layers.filmVisibleBounds.bottom, 0.01));
      expect(straps.first.width, liftStrapWidth);
    });

    test('рулон и крепёж подвижных сторон', () {
      const lifting = WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
      );
      final layers = WindowLayers(lifting, WindowGeometry.of(lifting));

      expect(layers.movableSideEyelets.isNotEmpty, isTrue);
      expect(layers.liftStraps.length, 2);
    });

    test('у глухого окна крепёж подвижных сторон не рисуется', () {
      expect(
        WindowLayers(_rect, WindowGeometry.of(_rect)).movableSideEyelets,
        isEmpty,
      );
    });
  });

  group('Заказ и вид листа', () {
    test('нумерация окон и подписи', () {
      const project = OrderProject();
      final withThree =
          project.updateSelected(_example).addWindow().addWindow();

      expect(withThree.windowCount, 3);
      expect(withThree.labelFor(0), 'Окно №1');
      expect(withThree.labelFor(2), 'Окно №3');
    });

    test('вид листа и колонки', () {
      const project = OrderProject();

      expect(project.sheetMode, SheetMode.single);
      expect(project.setSheetMode(SheetMode.grid).sheetMode, SheetMode.grid);
      expect(project.setGridColumns(1).gridColumns, 1);
      expect(project.setGridColumns(9).gridColumns, 4);
    });

    test('подробный лист растёт под число окон', () {
      const viewport = Size(1500, 900);
      final five = const OrderProject()
          .addWindow()
          .addWindow()
          .addWindow()
          .addWindow()
          .setSheetMode(SheetMode.grid)
          .setGridColumns(1);

      final size = DrawingSheet.detailedSheetSize(five, viewport);
      expect(size, isNotNull);
      expect(size!.height,
          closeTo(DrawingSheet.titleBlockHeight + 40 + 5 * 640, 0.01));
      expect(size.width, greaterThanOrEqualTo(1360));

      // В обычных режимах лист заполняет окно программы.
      expect(
        DrawingSheet.detailedSheetSize(five.setGridColumns(2), viewport),
        isNull,
      );
      expect(
        DrawingSheet.detailedSheetSize(
          five.setSheetMode(SheetMode.single),
          viewport,
        ),
        isNull,
      );
    });

    test('удаление окна не уходит ниже одного', () {
      const project = OrderProject();
      final two = project.addWindow();

      expect(two.removeSelected().windowCount, 1);
      expect(two.removeSelected().removeSelected().windowCount, 1);
    });
  });

  group('Проверка параметров', () {
    test('шаг люверсов вне 250–400 — предупреждение', () {
      final issues = validateParams(
        const WindowParams(bottomWidth: 2000, topWidth: 2000, eyeletStep: 500),
      );

      expect(hasBlockingIssues(issues), isFalse);
      expect(
        issues.any((issue) =>
            issue.field == ParamField.eyeletStep && !issue.isError),
        isTrue,
      );
    });

    test('нулевая ширина — ошибка', () {
      final issues =
          validateParams(const WindowParams(bottomWidth: 0, topWidth: 0));

      expect(hasBlockingIssues(issues), isTrue);
    });

    test('ширина спайки вне 40–120 — предупреждение', () {
      final issues = validateParams(
        const WindowParams(
          bottomWidth: 2000,
          topWidth: 2000,
          zipperEnabled: true,
          zipperBandWidth: 200,
        ),
      );

      expect(
        issues.any((issue) => issue.field == ParamField.zipperBandWidth),
        isTrue,
      );
    });

    test('верх шире низа — предупреждение, а не ошибка', () {
      final issues = validateParams(const WindowParams(
        bottomWidth: 2000,
        topWidth: 2400,
      ));

      expect(hasBlockingIssues(issues), isFalse);
    });
  });

  group('Форматирование', () {
    test('разряды, сантиметры, метры и проценты', () {
      expect(formatMm(3000), '3\u202F000');
      expect(formatCm(6540), '654');
      expect(formatMeters(6.75), '6,75');
      expect(formatPercent(1.5), '1,5 %');
    });

    test('разбор ввода с запятой и пробелами', () {
      expect(parseMm('2 500'), 2500);
      expect(parseMm('2,5'), 2.5);
      expect(parseMm('abc'), isNull);
    });
  });
}
