import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
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
  _eyeletRules();
  _costsSummaryRules();
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
      // Пресеты и разбор старых имён enum — для чтения прежних заказов.
      expect(WindowParams.edgePresets, [100, 200, 240]);
      expect(EdgeRoll.presetRawWidth('roll200'), 200);
      expect(EdgeRoll.presetRawWidth('roll500'), isNull);
      expect(WindowParams.finishedEdgeWidth(150), 75);
    });

    test('своя ширина 150 мм: полоса 75 мм, расход и площадь не падают', () {
      const params = WindowParams(
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: 2520,
        rightHeight: 2520,
        rollBottom: 150,
      );
      final spec = WindowSpec.of(params);

      // Готовая полоса нижней стороны — половина рулона.
      expect(spec.layers.finishedWidths[0], 75);
      // Расход ключуется шириной рулона (150), а не типом, и равен длине низа.
      expect(spec.edgeConsumption[150], closeTo(1500, 1e-9));
      expect(spec.edgeConsumption.containsKey(150), isTrue);
      // Площадь плёнки и изделия остаются положительными.
      expect(spec.filmAreaM2, greaterThan(0));
      expect(spec.productAreaM2, closeTo(3.78, 1e-9));
      expect(edgeBandLabel(150), 'Тент 150 мм');
      expect(edgeBandLabel(150, short: true), '150 мм');
    });

    test('расход окантовки совпадает с примером заказчика (654 см + 150 см)', () {
      const params = WindowParams(
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: 2520,
        rightHeight: 2520,
        rollBottom: 100,
        rollLeft: 100,
        rollRight: 100,
        rollTop: 200,
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
      zippers: [ZipperSpec(centered: true)],
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
        zippers: [const ZipperSpec(centered: false, offsetMm: 400)],
      );
      final layers = WindowLayers(moved, WindowGeometry.of(moved));
      final gaps = layers.zipperGaps!;

      expect(gaps.left, closeTo(375, 0.02));
      expect(gaps.right, closeTo(1475, 0.02));
      expect(gaps.band, closeTo(defaultZipperBandWidth, 0.01));
    });

    test('смещение зажимается в границах плёнки', () {
      final tooFar = withZipper.copyWith(
        zippers: [const ZipperSpec(centered: false, offsetMm: 5000)],
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

  group('Вторая молния', () {
    // Две молнии задаются явно: одна по центру, вторая — на 400 мм от левого
    // края. Так их полосы заведомо разнесены по ширине плёнки.
    const twoZippers = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      zippers: [
        ZipperSpec(centered: true),
        ZipperSpec(centered: false, offsetMm: 400),
      ],
    );

    test('две молнии дают две линии и две непересекающиеся полосы', () {
      final layers = WindowLayers(twoZippers, WindowGeometry.of(twoZippers));

      expect(layers.zippers.length, 2);
      expect(layers.zipperBands.length, 2);
      // Плёнка 1900 × 1400: центр — 1000, вторая молния — 50 + 400 = 450.
      expect(layers.zippers[0].start.dx, closeTo(1000, 0.02));
      expect(layers.zippers[1].start.dx, closeTo(450, 0.02));
      expect(layers.zipperBands[0].overlaps(layers.zipperBands[1]), isFalse);
      // Зазоры считаются для каждой молнии отдельно.
      expect(layers.zipperGapsAll.length, 2);
    });

    test('addZipper() дважды не даёт больше maxZippers', () {
      final once = _rect.addZipper();
      expect(once.zippers.length, 1);
      expect(once.zippers.first.centered, isTrue);

      final twice = once.addZipper();
      expect(twice.zippers.length, 2);
      expect(twice.hasZipper, isTrue);

      // Третья молния не добавляется: упор в maxZippers.
      expect(maxZippers, 2);
      expect(twice.addZipper().zippers.length, maxZippers);
    });

    test('removeZipper() убирает нужную молнию', () {
      final removedFirst = twoZippers.removeZipper(0);
      expect(removedFirst.zippers.length, 1);
      expect(removedFirst.zippers.single.centered, isFalse);
      expect(removedFirst.zippers.single.offsetMm, 400);

      final removedSecond = twoZippers.removeZipper(1);
      expect(removedSecond.zippers.length, 1);
      expect(removedSecond.zippers.single.centered, isTrue);

      // Индекс вне списка ничего не меняет.
      expect(twoZippers.removeZipper(5).zippers.length, 2);
    });
  });

  group('Вырезы', () {
    // Окно 2000 × 1500, плёнка по внутренней кромке окантовки — 1900 × 1400
    // с левым нижним углом (50, 50). Вырезы ставим в центр плёнки.
    const rectCutout = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      cutouts: [
        Cutout(
          shape: CutoutShape.rect,
          width: 300,
          height: 300,
          centerXMm: 950,
          centerYMm: 700,
        ),
      ],
    );

    const circleCutout = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      cutouts: [
        Cutout(
          shape: CutoutShape.circle,
          width: 200,
          centerXMm: 950,
          centerYMm: 700,
        ),
      ],
    );

    test('прямоугольный вырез 300×300 уменьшает плёнку ровно на 0,09 м²', () {
      final plain = WindowSpec.of(_rect);
      final withCutout = WindowSpec.of(rectCutout);

      expect(withCutout.layers.cutoutAreaMm2, closeTo(90000, 1e-6));
      expect(
        withCutout.filmAreaM2,
        closeTo(plain.filmAreaM2 - 0.09, 1e-6),
      );
    });

    test('круглый вырез Ø200 уменьшает плёнку на π·0,1² м²', () {
      final plain = WindowSpec.of(_rect);
      final withCutout = WindowSpec.of(circleCutout);
      final expected = math.pi * 0.1 * 0.1;

      expect(expected, closeTo(0.0314, 0.0001));
      expect(
        withCutout.filmAreaM2,
        closeTo(plain.filmAreaM2 - expected, 1e-6),
      );
    });

    test('расход окантовки растёт на периметр выреза', () {
      final plain = WindowSpec.of(_rect);
      final withCutout = WindowSpec.of(rectCutout);

      // Периметр прямоугольника 300×300 — 1200 мм.
      expect(withCutout.layers.cutoutPerimeterMm, closeTo(1200, 1e-6));

      final before = plain.edgeConsumption[100.0]!;
      final after = withCutout.edgeConsumption[100.0]!;
      expect(after - before, closeTo(1200, 1e-6));
    });

    test('addCutout() дважды не даёт больше maxCutouts', () {
      var params = _rect;
      for (var i = 0; i < maxCutouts; i++) {
        params = params.addCutout();
      }
      expect(params.cutouts.length, maxCutouts);

      expect(params.addCutout().cutouts.length, maxCutouts);
      expect(params.removeCutout(0).cutouts.length, maxCutouts - 1);
    });

    test('вырез за пределами полотна даёт замечание', () {
      // Центр прижат к левой кромке плёнки, поэтому половина выреза 300×300
      // выходит за полотно.
      const outside = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        cutouts: [
          Cutout(
            shape: CutoutShape.rect,
            width: 300,
            height: 300,
            centerXMm: 0,
            centerYMm: 400,
          ),
        ],
      );
      final issues = validateParams(outside);

      expect(issues, isNotEmpty);
      expect(
        issues.any((issue) => issue.message.contains('за пределы полотна')),
        isTrue,
      );
    });
  });

  group('Спайка окон', () {
    test('спайка справа убирает окантовку правой стороны', () {
      const welded = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        weldedSides: [EdgeSide.right],
      );
      final plain = WindowSpec.of(_rect);
      final withWeld = WindowSpec.of(welded);
      final rightLength = withWeld.geometry.rightEdgeLength;

      expect(rightLength, closeTo(1500, 1e-9));
      expect(withWeld.layers.isSideWelded(1), isTrue);
      expect(withWeld.layers.weldLengthMm, closeTo(rightLength, 1e-6));

      // Разница с окном без спайки — ровно длина правой стороны.
      final before = plain.edgeConsumption[100.0]!;
      final after = withWeld.edgeConsumption[100.0]!;
      expect(before - after, closeTo(rightLength, 1e-6));
    });

    test('спайка слева и справа убирает обе длины', () {
      const welded = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        weldedSides: [EdgeSide.left, EdgeSide.right],
      );
      final plain = WindowSpec.of(_rect);
      final withWeld = WindowSpec.of(welded);
      final expected = withWeld.geometry.rightEdgeLength +
          withWeld.geometry.leftEdgeLength;

      expect(withWeld.layers.isSideWelded(1), isTrue);
      expect(withWeld.layers.isSideWelded(3), isTrue);
      expect(withWeld.layers.weldLengthMm, closeTo(expected, 1e-6));

      final before = plain.edgeConsumption[100.0]!;
      final after = withWeld.edgeConsumption[100.0]!;
      expect(before - after, closeTo(expected, 1e-6));
      // Остались только верх и низ.
      expect(after, closeTo(4000, 1e-6));
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
      // 5 окон в одну колонку — пять рядов по 640.
      expect(size!.height,
          closeTo(DrawingSheet.titleBlockHeight + 40 + 5 * 640, 0.01));
      expect(size.width, greaterThanOrEqualTo(1360));

      // Теперь подробный режим всегда: и при 2 колонках, и при одном окне
      // лист получает собственный размер, а не растягивается на окно программы.
      // 5 окон в 2 колонки — три ряда, лист ниже.
      final two = DrawingSheet.detailedSheetSize(
        five.setGridColumns(2),
        viewport,
      );
      expect(two, isNotNull);
      expect(two!.height,
          closeTo(DrawingSheet.titleBlockHeight + 40 + 3 * 640, 0.01));
      expect(two.height, lessThan(size.height));

      final single = DrawingSheet.detailedSheetSize(
        const OrderProject(),
        viewport,
      );
      expect(single, isNotNull);
      // Лист одного окна выше окна программы: чертёж крупный, лист листается.
      expect(single!.height, greaterThan(viewport.height));
      expect(single.width, lessThan(viewport.width + 200));
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
          zippers: [ZipperSpec(bandWidth: 200)],
        ),
      );

      // Отдельного поля ParamField для ширины спайки больше нет — ищем
      // предупреждение по тексту и проверяем, что оно не блокирующее.
      expect(
        issues.any((issue) => issue.message.contains('спайки') && !issue.isError),
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

    test('ширина окантовки 20 мм даёт замечание', () {
      final issues = validateParams(const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        rollBottom: 20,
      ));

      expect(
        issues.any((issue) => issue.message.contains('вне диапазона')),
        isTrue,
      );
      expect(hasBlockingIssues(issues), isFalse);
    });

    test('нестандартная ширина окантовки — без замечаний', () {
      final issues = validateParams(const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        rollBottom: 150,
        rollTop: 210,
        rollLeft: 240,
        rollRight: 100,
      ));

      expect(
        issues.any((issue) => issue.message.contains('Окантовка')),
        isFalse,
      );
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

// --- Люверсы: углы и спайка -------------------------------------------------

void _eyeletRules() {
  group('Люверсы: углы и спайка', () {
    test('в углах люверсы всегда круглые, овальные — только по сторонам', () {
      const params = WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        eyeletType: EyeletType.oval42x22,
      );
      final layers = WindowLayers(params, WindowGeometry.of(params));

      final corners = layers.eyelets.where((e) => e.isCorner).toList();
      final sides = layers.eyelets.where((e) => !e.isCorner).toList();

      expect(corners, isNotEmpty);
      expect(sides, isNotEmpty);
      for (final corner in corners) {
        expect(
          layers.typeFor(corner),
          EyeletType.round10,
          reason: 'угол тянет по диагонали — там только круглый люверс',
        );
      }
      for (final side in sides) {
        expect(layers.typeFor(side), EyeletType.oval42x22);
      }
    });

    test('на спаянной стороне люверсы убираются', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        weldedSides: [EdgeSide.right],
      );
      final layers = WindowLayers(params, WindowGeometry.of(params));

      expect(
        layers.eyelets.any((e) => e.side == WindowSide.right),
        isFalse,
        reason: 'по сварному шву крепёж не ставится',
      );
      // Люверсы на остальных сторонах остаются.
      expect(layers.eyelets.any((e) => e.side == WindowSide.left), isTrue);
      expect(layers.eyelets.any((e) => e.side == WindowSide.top), isTrue);
    });

    test('крепёж на спайке можно оставить кнопкой', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        weldedSides: [EdgeSide.right],
        removeEyeletsOnWelded: false,
      );
      final layers = WindowLayers(params, WindowGeometry.of(params));

      expect(layers.eyelets.any((e) => e.side == WindowSide.right), isTrue);
    });
  });
}

/// Сводка расхода: несколько молний считаются каждая.
void _costsSummaryRules() {
  group('Сводка расхода', () {
    test('две молнии удваивают длину полос и расход тента', () {
      const one = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2200,
        rightHeight: 2200,
        zippers: [ZipperSpec(centered: true)],
      );
      const two = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2200,
        rightHeight: 2200,
        zippers: [
          ZipperSpec(centered: false, offsetMm: 600),
          ZipperSpec(centered: false, offsetMm: 1400),
        ],
      );
      final oneSummary = CostsSummary(const OrderProject(windows: [one]));
      final twoSummary = CostsSummary(const OrderProject(windows: [two]));

      expect(oneSummary.zipperCount, 1);
      expect(twoSummary.zipperCount, 2);
      expect(
        twoSummary.zipperBandLengthMm,
        closeTo(oneSummary.zipperBandLengthMm * 2, 0.01),
      );
      // Расход тента на спайку молний тоже удваивается.
      expect(
        twoSummary.edgeByRoll[100.0]! -
            oneSummary.edgeByRoll[100.0]!,
        closeTo(oneSummary.zipperBandLengthMm, 0.01),
      );
    });

    test('дренаж считается по всему заказу', () {
      const window = WindowParams(
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: 2000,
        rightHeight: 2000,
        drainHoles: true,
        drainCount: 3,
      );
      final summary = CostsSummary(const OrderProject(windows: [window, window]));
      expect(summary.drainTotal, 6);
    });
  });
}
