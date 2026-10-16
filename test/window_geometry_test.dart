import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

/// Пример заказчика: окно 1500 × 2520 мм, окантовка 100 мм (50 мм готовых).
const _example = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

/// Прямоугольное окно 2000 × 1500 мм, окантовка 100 мм (50 мм готовых),
/// запайка 25 мм — как в примере заказчика.
const _rect = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  weldOverlapMm: 25,
);

void main() {
  _eyeletRules();
  _freeEyeletStepRules();
  _costsSummaryRules();
  _weldedWindowRules();
  _allowanceRules();
  _shrinkageAndPvcAllowanceRules();
  _weldOverlapRules();
  _screenRules();
  _pocketRules();
  _rollWidthRules();
  _eyeletlessSideRules();
  _anyEyeletTypeRules();
  _screenZipperRules();
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
    test('рулон складывается пополам: 80 → 40, 100 → 50, 120 → 60, '
        '200 → 100, 240 → 120', () {
      expect(EdgeRoll.roll80.finishedWidth, 40);
      expect(EdgeRoll.roll100.finishedWidth, 50);
      expect(EdgeRoll.roll120.finishedWidth, 60);
      expect(EdgeRoll.roll200.finishedWidth, 100);
      expect(EdgeRoll.roll240.finishedWidth, 120);
      // Пресеты (в порядке ширины рулона) и разбор старых имён enum — для
      // чтения прежних заказов и как опорные точки прайса.
      expect(WindowParams.edgePresets, [80, 100, 120, 200, 240]);
      expect(EdgeRoll.presetRawWidth('roll80'), 80);
      expect(EdgeRoll.presetRawWidth('roll120'), 120);
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
      // Усадка по умолчанию выключена — включаем её явно, чтобы проверить
      // компенсацию 1,5 % (типовое значение).
      final shrunk = _rect.copyWith(
        shrinkageEnabled: true,
        shrinkagePercent: defaultShrinkagePercent,
      );
      final spec = WindowSpec.of(shrunk);

      expect(spec.filmVisibleWidth, closeTo(1900, 0.01));
      expect(spec.filmCutWidth, closeTo(1950, 0.01));
      expect(spec.filmCutHeight, closeTo(1450, 0.01));
      expect(spec.filmCutWidthWithShrinkage, closeTo(1950 * 1.015, 0.02));

      // С выключенной усадкой заготовка чистая: ширина 1950, высота
      // 1450 + 10 (авто-припуск ПВХ) = 1460 мм.
      final plain = WindowSpec.of(_rect);
      expect(plain.filmCutWidthWithShrinkage, closeTo(1950, 1e-9));
      expect(plain.filmCutHeightWithShrinkage, closeTo(1460, 1e-9));
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

    test('любой тип люверса доступен на любом окне, в углах — круглый', () {
      const fixed = WindowParams(
        windowType: WindowType.fixed,
        eyeletType: EyeletType.oval42x22,
      );
      const lifting = WindowParams(
        windowType: WindowType.lifting,
        eyeletType: EyeletType.oval42x22,
      );

      // Принудительной замены на круглый у глухого окна больше нет: тип
      // выбирает пользователь, он же и ставится.
      expect(fixed.effectiveEyeletType, EyeletType.oval42x22);
      expect(WindowSpec.of(fixed).eyeletType, EyeletType.oval42x22);
      expect(WindowSpec.of(lifting).eyeletType, EyeletType.oval42x22);

      // Единственное правило по типу — «в углах круглый».
      final fixedLayers = WindowLayers(fixed, WindowGeometry.of(fixed));
      final sideEyelet = fixedLayers.eyelets.firstWhere((e) => !e.isCorner);
      final cornerEyelet = fixedLayers.eyelets.firstWhere((e) => e.isCorner);
      expect(fixedLayers.typeFor(sideEyelet), EyeletType.oval42x22);
      expect(fixedLayers.typeFor(cornerEyelet), EyeletType.round10);
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
      // Сравниваем с _rect: там запайка 25 мм.
      weldOverlapMm: 25,
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
      weldOverlapMm: 25,
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

    test('подробный лист растёт под число окон (страницы A4)', () {
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
      // Лист чертежа — A4: 5 окон в одну колонку — пять страниц A4.
      // Поля рабочей области вокруг листа выводим из самого размера, чтобы
      // не дублировать приватную константу: высота = 5 × A4 + поля.
      final padding = size!.height - DrawingSheet.a4Height * 5;
      expect(padding, greaterThan(0));
      expect(padding, lessThan(100));
      expect(size.width, closeTo(DrawingSheet.a4Width + padding, 0.01));
      // Сам лист (без полей рабочей области) — ровно A4: и по размеру,
      // и по пропорциям 1 : 1,4142 (допуск 0,5 %).
      expect(DrawingSheet.a4PageCount(five), 5);
      expect(
        DrawingSheet.a4Height / DrawingSheet.a4Width,
        closeTo(DrawingSheet.a4Aspect, DrawingSheet.a4Aspect * 0.005),
      );
      expect(DrawingSheet.a4Aspect, closeTo(1.4142, 0.005));

      // Резать PDF можно только по границам страниц A4 — окно не рвётся.
      expect(DrawingSheet.safeBreakFractions(five, viewport), [
        closeTo(0.2, 1e-9),
        closeTo(0.4, 1e-9),
        closeTo(0.6, 1e-9),
        closeTo(0.8, 1e-9),
      ]);

      // 5 окон в 2 колонки — три ряда, три страницы, лист ниже.
      final two = DrawingSheet.detailedSheetSize(
        five.setGridColumns(2),
        viewport,
      );
      expect(two, isNotNull);
      expect(
        two!.height,
        closeTo(DrawingSheet.a4Height * 3 + padding, 0.01),
      );
      expect(two.height, lessThan(size.height));
      expect(two.width, closeTo(size.width, 0.01));

      final single = DrawingSheet.detailedSheetSize(
        const OrderProject(),
        viewport,
      );
      expect(single, isNotNull);
      // Лист одного окна — одна страница A4, выше окна программы.
      expect(
        single!.height,
        closeTo(DrawingSheet.a4Height + padding, 0.01),
      );
      expect(single.height, greaterThan(viewport.height));
      expect(single.width, lessThan(viewport.width + 200));

      // Одно окно — резать нечего; размер листа не зависит от окна программы.
      expect(DrawingSheet.safeBreakFractions(const OrderProject(), viewport),
          isNull);
      expect(
        DrawingSheet.detailedSheetSize(
          const OrderProject(),
          const Size(800, 600),
        ),
        single,
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
    test('интервал люверсов 500 мм — подсказка, не запрет', () {
      final issues = validateParams(
        const WindowParams(bottomWidth: 2000, topWidth: 2000, eyeletStep: 500),
      );

      expect(hasBlockingIssues(issues), isFalse);
      expect(
        issues.any((issue) =>
            issue.field == ParamField.eyeletStep &&
            issue.severity == ParamIssueSeverity.info),
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

/// Свободный интервал люверсов: пользователь задаёт его сам, а фактический
/// интервал по сторонам получается НЕ БОЛЬШЕ заданного.
void _freeEyeletStepRules() {
  /// Окно 2000 × 1500 с окантовкой 100 мм (линия люверсов 1950 × 1450).
  WindowParams rect(double step) => WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        eyeletStep: step,
      );

  WindowLayers layersOf(WindowParams params) =>
      WindowLayers(params, WindowGeometry.of(params));

  group('Свободный интервал люверсов', () {
    test('шаг 280 на 2000 × 1500: факт не больше 280, число по ручному расчёту',
        () {
      final layers = layersOf(rect(280));

      // Линия люверсов — середина окантовки: 2000 − 2×25 = 1950,
      // 1500 − 2×25 = 1450. Интервалы: ceil(1950/280) = 7, ceil(1450/280) = 6.
      const longSide = 1950.0;
      const shortSide = 1450.0;
      const longIntervals = 7;
      const shortIntervals = 6;
      expect((longSide / 280).ceil(), longIntervals);
      expect((shortSide / 280).ceil(), shortIntervals);

      expect(layers.eyeletSteps.length, 4, reason: 'по записи на сторону');
      for (final step in layers.eyeletSteps) {
        expect(step, lessThanOrEqualTo(280 + 1e-9),
            reason: 'фактический интервал не больше заданного');
        // Гарантия алгоритма: ceil даёт факт в пределах (заданный/2, заданный].
        expect(step, greaterThan(140));
      }

      // Длинные стороны: 1950/7 ≈ 278,6 мм; короткие: 1450/6 ≈ 241,7 мм.
      final sorted = [...layers.eyeletSteps]..sort();
      expect(sorted[0], closeTo(shortSide / shortIntervals, 1e-9));
      expect(sorted[1], closeTo(shortSide / shortIntervals, 1e-9));
      expect(sorted[2], closeTo(longSide / longIntervals, 1e-9));
      expect(sorted[3], closeTo(longSide / longIntervals, 1e-9));

      // Уникальных люверсов: (7+1) + (6+1) + (7+1) + (6+1) − 4 общих угла.
      const manual = 8 + 7 + 8 + 7 - 4;
      expect(manual, 26);
      expect(layers.eyeletCount, manual);
    });

    test('шаг 280 на скрине 2000 × 1500: факт ровно 250 по всем сторонам', () {
      // У скрина линия люверсов — сам контур (без окантовки): 2000 и 1500.
      // ceil(2000/280) = 8 → 250; ceil(1500/280) = 6 → 250.
      const params = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        eyeletStep: 280,
      );
      final layers = layersOf(params);

      expect(layers.eyeletSteps, hasLength(4));
      for (final step in layers.eyeletSteps) {
        expect(step, inInclusiveRange(250, 280));
        expect(step, closeTo(250, 1e-9));
      }
      expect(WindowSpec.of(params).eyeletStepLabel, '250 мм');
    });

    test('шаг 600: факт не больше 600, люверсов меньше, чем при 300', () {
      final step300 = layersOf(rect(300));
      final step600 = layersOf(rect(600));

      for (final step in step600.eyeletSteps) {
        expect(step, lessThanOrEqualTo(600 + 1e-9));
      }
      expect(step600.eyeletCount, lessThan(step300.eyeletCount));
      // Вручную: ceil(1950/600) = 4, ceil(1450/600) = 3 →
      // (4+1) + (3+1) + (4+1) + (3+1) − 4 = 14.
      expect(step600.eyeletCount, 14);
      expect(step300.eyeletCount, 24);
    });

    test('шаг 1500 на окне 800 × 600: по люверсу в углах, без падения', () {
      const params = WindowParams(
        bottomWidth: 800,
        topWidth: 800,
        leftHeight: 600,
        rightHeight: 600,
        eyeletStep: 1500,
      );
      final layers = layersOf(params);

      // Линия люверсов 750 × 550: на каждой стороне ровно один интервал,
      // то есть по люверсу в углах. Четыре угла общие для соседних сторон.
      expect(layers.eyeletCount, 4);
      expect(layers.eyelets.every((eyelet) => eyelet.isCorner), isTrue);
      for (final step in layers.eyeletSteps) {
        expect(step, lessThanOrEqualTo(1500 + 1e-9));
      }
      // Подпись фактического интервала считается без ошибок.
      expect(WindowSpec.of(params).eyeletStepLabel, isNot('—'));
    });

    test('нулевой и битый интервал не ломают геометрию (минимум 50 мм)', () {
      for (final step in const [0.0, -100.0, double.nan]) {
        final layers = layersOf(rect(step));
        expect(layers.eyeletCount, greaterThan(0));
        for (final actual in layers.eyeletSteps) {
          expect(actual, greaterThanOrEqualTo(50));
        }
      }
    });

    test('интервал 280 переживает JSON round-trip', () {
      final params = rect(280);
      expect(windowToJson(params)['eyeletStep'], 280);
      expect(windowFromJson(windowToJson(params)).eyeletStep, 280);

      final project = orderFromJson(
        orderToJson(OrderProject(windows: [params])),
      );
      expect(project.windows.first.eyeletStep, 280);

      // Старый заказ без поля и заказ со строкой читаются без потерь.
      expect(
        windowFromJson(const <String, dynamic>{
          'bottomWidth': 2000,
          'topWidth': 2000,
        }).eyeletStep,
        300,
      );
      expect(
        windowFromJson(const <String, dynamic>{'eyeletStep': '280'}).eyeletStep,
        280,
      );
    });
  });

  group('Проверка свободного интервала люверсов', () {
    ParamIssue? issueFor(double step) {
      for (final issue in validateParams(rect(step))) {
        if (issue.field == ParamField.eyeletStep) return issue;
      }
      return null;
    }

    test('500 мм — подсказка (info), а не ошибка и не запрет', () {
      final issue = issueFor(500.0);
      expect(issue, isNotNull);
      expect(issue!.severity, ParamIssueSeverity.info);
      expect(issue.isError, isFalse);
      expect(issue.isWarning, isFalse);
      expect(issue.message, contains('рекомендуем'));
    });

    test('100 мм — предупреждение о перерасходе', () {
      final issue = issueFor(100.0);
      expect(issue, isNotNull);
      expect(issue!.severity, ParamIssueSeverity.warning);
      expect(issue.isError, isFalse);
      expect(issue.message, contains('перерасход'));
    });

    test('900 мм — предупреждение о парусности', () {
      final issue = issueFor(900.0);
      expect(issue, isNotNull);
      expect(issue!.severity, ParamIssueSeverity.warning);
      expect(issue.message, contains('парусить'));
    });

    test('40 мм и 2500 мм — ошибки (вне рамок 50…2000)', () {
      final low = issueFor(40.0);
      expect(low, isNotNull);
      expect(low!.isError, isTrue);
      expect(hasBlockingIssues(validateParams(rect(40))), isTrue);

      final high = issueFor(2500.0);
      expect(high, isNotNull);
      expect(high!.isError, isTrue);
      expect(hasBlockingIssues(validateParams(rect(2500))), isTrue);
    });

    test('280 и 300 мм — без замечаний', () {
      expect(issueFor(280.0), isNull);
      expect(issueFor(300.0), isNull);
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

// --- Спайка окон: четыре стороны -------------------------------------------

void _weldedWindowRules() {
  group('Спайка окон: копия к спайке', () {
    test('спайка справа: копия встаёт после окна и варится слева', () {
      const source = WindowParams(
        drawingNumber: 'МО-014',
        bottomWidth: 2000,
        topWidth: 1980,
        leftHeight: 1500,
        rightHeight: 1520,
        material: FilmMaterial.tintedPvc,
        rollBottom: 150,
        zippers: [ZipperSpec(centered: false, offsetMm: 500)],
        cutouts: [Cutout(width: 300, height: 200, centerXMm: 700, centerYMm: 600)],
        pocket: true,
      );
      final welded = const OrderProject(windows: [source])
          .addWeldedWindow(EdgeSide.right);

      expect(welded.windowCount, 2);
      expect(welded.selectedIndex, 1);
      expect(welded.windows[0].weldedSides, [EdgeSide.right]);
      expect(welded.windows[1].weldedSides, [EdgeSide.left]);

      // Шаблон скопирован целиком: размеры, материал, окантовка, молнии,
      // вырезы и карман.
      final copy = welded.windows[1];
      expect(copy.bottomWidth, source.bottomWidth);
      expect(copy.topWidth, source.topWidth);
      expect(copy.leftHeight, source.leftHeight);
      expect(copy.rightHeight, source.rightHeight);
      expect(copy.material, source.material);
      expect(copy.rollBottom, source.rollBottom);
      expect(copy.zippers.length, source.zippers.length);
      expect(copy.cutouts.length, source.cutouts.length);
      expect(copy.pocket, source.pocket);

      // Номера окон разные, у копии маркировка очищена.
      expect(welded.labelFor(0), 'Окно №1');
      expect(welded.labelFor(1), 'Окно №2');
      expect(welded.windows[0].drawingNumber, 'МО-014');
      expect(copy.drawingNumber, isEmpty);
    });

    test('спайка сверху: копия варится снизу; спайка снизу — копия сверху',
        () {
      final top = const OrderProject(windows: [_rect])
          .addWeldedWindow(EdgeSide.top);
      expect(top.windowCount, 2);
      expect(top.windows[0].weldedSides, [EdgeSide.top]);
      expect(top.windows[1].weldedSides, [EdgeSide.bottom]);

      final bottom = const OrderProject(windows: [_rect])
          .addWeldedWindow(EdgeSide.bottom);
      expect(bottom.windows[0].weldedSides, [EdgeSide.bottom]);
      expect(bottom.windows[1].weldedSides, [EdgeSide.top]);
    });

    test('повторная спайка по той же стороне не дублируется', () {
      const source = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        weldedSides: [EdgeSide.right],
      );
      final welded = const OrderProject(windows: [source])
          .addWeldedWindow(EdgeSide.right);

      // У текущего окна сторона уже была — второй раз её не добавляем.
      expect(welded.windows[0].weldedSides, [EdgeSide.right]);
      // Копия встаёт слева и варится с ним; унаследованная сторона тоже
      // остаётся в единственном экземпляре.
      expect(welded.windows[1].weldedSides, [EdgeSide.right, EdgeSide.left]);
      expect(
        welded.windows[1].weldedSides.where((side) => side == EdgeSide.left),
        hasLength(1),
      );
      expect(
        welded.windows[1].weldedSides.where((side) => side == EdgeSide.right),
        hasLength(1),
      );
    });

    test('расход окантовки уменьшается ровно на длину общей стороны', () {
      final project = const OrderProject(windows: [_rect])
          .addWeldedWindow(EdgeSide.bottom);
      final plain = WindowSpec.of(_rect);
      final bottomLength = plain.geometry.sideLengths[0];

      for (final window in project.windows) {
        final spec = WindowSpec.of(window);
        expect(
          plain.edgeConsumption[100.0]! - spec.edgeConsumption[100.0]!,
          closeTo(bottomLength, 1e-6),
          reason: 'нижняя спайка убирает ровно длину нижней кромки',
        );
        expect(
          spec.edgeConsumption.values.every((length) => length >= 0),
          isTrue,
        );
        expect(spec.layers.weldLengthMm, closeTo(bottomLength, 1e-6));
      }
    });

    test('все четыре стороны спаяны: расход не уходит в минус', () {
      final params = _rect.copyWith(weldedSides: EdgeSide.values);
      final spec = WindowSpec.of(params);
      final total =
          spec.edgeConsumption.values.fold(0.0, (sum, value) => sum + value);

      expect(total, 0);
      expect(spec.layers.weldLengthMm, closeTo(spec.geometry.perimeter, 1e-6));
    });

    test('JSON round-trip заказа с вертикальной спайкой', () {
      final project = const OrderProject(windows: [_rect])
          .addWeldedWindow(EdgeSide.top);
      final restored = orderFromJson(orderToJson(project));

      expect(restored.windowCount, 2);
      expect(restored.windows[0].weldedSides, [EdgeSide.top]);
      expect(restored.windows[1].weldedSides, [EdgeSide.bottom]);
      // Спаянная сторона по-прежнему без окантовки и с тем же швом.
      final before = WindowSpec.of(project.windows[0]);
      final after = WindowSpec.of(restored.windows[0]);
      expect(after.layers.isSideWelded(2), isTrue);
      expect(
        after.edgeConsumption[100.0],
        closeTo(before.edgeConsumption[100.0]!, 1e-6),
      );
      expect(after.layers.weldLengthMm, closeTo(before.layers.weldLengthMm, 1e-6));
    });
  });
}

// --- Припуск на раскрой ------------------------------------------------------
//
// Припуск добавляется ТОЛЬКО к заготовке плёнки в раскрое. Изделие, чертёж,
// окантовка, люверсы, площадь изделия и остальные расчёты идут по основным
// размерам замера.

void _allowanceRules() {
  group('Припуск на раскрой', () {
    // Пример заказчика: изделие 2000 × 2000 мм, окантовка 100 мм (готовая 50),
    // напайка 25 мм (задана явно: по умолчанию в модели 5 мм),
    // припуск +100 по ширине и +100 по высоте.
    const product = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      weldOverlapMm: 25,
      allowanceWidthMm: 100,
      allowanceHeightMm: 100,
    );
    const withoutAllowance = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      weldOverlapMm: 25,
    );
    // Припуск другого размера — для round-trip и подписей.
    const measured = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      weldOverlapMm: 25,
      allowanceWidthMm: 120,
      allowanceHeightMm: 80,
    );

    test('по умолчанию ручного припуска нет, но есть авто +10 мм у ПВХ', () {
      expect(const WindowParams().allowanceWidthMm, 0);
      expect(const WindowParams().allowanceHeightMm, 0);
      expect(withoutAllowance.hasManualAllowance, isFalse);
      // Авто-припуск +10 мм к высоте включён по умолчанию для ПВХ.
      expect(withoutAllowance.hasAutoHeightAllowance, isTrue);
      expect(withoutAllowance.autoHeightAllowanceMm, pvcHeightAllowanceMm);
      expect(withoutAllowance.hasAllowance, isTrue);
      expect(withoutAllowance.effectiveBottomWidth, 2000);
      expect(withoutAllowance.effectiveLeftHeight, 2010);
      // Припуск по ширине не трогает высоту и наоборот; по высоте авто
      // складывается с ручным.
      expect(measured.effectiveBottomWidth, 2120);
      expect(measured.effectiveTopWidth, 2120);
      expect(measured.effectiveLeftHeight, 2090);
      expect(measured.effectiveRightHeight, 2090);
      expect(measured.hasManualAllowance, isTrue);
      expect(measured.effectiveAllowanceHeightMm, 90);
    });

    test('геометрия строится по основным размерам: 2000×2000 + 100/+100', () {
      final geometry = WindowGeometry.of(product);

      expect(geometry.spanX, closeTo(2000, 1e-9));
      expect(geometry.overallHeight, closeTo(2000, 1e-9));
      expect(geometry.bottomWidth, closeTo(2000, 1e-9));
      expect(geometry.topWidth, closeTo(2000, 1e-9));
      expect(geometry.leftHeight, closeTo(2000, 1e-9));
      expect(geometry.rightHeight, closeTo(2000, 1e-9));
      expect(geometry.topOffset, 0);
      // Без припуска геометрия точно такая же.
      final plain = WindowGeometry.of(withoutAllowance);
      expect(geometry.spanX, closeTo(plain.spanX, 1e-9));
      expect(geometry.overallHeight, closeTo(plain.overallHeight, 1e-9));

      // Трапеция: припуск не сдвигает верх и не растягивает стороны.
      final trapezoid = WindowGeometry.of(measured.copyWith(
        bottomWidth: 3000,
        topWidth: 2400,
        leftHeight: 2500,
        rightHeight: 2500,
      ));
      expect(trapezoid.spanX, closeTo(3000, 1e-9));
      expect(trapezoid.overallHeight, closeTo(2500, 1e-9));
      expect(trapezoid.topOffset, closeTo(300, 1e-9));
    });

    test('площадь изделия не зависит от припуска', () {
      final plain = WindowSpec.of(withoutAllowance);
      final spec = WindowSpec.of(product);

      expect(spec.productAreaM2, closeTo(4.0, 1e-9));
      expect(spec.productAreaM2, closeTo(plain.productAreaM2, 1e-9));
      // Габарит изделия 2000 × 2000 = 4,00 м², а не 4,41 м².
      expect(
        spec.geometry.spanX * spec.geometry.overallHeight / 1e6,
        closeTo(4.0, 1e-9),
      );
    });

    test('плёнка в раскрое: напайка, припуск и авто +10 мм к высоте', () {
      final plain = WindowSpec.of(withoutAllowance);
      final spec = WindowSpec.of(product);

      // Окантовка 100 (готовая 50), напайка 25 → плёнка 2000 − 2×25 = 1950.
      expect(spec.filmCutWidth, closeTo(1950, 1e-9));
      expect(spec.filmCutHeight, closeTo(1950, 1e-9));
      // Площадь полотна изделия — без припуска.
      expect(spec.filmAreaM2, closeTo(1950 * 1950 / 1e6, 1e-9));
      expect(plain.filmAreaM2, closeTo(spec.filmAreaM2, 1e-9));
      // Заготовка к раскрою: припуск +100 по ширине и +100 вручную по высоте
      // плюс авто +10 мм к высоте для ПВХ → 2050 × 2060.
      expect(spec.filmCutWidthWithAllowance, closeTo(2050, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2060, 1e-9));
      // Усадка выключена — «с усадкой» совпадает с заготовкой.
      expect(spec.filmCutWidthWithShrinkage, closeTo(2050, 1e-9));
      expect(spec.filmCutHeightWithShrinkage, closeTo(2060, 1e-9));
      // Площадь заготовки к раскрою — с припуском, без вырезов.
      expect(spec.filmCutAreaM2, closeTo(2050 * 2060 / 1e6, 1e-9));
      expect(spec.filmAreaM2, lessThan(spec.filmCutAreaM2));

      // Включаем усадку 1,5 %: она считается от заготовки с припуском по
      // обеим сторонам, поэтому площадь — произведение усадочных сторон.
      final shrunk = WindowSpec.of(product.copyWith(
        shrinkageEnabled: true,
        shrinkagePercent: defaultShrinkagePercent,
      ));
      final factor = 1 + defaultShrinkagePercent / 100;
      expect(shrunk.filmCutWidthWithShrinkage, closeTo(2050 * factor, 1e-9));
      expect(shrunk.filmCutHeightWithShrinkage, closeTo(2060 * factor, 1e-9));
      expect(
        shrunk.filmCutAreaWithShrinkageM2,
        closeTo((2050 * factor) * (2060 * factor) / 1e6, 1e-9),
      );
      expect(
        shrunk.filmCutAreaWithShrinkageM2,
        greaterThan(shrunk.filmCutAreaM2 * factor),
      );
      // Площадь полотна и заготовка — разные числа: в подписях это
      // «площадь полотна» против «заготовки (габарит)».
      expect(shrunk.filmAreaM2, lessThan(shrunk.filmCutAreaWithShrinkageM2));
    });

    test('окантовка, люверсы, периметр и спайки не зависят от припуска', () {
      final plain = WindowSpec.of(withoutAllowance);
      final spec = WindowSpec.of(product);

      expect(spec.eyeletCount, plain.eyeletCount);
      expect(spec.eyeletStepMin, closeTo(plain.eyeletStepMin!, 1e-9));
      expect(spec.eyeletStepMax, closeTo(plain.eyeletStepMax!, 1e-9));
      expect(spec.eyeletStepLabel, plain.eyeletStepLabel);
      expect(spec.edgeConsumption, plain.edgeConsumption);
      expect(spec.edgeConsumptionLabels, plain.edgeConsumptionLabels);
      expect(spec.outerPerimeter, closeTo(plain.outerPerimeter, 1e-9));
      expect(spec.layers.weldLengthMm, closeTo(plain.layers.weldLengthMm, 1e-9));
      // Вырезы и их окантовка — по изделию.
      expect(spec.layers.cutoutPerimeterMm, plain.layers.cutoutPerimeterMm);
    });

    test('расход в CostsSummary растёт только по плёнке', () {
      final plain =
          CostsSummary(const OrderProject(windows: [withoutAllowance]));
      final cost = CostsSummary(const OrderProject(windows: [product]));

      // Площадь изделий не изменилась — припуск её не раздувает.
      expect(cost.productAreaM2, closeTo(plain.productAreaM2, 1e-9));
      expect(cost.productAreaM2, closeTo(4.0, 1e-9));
      // Плёнка выросла ровно на припуск: 2050 × 2060 против 1950 × 1960
      // (у окна без припуска высота тоже с авто +10 мм для ПВХ).
      expect(
        cost.filmAreaM2 - plain.filmAreaM2,
        closeTo((2050 * 2060 - 1950 * 1960) / 1e6, 1e-9),
      );
      expect(cost.filmAreaM2, closeTo(2050 * 2060 / 1e6, 1e-9));
      expect(
        cost.filmAreaByMaterial[FilmMaterial.clearPvc],
        closeTo(2050 * 2060 / 1e6, 1e-9),
      );
      // Плёнка в раскрое — заготовка с припуском, а не полотно изделия.
      expect(cost.filmAreaM2, greaterThan(WindowSpec.of(product).filmAreaM2));
      // Окантовка и люверсы — те же, что без припуска.
      expect(cost.edgeByRoll[100.0], closeTo(plain.edgeByRoll[100.0]!, 1e-9));
      expect(cost.eyeletTotal, plain.eyeletTotal);
      expect(cost.cutoutPerimeterMm, plain.cutoutPerimeterMm);
    });

    test('раскладка на рулоне не даёт отрицательного отхода', () {
      // Заготовка 2050 × 2050 (плюс усадка) шире стандартного рулона 2000:
      // раскладка предупреждает о сшивке, но отход не уходит в минус.
      final summary = CostsSummary(const OrderProject(windows: [product]));

      expect(summary.rollWastePercent, greaterThanOrEqualTo(0));
      expect(summary.rollWastePercent, lessThanOrEqualTo(100));
      for (final plan in summary.rollPlans) {
        expect(plan.wastePercent, greaterThanOrEqualTo(0));
        expect(plan.wastePercent, lessThanOrEqualTo(100));
      }
    });

    test('лист раскроя показывает заготовку с припуском', () {
      final spec = WindowSpec.of(product);
      final piece = CutPiece.ofSpec(spec);

      expect(piece.widthMm, closeTo(spec.filmCutWidthWithShrinkage, 1e-9));
      expect(piece.heightMm, closeTo(spec.filmCutHeightWithShrinkage, 1e-9));
      // Заготовка крупнее изделия на припуск (и на напайку с усадкой).
      expect(piece.widthMm, greaterThan(product.bottomWidth));
      expect(piece.heightMm, greaterThan(product.leftHeight));
      expect(piece.widthMm * piece.heightMm / 1e6, greaterThan(4.0));
      // Без припуска заготовка меньше — припуск реально входит в размер.
      final plainPiece = CutPiece.ofSpec(WindowSpec.of(withoutAllowance));
      expect(piece.widthMm, greaterThan(plainPiece.widthMm));
      expect(piece.heightMm, greaterThan(plainPiece.heightMm));
      expect(
        piece.widthMm - plainPiece.widthMm,
        closeTo(100 * (1 + product.shrinkagePercent / 100), 1e-9),
      );
    });

    test('припуски переживают JSON round-trip', () {
      final restored = windowFromJson(windowToJson(measured));
      expect(restored.allowanceWidthMm, 120);
      expect(restored.allowanceHeightMm, 80);
      expect(restored.pvcHeightAllowanceEnabled, isTrue);
      expect(restored.effectiveBottomWidth, 2120);
      expect(restored.effectiveLeftHeight, 2090);

      // Заказ целиком тоже.
      final project = orderFromJson(orderToJson(
        const OrderProject(windows: [measured, withoutAllowance]),
      ));
      expect(project.windows[0].allowanceWidthMm, 120);
      expect(project.windows[0].allowanceHeightMm, 80);
      expect(project.windows[1].allowanceWidthMm, 0);
      expect(project.windows[1].hasManualAllowance, isFalse);
      expect(project.windows[1].autoHeightAllowanceMm, pvcHeightAllowanceMm);

      // Старый JSON без полей припуска читается как «без ручного припуска»,
      // авто +10 мм для ПВХ остаётся включённым.
      final old = windowFromJson(const <String, dynamic>{
        'bottomWidth': 2000,
        'topWidth': 2000,
        'leftHeight': 2000,
        'rightHeight': 2000,
      });
      expect(old.allowanceWidthMm, 0);
      expect(old.allowanceHeightMm, 0);
      expect(old.pvcHeightAllowanceEnabled, isTrue);
      expect(old.autoHeightAllowanceMm, pvcHeightAllowanceMm);
    });

    test('припуск больше 500 мм и отрицательный — предупреждения', () {
      final tooBig = validateParams(measured.copyWith(allowanceWidthMm: 600));
      expect(
        tooBig.any((issue) =>
            issue.field == ParamField.allowanceWidth && !issue.isError),
        isTrue,
      );
      expect(hasBlockingIssues(tooBig), isFalse);
      expect(
        tooBig.any((issue) => issue.message.contains('Припуск на раскрой')),
        isTrue,
      );

      final negative = validateParams(measured.copyWith(allowanceHeightMm: -40));
      expect(
        negative.any((issue) =>
            issue.field == ParamField.allowanceHeight && !issue.isError),
        isTrue,
      );
      expect(hasBlockingIssues(negative), isFalse);

      // Нормальный припуск замечаний не вызывает.
      final normal = validateParams(measured);
      expect(
        normal.any((issue) => issue.message.contains('Припуск на раскрой')),
        isFalse,
      );
    });

    test('подписи припуска для документов', () {
      expect(formatSignedMm(120), '+120');
      expect(formatSignedMm(-30), formatMm(-30));
      // Высота в подписи — фактическая: ручная плюс авто +10 мм для ПВХ.
      expect(measured.allowanceLabel, 'припуск +120/+90 мм');
      expect(measured.manualAllowanceHeightLabel, '+80');
      expect(product.allowanceWidthLabel, '+100');
      expect(product.allowanceHeightLabel, '+110');
      expect(
        product.heightAllowanceBreakdownLabel,
        'Припуск по высоте: 10 мм (авто) + 100 мм (вручную) = 110 мм',
      );
    });

    test('примечания показывают замер и припуск', () {
      final notes = WindowSpec.of(product).notes.join('\n');
      expect(
        notes,
        contains('Припуск на раскрой: ширина +100 мм, высота +110 мм'),
      );
      expect(notes, contains('в том числе авто 10 мм к высоте для ПВХ'));
      expect(notes, contains('плёнка кроится 2\u202F050 × 2\u202F060 мм'));
      expect(notes, contains('усадка не учитывается'));

      final measuredNotes = WindowSpec.of(measured).notes.join('\n');
      expect(
        measuredNotes,
        contains('Припуск на раскрой: ширина +120 мм, высота +90 мм'),
      );
      expect(
        measuredNotes,
        contains('плёнка кроится 2\u202F070 × 2\u202F040 мм'),
      );

      // Даже без ручного припуска у ПВХ есть авто +10 мм к высоте.
      final plainNotes = WindowSpec.of(withoutAllowance).notes.join('\n');
      expect(
        plainNotes,
        contains('Припуск на раскрой: ширина 0 мм, высота +10 мм'),
      );
      expect(
        plainNotes,
        contains('плёнка кроится 1\u202F950 × 1\u202F960 мм'),
      );

      // У скрина авто-припуска нет: примечания не содержат «Припуск».
      final screenNotes = WindowSpec.of(const WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
      )).notes.join('\n');
      expect(screenNotes.contains('Припуск на раскрой'), isFalse);
    });

    testWidgets('чертёж показывает чистое изделие, припуск — в примечаниях',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(windows: [
                WindowParams(
                  bottomWidth: 2000,
                  topWidth: 2000,
                  leftHeight: 2000,
                  rightHeight: 2000,
                  weldOverlapMm: 25,
                  allowanceWidthMm: 120,
                  allowanceHeightMm: 80,
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Подпись окна и штамп — чистое изделие 2000 × 2000.
      expect(find.textContaining('2\u202F000×2\u202F000 мм'), findsWidgets);
      expect(
        find.textContaining('2\u202F000/2\u202F000 · 2\u202F000/2\u202F000'),
        findsWidgets,
      );
      // Старых записей «замер + припуск → размер» и «· припуск …» нет.
      expect(find.textContaining('2\u202F000 + 120'), findsNothing);
      expect(find.textContaining('2\u202F000 + 80'), findsNothing);
      expect(find.textContaining('припуск +120/+80 мм'), findsNothing);
      // Припуск виден только в примечаниях; высота — фактическая
      // (+80 вручную и +10 авто для ПВХ).
      expect(
        find.textContaining(
            'Припуск на раскрой: ширина +120 мм, высота +90 мм'),
        findsOneWidget,
      );
      expect(
        find.textContaining('плёнка кроится 2\u202F070 × 2\u202F040 мм'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

// --- Усадка ПВХ и авто-припуск +10 мм к высоте ------------------------------

/// Правки заказчика: усадка выключена по умолчанию и включается тумблером;
/// для ПВХ по умолчанию есть авто-припуск +10 мм к высоте заготовки, на скрин
/// он не действует; JSON читает и новые флаги, и старые заказы.
void _shrinkageAndPvcAllowanceRules() {
  group('Усадка ПВХ и авто-припуск +10 мм', () {
    // Пример заказчика: окно 2000 × 2500, окантовка 100 мм (готовая 50),
    // напуск 5 мм (значение по умолчанию).
    const pvc = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2500,
      rightHeight: 2500,
    );

    test('по умолчанию усадка выключена и равна 0 %', () {
      const params = WindowParams();
      expect(params.shrinkageEnabled, isFalse);
      expect(params.shrinkagePercent, 0);
      expect(params.effectiveShrinkagePercent, 0);
      expect(params.hasShrinkage, isFalse);
    });

    test('ПВХ по умолчанию: +10 мм к высоте заготовки → 1910 × 2420', () {
      final spec = WindowSpec.of(pvc);

      // Вручную. Ширина: 2000 − 50 − 50 + 2 × 5 = 1910 мм.
      // Высота до авто-припуска: 2500 − 50 − 50 + 2 × 5 = 2410 мм,
      // плюс +10 мм для ПВХ → 2420 мм.
      expect(pvc.autoHeightAllowanceMm, pvcHeightAllowanceMm);
      expect(spec.filmCutWidth, closeTo(1910, 1e-9));
      expect(spec.filmCutWidthWithAllowance, closeTo(1910, 1e-9));
      expect(spec.filmCutHeight, closeTo(2410, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2420, 1e-9));
      expect(spec.filmCutHeightWithShrinkage, closeTo(2420, 1e-9));
    });

    test('выключенный тумблер убирает +10 мм', () {
      final params = pvc.copyWith(pvcHeightAllowanceEnabled: false);
      final spec = WindowSpec.of(params);

      expect(params.autoHeightAllowanceMm, 0);
      expect(params.hasAutoHeightAllowance, isFalse);
      expect(spec.filmCutWidthWithAllowance, closeTo(1910, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2410, 1e-9));
    });

    test('для скрина авто-припуск не действует', () {
      final screen = pvc.copyWith(material: FilmMaterial.screen);
      final spec = WindowSpec.of(screen);

      expect(screen.isPvcFilm, isFalse);
      expect(screen.autoHeightAllowanceMm, 0);
      expect(screen.pvcHeightAllowanceEnabled, isTrue);
      // Заготовка скрина — готовый размер плюс удвоенный больший подворот.
      expect(
        spec.filmCutHeight,
        closeTo(2500 + 2 * defaultScreenHemMm, 1e-9),
      );
      expect(spec.filmCutHeightWithAllowance, closeTo(spec.filmCutHeight, 1e-9));
    });

    test('ручной припуск складывается с авто: 20 вручную → 30 по высоте', () {
      final params = pvc.copyWith(allowanceHeightMm: 20, allowanceWidthMm: 100);
      final spec = WindowSpec.of(params);

      expect(params.autoHeightAllowanceMm, pvcHeightAllowanceMm);
      expect(params.effectiveAllowanceHeightMm, 30);
      expect(params.allowanceHeightLabel, '+30');
      expect(params.manualAllowanceHeightLabel, '+20');
      expect(spec.filmCutWidthWithAllowance, closeTo(1910 + 100, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2410 + 30, 1e-9));
    });

    test('включение усадки 1,5 % повторяет прежнюю формулу раскроя', () {
      final params = pvc.copyWith(
        allowanceWidthMm: 100,
        allowanceHeightMm: 100,
        shrinkageEnabled: true,
        shrinkagePercent: defaultShrinkagePercent,
      );
      final spec = WindowSpec.of(params);

      // Заготовка до усадки: ширина 1910 + 100 = 2010;
      // высота 2410 + 100 (ручной) + 10 (авто ПВХ) = 2520.
      expect(spec.filmCutWidthWithAllowance, closeTo(2010, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2520, 1e-9));
      // Усадка 1,5 % по обеим сторонам: 2030,15 × 2545,2 мм.
      expect(spec.filmCutWidthWithShrinkage, closeTo(2010 * 1.015, 1e-9));
      expect(spec.filmCutHeightWithShrinkage, closeTo(2520 * 1.015, 1e-9));
      expect(
        spec.filmCutAreaWithShrinkageM2,
        closeTo((2010 * 1.015) * (2520 * 1.015) / 1000000, 1e-9),
      );
      // Площадь заготовки без усадки при этом не меняется.
      expect(spec.filmCutAreaM2, closeTo(2010 * 2520 / 1000000, 1e-9));
    });

    test('JSON round-trip: тумблеры, процент усадки и авто-припуск', () {
      final source = pvc.copyWith(
        shrinkageEnabled: true,
        shrinkagePercent: 2,
        pvcHeightAllowanceEnabled: false,
      );
      final restored = windowFromJson(windowToJson(source));

      expect(restored.shrinkageEnabled, isTrue);
      expect(restored.shrinkagePercent, 2);
      expect(restored.effectiveShrinkagePercent, 2);
      expect(restored.pvcHeightAllowanceEnabled, isFalse);
      expect(
        WindowSpec.of(restored).filmCutHeightWithShrinkage,
        closeTo(WindowSpec.of(source).filmCutHeightWithShrinkage, 1e-9),
      );
    });

    test('старый заказ с усадкой 1,5 % читается как «включена»', () {
      final old = windowFromJson(const <String, dynamic>{
        'bottomWidth': 2000,
        'topWidth': 2000,
        'leftHeight': 2000,
        'rightHeight': 2000,
        'shrinkagePercent': 1.5,
      });

      expect(old.shrinkageEnabled, isTrue);
      expect(old.shrinkagePercent, 1.5);
      expect(old.effectiveShrinkagePercent, 1.5);
    });

    test('старый заказ с нулевой усадкой читается как «выключена»', () {
      final old =
          windowFromJson(const <String, dynamic>{'shrinkagePercent': 0});

      expect(old.shrinkageEnabled, isFalse);
      expect(old.shrinkagePercent, 0);
      expect(old.effectiveShrinkagePercent, 0);
    });

    test('новый заказ с явным флагом false не включает усадку', () {
      final order = windowFromJson(const <String, dynamic>{
        'shrinkageEnabled': false,
        'shrinkagePercent': 1.5,
      });

      expect(order.shrinkageEnabled, isFalse);
      expect(order.shrinkagePercent, 1.5);
      expect(order.effectiveShrinkagePercent, 0);
    });

    test('технолог молчит про выключенную усадку и подсказывает про 4 %', () {
      // Проверки живут в services/tech_checks.dart; здесь — только модель.
      expect(pvc.copyWith(shrinkagePercent: 4).effectiveShrinkagePercent, 0);
      expect(
        pvc
            .copyWith(shrinkageEnabled: true, shrinkagePercent: 4)
            .effectiveShrinkagePercent,
        4,
      );
    });
  });
}

// --- Запайка плёнки под окантовку, мм (вводится руками) ---------------------

void _weldOverlapRules() {
  group('Запайка плёнки под окантовку', () {
    // Пример заказчика: готовое окно 2000 × 2000, окантовка 100 мм (готовая 50)
    // по бокам и низу, сверху 80 мм (готовая 40), запайка 10 мм.
    // Ширина заготовки: 2000 − 50 − 50 + 2 × 10 = 1920 мм.
    // Высота заготовки: 2000 − 50 (низ) − 40 (верх) + 2 × 10 = 1930 мм.
    const customer = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      rollBottom: 100,
      rollLeft: 100,
      rollRight: 100,
      rollTop: 80,
      weldOverlapMm: 10,
      shrinkagePercent: 0,
    );

    test('по умолчанию запайка 5 мм (подсов ПВХ), у окна своё поле', () {
      expect(const WindowParams().weldOverlapMm, defaultWeldOverlapMm);
      expect(defaultWeldOverlapMm, 5);
      expect(minWeldOverlapMm, 5);
      expect(maxWeldOverlapMm, 60);
      // Своё значение окна важнее значения по умолчанию.
      expect(const WindowParams(weldOverlapMm: 25).weldOverlapMm, 25);
    });

    test('контрольные числа: полосы 40/60 мм, напуск 5 мм → 1930 × 2400', () {
      // «Полоса» — готовая окантовка, а рулон складывается пополам: бок
      // 40 мм готовых — это рулон 80 мм, верх/низ 60 мм готовых — рулон 120.
      // Напуск не задаём: он берётся по умолчанию (5 мм, подсов ПВХ).
      // Припуск 0 и усадка 0, но авто +10 мм к высоте для ПВХ включён:
      // 2500 − 120 + 10 (напуск) + 10 (авто) = 2400 мм.
      const control = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2500,
        rightHeight: 2500,
        rollBottom: 120,
        rollTop: 120,
        rollLeft: 80,
        rollRight: 80,
        shrinkagePercent: 0,
      );
      expect(control.weldOverlapMm, defaultWeldOverlapMm);
      expect(control.weldOverlapMm, 5);
      expect(control.allowanceWidthMm, 0);
      expect(control.allowanceHeightMm, 0);
      expect(control.effectiveShrinkagePercent, 0);
      expect(control.pvcHeightAllowanceEnabled, isTrue);

      final spec = WindowSpec.of(control);

      // Ширина: 2000 − 40 − 40 + 2 × 5 = 1930 мм (совпадает с заказчиком).
      expect(spec.filmCutWidth, closeTo(2000 - 80 + 10, 1e-9));
      expect(spec.filmCutWidth, closeTo(1930, 1e-9));
      // Высота заготовки: 2500 − 60 − 60 + 2 × 5 = 2390 мм, плюс авто
      // +10 мм для ПВХ (см. [pvcHeightAllowanceMm]) → 2400 мм.
      expect(spec.filmCutHeight, closeTo(2500 - 120 + 10, 1e-9));
      expect(spec.filmCutHeight, closeTo(2390, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2400, 1e-9));
      // Заготовка к раскрою без усадки: ширина 1930, высота 2400.
      expect(spec.filmCutWidthWithShrinkage, closeTo(1930, 1e-9));
      expect(spec.filmCutHeightWithShrinkage, closeTo(2400, 1e-9));

      // С выключенным тумблером авто-припуска высота снова 2390 мм.
      final off = WindowSpec.of(control.copyWith(
        pvcHeightAllowanceEnabled: false,
      ));
      expect(off.filmCutWidthWithShrinkage, closeTo(1930, 1e-9));
      expect(off.filmCutHeightWithShrinkage, closeTo(2390, 1e-9));
    });

    test('пример заказчика: запайка 10 мм даёт заготовку 1920 × 1930', () {
      final spec = WindowSpec.of(customer);

      expect(spec.filmVisibleWidth, closeTo(1900, 1e-9));
      expect(spec.filmVisibleHeight, closeTo(1910, 1e-9));
      expect(spec.filmCutWidth, closeTo(1920, 1e-9));
      expect(spec.filmCutHeight, closeTo(1930, 1e-9));
      // Формула: готовый размер − 2 × окантовка + 2 × запайка.
      expect(spec.filmCutWidth, closeTo(2000 - 100 + 20, 1e-9));
      expect(spec.filmCutHeight, closeTo(2000 - 90 + 20, 1e-9));
    });

    test('запайка влияет только на заготовку, изделие не меняется', () {
      final thin = WindowSpec.of(customer.copyWith(weldOverlapMm: 5));
      final thick = WindowSpec.of(customer.copyWith(weldOverlapMm: 40));

      expect(thin.productAreaM2, closeTo(thick.productAreaM2, 1e-9));
      // Заготовка = готовый размер − 2 × окантовка + 2 × запайка:
      // 1900 + 2 × 5 = 1910 и 1900 + 2 × 40 = 1980.
      expect(thin.filmCutWidth, closeTo(1910, 1e-9));
      expect(thick.filmCutWidth, closeTo(1980, 1e-9));
      expect(thick.filmCutWidth - thin.filmCutWidth, closeTo(2 * 35, 1e-9));
      expect(thick.filmCutHeight - thin.filmCutHeight,
          closeTo(2 * 35, 1e-9));
    });

    test('валидация: запайка вне 5…60 мм — замечание', () {
      final issues = validateParams(customer.copyWith(weldOverlapMm: 80));
      expect(
        issues.any((issue) => issue.field == ParamField.weldOverlap),
        isTrue,
      );
      final ok = validateParams(customer);
      expect(
        ok.any((issue) => issue.field == ParamField.weldOverlap),
        isFalse,
      );
    });
  });
}

// --- Скрин: самостоятельная технология без тента -----------------------------

void _screenRules() {
  group('Скрин', () {
    WindowParams screenWith(double hem, {bool pocket = false, bool top = false}) =>
        WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: hem,
          hemRightMm: hem,
          hemTopMm: hem,
          hemLeftMm: hem,
          pocket: pocket,
          pocketTop: top,
        );

    /// Скрин с разными подворотами по сторонам: низ, право, верх, лево.
    WindowParams screenWithSides(
      double bottom,
      double right,
      double top,
      double left,
    ) =>
        WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: bottom,
          hemRightMm: right,
          hemTopMm: top,
          hemLeftMm: left,
        );

    test('технология выводится из материала, а не из отдельного поля', () {
      expect(const WindowParams().isScreen, isFalse);
      expect(const WindowParams().tech, WindowTech.pvcTent);
      final screen = screenWith(40);
      expect(screen.isScreen, isTrue);
      expect(screen.tech, WindowTech.screen);
      // Смена материала переключает технологию.
      expect(screen.copyWith(material: FilmMaterial.clearPvc).tech,
          WindowTech.pvcTent);
    });

    test('одинаковый подворот 40/50/60: заготовка 2080 / 2100 / 2120', () {
      // Одинаковый подворот на все стороны: по оси берётся удвоенный больший,
      // а подвороты равны — заготовка = 2000 + 2 × подворот.
      for (final (hem, blank) in [(40.0, 2080.0), (50.0, 2100.0), (60.0, 2120.0)]) {
        final spec = WindowSpec.of(screenWith(hem));
        expect(spec.filmCutWidth, closeTo(blank, 1e-9),
            reason: 'подворот $hem мм');
        expect(spec.filmCutHeight, closeTo(blank, 1e-9));
        // Готовое изделие остаётся 2000 × 2000.
        expect(spec.productAreaM2, closeTo(4.0, 1e-9));
        expect(spec.filmVisibleWidth, closeTo(2000, 1e-9));
      }
      expect(screenHemPresets, [40, 50, 60]);
      expect(screenSeamMm, 3);
    });

    test('контрольные числа: подворот бок 40, верх/низ 60 → 2080 × 2120', () {
      // Скрин 2000 × 2000: ширина = 2000 + 2 × max(лево 40, право 40) = 2080 мм;
      // высота = 2000 + 2 × max(низ 60, верх 60) = 2120 мм.
      final spec = WindowSpec.of(screenWithSides(60, 40, 60, 40));

      expect(spec.filmCutWidth, closeTo(2000 + 2 * 40, 1e-9));
      expect(spec.filmCutWidth, closeTo(2080, 1e-9));
      expect(spec.filmCutHeight, closeTo(2000 + 2 * 60, 1e-9));
      expect(spec.filmCutHeight, closeTo(2120, 1e-9));
      // Готовое изделие не изменилось, запайки у скрина нет.
      expect(spec.productAreaM2, closeTo(4.0, 1e-9));
      expect(spec.edgeConsumption, isEmpty);
    });

    test('заказчик: (низ 40, верх 60, лево 40, право 40) → 2080 × 2120', () {
      // Главное требование заказчика: 40 + 60 = 100, но к высоте
      // прибавляется 120 мм — по удвоенному БОЛЬШЕМУ подвороту оси (верх 60).
      final params = screenWithSides(40, 40, 60, 40);
      final spec = WindowSpec.of(params);

      expect(params.hemAxisBottomTopIncrease, closeTo(120, 1e-9));
      expect(params.hemAxisLeftRightIncrease, closeTo(80, 1e-9));
      expect(spec.filmCutWidth, closeTo(2080, 1e-9));
      expect(spec.filmCutHeight, closeTo(2120, 1e-9));
      expect(spec.filmCutWidthWithAllowance, closeTo(2080, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(2120, 1e-9));
    });

    test('(низ 60, верх 60) → высота 2120 — как в прежнем примере', () {
      final spec = WindowSpec.of(screenWithSides(60, 40, 60, 40));
      expect(spec.filmCutHeight, closeTo(2120, 1e-9));
      expect(
        spec.filmCutHeight - spec.params.hemAxisBottomTopIncrease,
        closeTo(2000, 1e-9),
      );
    });

    test('(низ 40, верх 40, лево 40, право 40) → 2080 × 2080', () {
      final spec = WindowSpec.of(screenWithSides(40, 40, 40, 40));
      expect(spec.filmCutWidth, closeTo(2080, 1e-9));
      expect(spec.filmCutHeight, closeTo(2080, 1e-9));
    });

    test('берётся максимум, а не верх: (низ 70, верх 50) → высота 2140', () {
      final spec = WindowSpec.of(screenWithSides(70, 40, 50, 40));
      // 2000 + 2 × max(70, 50) = 2000 + 140 = 2140.
      expect(spec.filmCutHeight, closeTo(2000 + 140, 1e-9));
      expect(spec.filmCutHeight, closeTo(2140, 1e-9));
    });

    test('берётся максимум по ширине: (лево 30, право 90) → 2180', () {
      final spec = WindowSpec.of(screenWithSides(40, 90, 40, 30));
      // 2000 + 2 × max(30, 90) = 2000 + 180 = 2180.
      expect(spec.filmCutWidth, closeTo(2000 + 180, 1e-9));
      expect(spec.filmCutWidth, closeTo(2180, 1e-9));
    });

    test('человеческие формулы заготовки: «2000 + 2 × 60 (верх) = 2120»', () {
      final spec = WindowSpec.of(screenWithSides(40, 40, 60, 40));
      expect(
        spec.screenBlankHeightFormulaLabel,
        'Высота: ${formatMm(2000)} + 2 × ${formatMm(60)} (верх) = '
        '${formatMm(2120)} мм',
      );
      expect(
        spec.screenBlankWidthFormulaLabel,
        'Ширина: ${formatMm(2000)} + 2 × ${formatMm(40)} = '
        '${formatMm(2080)} мм',
      );
      // Победившая сторона подписывается: по ширине больше право.
      final right = WindowSpec.of(screenWithSides(40, 90, 40, 30));
      expect(
        right.screenBlankWidthFormulaLabel,
        'Ширина: ${formatMm(2000)} + 2 × ${formatMm(90)} (право) = '
        '${formatMm(2180)} мм',
      );
      // По высоте больше низ — подписывается низ.
      final bottom = WindowSpec.of(screenWithSides(70, 40, 50, 40));
      expect(
        bottom.screenBlankHeightFormulaLabel,
        'Высота: ${formatMm(2000)} + 2 × ${formatMm(70)} (низ) = '
        '${formatMm(2140)} мм',
      );
      // Припуск на раскрой — отдельным слагаемым.
      final withAllowance = WindowSpec.of(
        screenWithSides(40, 40, 60, 40)
            .copyWith(allowanceWidthMm: 20, allowanceHeightMm: 30),
      );
      expect(
        withAllowance.screenBlankHeightFormulaLabel,
        'Высота: ${formatMm(2000)} + 2 × ${formatMm(60)} (верх) + припуск '
        '${formatMm(30)} = ${formatMm(2150)} мм',
      );
      expect(
        withAllowance.screenBlankWidthFormulaLabel,
        'Ширина: ${formatMm(2000)} + 2 × ${formatMm(40)} + припуск '
        '${formatMm(20)} = ${formatMm(2100)} мм',
      );
    });

    test('Подворот 25 мм на все стороны — заготовка 2050 × 2050', () {
      final params = screenWithSides(25, 25, 25, 25);
      final spec = WindowSpec.of(params);
      expect(params.hemWidths, [25, 25, 25, 25]);
      expect(params.hemTotalMm, closeTo(100, 1e-9));
      expect(params.hasUniformHem, isTrue);
      expect(spec.filmCutWidth, closeTo(2050, 1e-9));
      expect(spec.filmCutHeight, closeTo(2050, 1e-9));
    });

    test('смешанные подвороты: по каждой оси — удвоенный максимум', () {
      // Низ 40, право 50, верх 60, лево 40 мм.
      final params = screenWithSides(40, 50, 60, 40);
      final spec = WindowSpec.of(params);

      // Ширина заготовки = bottomWidth + 2 × max(лево 40, право 50) = 2100 мм.
      expect(spec.filmCutWidth, closeTo(2000 + 2 * 50, 1e-9));
      expect(spec.filmCutWidth, closeTo(2100, 1e-9));
      // Высота заготовки = leftHeight + 2 × max(низ 40, верх 60) = 2120 мм.
      expect(spec.filmCutHeight, closeTo(2000 + 2 * 60, 1e-9));
      expect(spec.filmCutHeight, closeTo(2120, 1e-9));
      expect(params.hemForSide(EdgeSide.bottom), 40);
      expect(params.hemForSide(EdgeSide.right), 50);
      expect(params.hemForSide(EdgeSide.top), 60);
      expect(params.hemForSide(EdgeSide.left), 40);
      expect(params.hemForEdge(0), 40);
      expect(params.hemForEdge(1), 50);
      expect(params.hemForEdge(2), 60);
      expect(params.hemForEdge(3), 40);
      expect(params.hemTotalMm, closeTo(190, 1e-9));
      expect(params.hasUniformHem, isFalse);
      // Готовое изделие не изменилось: подворот уходит на изнанку.
      expect(spec.productAreaM2, closeTo(4.0, 1e-9));
    });

    test('подворот по сторонам читается во всех подписях', () {
      final params = screenWithSides(40, 50, 60, 40);
      final spec = WindowSpec.of(params);
      expect(spec.edgeBySideSummary,
          contains(params.hemBySideLabel));
      expect(spec.edgeBySideSummary, contains('низ 40'));
      expect(spec.edgeBySideSummary, contains('право 50'));
      expect(spec.edgeBySideSummary, contains('верх 60'));
      expect(spec.edgeBySideSummary, contains('лево 40'));
      expect(spec.edgeSummary, contains(params.hemBySideShortLabel));
      expect(params.hemBySideShortLabel, '40/50/60/40 мм');
    });

    test('у скрина нет усадки и нет авто-припуска: 2080 × 2080', () {
      final spec = WindowSpec.of(screenWith(40));
      // Скрин — не ПВХ: ни усадки, ни авто-припуска +10 мм к высоте.
      expect(spec.params.isPvcFilm, isFalse);
      expect(spec.params.effectiveShrinkagePercent, 0);
      expect(spec.params.autoHeightAllowanceMm, 0);
      expect(spec.filmCutWidthWithShrinkage, closeTo(2080, 1e-9));
      expect(spec.filmCutHeightWithShrinkage, closeTo(2080, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(4.3264, 1e-9));
    });

    test('усадка скрину не задаётся даже при включённом тумблере', () {
      final params = screenWith(40).copyWith(
        shrinkageEnabled: true,
        shrinkagePercent: 2,
      );
      final spec = WindowSpec.of(params);
      expect(spec.params.effectiveShrinkagePercent, 0);
      expect(spec.filmCutHeightWithShrinkage, closeTo(2080, 1e-9));
    });

    test('окантовки нет: расход нулевой, готовая полоса нулевая', () {
      final spec = WindowSpec.of(screenWith(40));
      expect(spec.edgeConsumption, isEmpty);
      expect(spec.edgeConsumptionLabels, isEmpty);
      expect(spec.layers.finishedWidths, [0, 0, 0, 0]);
      expect(spec.layers.rolls, [0, 0, 0, 0]);
      expect(spec.edgeBySideSummary, contains('подворот'));
    });

    test('линия подворота и шов 3 мм внутри неё', () {
      final spec = WindowSpec.of(screenWith(40));
      final hem = spec.layers.screenHemLine;
      final seam = spec.layers.screenSeamLine;

      expect(hem, hasLength(4));
      expect(seam, hasLength(4));
      // Линия подворота совпадает с готовым контуром 2000 × 2000.
      expect(hem[0].dx, closeTo(0, 1e-6));
      expect(hem[0].dy, closeTo(0, 1e-6));
      expect(hem[1].dx, closeTo(2000, 1e-6));
      expect(hem[2].dy, closeTo(2000, 1e-6));
      // Шов — на 3 мм внутри линии подворота.
      expect(seam[0].dx, closeTo(screenSeamMm, 1e-6));
      expect(seam[0].dy, closeTo(screenSeamMm, 1e-6));
      expect(seam[1].dx, closeTo(2000 - screenSeamMm, 1e-6));
    });

    test('люверсы ставятся по линии подворота, крепёж — по низу и бокам', () {
      final params = screenWith(40).copyWith(
        windowType: WindowType.lifting,
        fastenerType: FastenerType.frenchLocks,
        drainHoles: true,
      );
      final spec = WindowSpec.of(params);

      // Скрин — съёмное полотно: крепёж ставится по низу и бокам, как у
      // подъёмного ПВХ-окна, а не игнорируется.
      expect(spec.layers.movableSideEyelets, isNotEmpty);
      expect(
        spec.layers.movableSideEyelets
            .every((eyelet) => eyelet.side != WindowSide.top),
        isTrue,
        reason: 'верх остаётся на саморезах',
      );
      expect(
        spec.layers.movableSideEyelets.any((eyelet) => eyelet.isCorner),
        isFalse,
        reason: 'в углах круглые люверсы, а не замок',
      );
      expect(spec.layers.drainHoles, isEmpty);
      expect(spec.strapCount, 0);
      expect(spec.fastenerSummary, contains('французский замок'));
      expect(spec.fastenerSummary, contains('по подвороту'));
      expect(spec.fastenerSummary, contains('Сверху саморезы'));
      expect(spec.eyeletCount, greaterThan(0));
      // Все люверсы лежат на линии подворота — на наружном контуре 2000 × 2000.
      for (final eyelet in spec.layers.eyelets) {
        final onOuter = eyelet.center.dx.abs() < 1e-6 ||
            (eyelet.center.dx - 2000).abs() < 1e-6 ||
            eyelet.center.dy.abs() < 1e-6 ||
            (eyelet.center.dy - 2000).abs() < 1e-6;
        expect(onOuter, isTrue, reason: 'люверс ${eyelet.center} не на подвороте');
      }
    });

    test('скрин со скобами: крепёж по низу и бокам, в углах круглые люверсы', () {
      final params = screenWith(40).copyWith(
        fastenerType: FastenerType.turnBuckles,
      );
      final spec = WindowSpec.of(params);

      // Тип окна не важен: глухой скрин тоже получает крепёж.
      expect(params.windowType, WindowType.fixed);
      expect(spec.layers.movableSideEyelets, isNotEmpty);
      final sides = spec.layers.movableSideEyelets
          .map((eyelet) => eyelet.side)
          .toSet();
      expect(sides, isNot(contains(WindowSide.top)));
      expect(spec.layers.movableSideEyelets.any((eyelet) => eyelet.isCorner),
          isFalse);
      expect(spec.fastenerSummary, contains('поворотные скобы'));
      expect(spec.fastenerSummary, contains('по подвороту'));
      // Угловые люверсы остаются круглыми.
      final corners =
          spec.layers.eyelets.where((eyelet) => eyelet.isCorner).toList();
      expect(corners, isNotEmpty);
      for (final corner in corners) {
        expect(spec.layers.typeFor(corner), EyeletType.round10);
      }
    });

    test('скрин с ремнями и скрин «только люверсы»', () {
      final straps = WindowSpec.of(
        screenWith(40).copyWith(
          fastenerType: FastenerType.straps,
          windowType: WindowType.lifting,
        ),
      );
      expect(straps.fastenerSummary, contains('силиконовые ремни'));
      expect(straps.layers.movableSideEyelets, isNotEmpty);

      final eyeletsOnly = WindowSpec.of(
        screenWith(40).copyWith(fastenerType: FastenerType.eyeletsOnly),
      );
      expect(eyeletsOnly.fastenerSummary, contains('Только люверсы'));
      expect(eyeletsOnly.fastenerSummary, contains('по подвороту'));
      expect(eyeletsOnly.fastenerSummary,
          isNot(contains('поворотные скобы')));
    });

    test('JSON хранит тип крепежа скрина и читает его обратно', () {
      for (final type in FastenerType.values) {
        final params = screenWithSides(40, 50, 60, 40)
            .copyWith(fastenerType: type, windowType: WindowType.lifting);
        final restored = windowFromJson(windowToJson(params));
        expect(restored.fastenerType, type, reason: 'тип крепежа $type');
        expect(restored.isScreen, isTrue);
        final original = WindowSpec.of(params);
        final restoredSpec = WindowSpec.of(restored);
        expect(restoredSpec.fastenerSummary, original.fastenerSummary);
        expect(restoredSpec.layers.movableSideEyelets.length,
            original.layers.movableSideEyelets.length);
      }
    });

    test('JSON хранит подвороты по сторонам и читает их обратно', () {
      final json = windowToJson(
        screenWithSides(40, 50, 60, 25).copyWith(weldOverlapMm: 15),
      );
      final restored = windowFromJson(json);

      expect(restored.material, FilmMaterial.screen);
      expect(restored.hemBottomMm, 40);
      expect(restored.hemRightMm, 50);
      expect(restored.hemTopMm, 60);
      expect(restored.hemLeftMm, 25);
      expect(restored.hemWidths, [40, 50, 60, 25]);
      expect(restored.weldOverlapMm, 15);
      expect(restored.isScreen, isTrue);
      // Разные подвороты — старое одиночное поле не пишем.
      expect(json.containsKey('hemMm'), isFalse);
    });

    test('JSON: одинаковый подворот пишется и старым полем hemMm', () {
      final json = windowToJson(screenWith(50));
      expect(json['hemMm'], 50);
      expect(json['hemBottomMm'], 50);
      expect(json['hemRightMm'], 50);
      expect(json['hemTopMm'], 50);
      expect(json['hemLeftMm'], 50);
    });

    test('JSON: старый заказ с одиночным hemMm читается на все стороны', () {
      final legacy = {
        'material': 'screen',
        'bottomWidth': 2000,
        'topWidth': 2000,
        'leftHeight': 2000,
        'rightHeight': 2000,
        'hemMm': 60,
      };
      final restored = windowFromJson(legacy);
      expect(restored.hemBottomMm, 60);
      expect(restored.hemRightMm, 60);
      expect(restored.hemTopMm, 60);
      expect(restored.hemLeftMm, 60);
      expect(restored.hasUniformHem, isTrue);
      // Новые поля имеют приоритет над старым.
      final partial = Map<String, dynamic>.from(legacy)
        ..['hemTopMm'] = 25;
      expect(windowFromJson(partial).hemTopMm, 25);
      expect(windowFromJson(partial).hemBottomMm, 60);
    });

    test('валидация: подворот вне обычного диапазона — замечание', () {
      final issues = validateParams(screenWith(200));
      expect(
        issues.any((issue) =>
            issue.field == ParamField.hemBottom && !issue.isError),
        isTrue,
      );
      // Замечание адресуется каждой стороне отдельно.
      for (final side in EdgeSide.values) {
        expect(
          issues.any((issue) => issue.field == hemFieldForSide(side)),
          isTrue,
          reason: 'нет замечания по стороне ${side.label}',
        );
      }
      // Окантовка скрину не проверяется вовсе.
      expect(
        issues.any((issue) => issue.message.contains('Окантовка,')),
        isFalse,
      );
    });
  });
}

// --- Карман снизу и сверху ---------------------------------------------------

void _pocketRules() {
  group('Карманы снизу и сверху', () {
    const base = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
    );

    test('карман только снизу: подняты нижние угловые люверсы', () {
      final params = base.copyWith(pocket: true, pocketWidth: 100);
      final layers = WindowLayers(params, WindowGeometry.of(params));

      expect(layers.pocketRect.isEmpty, isFalse);
      expect(layers.pocketTopRect.isEmpty, isTrue);
      final bottom = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.bottom)
          .toList();
      expect(bottom.length, 6);
      final rightLowest = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.right)
          .reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      expect(rightLowest.center.dy, closeTo(75, 0.02));
    });

    test('карман только сверху: опущены верхние угловые люверсы', () {
      final params = base.copyWith(pocketTop: true, pocketWidth: 100);
      final geometry = WindowGeometry.of(params);
      final layers = WindowLayers(params, geometry);

      expect(layers.pocketRect.isEmpty, isTrue);
      expect(layers.pocketTopRect.isEmpty, isFalse);
      // Полоса идёт от верхней кромки изделия вверх: 1500 → 1600 мм.
      expect(layers.pocketTopRect.top, closeTo(1500, 0.01));
      expect(layers.pocketTopRect.bottom, closeTo(1600, 0.01));
      // Верхний карман расширяет лист, но не габарит изделия.
      expect(geometry.pocketTopRise, 100);
      expect(geometry.spanY, closeTo(1600, 0.01));
      expect(geometry.overallHeight, closeTo(1500, 0.01));

      final top = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.top)
          .toList();
      expect(top.length, 6);
      final rightHighest = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.right)
          .reduce((a, b) => a.center.dy > b.center.dy ? a : b);
      expect(rightHighest.center.dy, closeTo(1500 - 75, 0.02));
    });

    test('оба кармана: симметрично убраны углы снизу и сверху', () {
      final params = base.copyWith(
        pocket: true,
        pocketTop: true,
        pocketWidth: 100,
      );
      final geometry = WindowGeometry.of(params);
      final layers = WindowLayers(params, geometry);

      expect(layers.pocketRect.isEmpty, isFalse);
      expect(layers.pocketTopRect.isEmpty, isFalse);
      expect(geometry.minY, closeTo(-100, 0.01));
      expect(geometry.spanY, closeTo(1700, 0.01));

      final right = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.right)
          .toList();
      final lowest =
          right.reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      final highest =
          right.reduce((a, b) => a.center.dy > b.center.dy ? a : b);
      expect(lowest.center.dy, closeTo(75, 0.02));
      expect(highest.center.dy, closeTo(1500 - 75, 0.02));
    });

    test('расход и подписи: карманы считаются оба', () {
      const project = OrderProject(windows: [
        WindowParams(
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 1500,
          rightHeight: 1500,
          pocket: true,
          pocketTop: true,
          pocketWidth: 100,
        ),
      ]);
      final summary = CostsSummary(project);

      expect(summary.pocketCount, 2);
      expect(summary.pocketLengthMm, closeTo(4000, 1e-9));
      expect(
        summary.extraLabels.any((label) => label.contains('Карман')),
        isTrue,
      );
      final notes = WindowSpec.of(project.windows.first).notes.join('\n');
      expect(notes, contains('снизу и сверху'));
      // Верхний карман тоже попадает в расход материала.
      expect(summary.filmAreaM2, greaterThan(0));
    });
  });
}

// --- Ширины рулонов скрина --------------------------------------------------

void _rollWidthRules() {
  group('Ширины рулонов скрина', () {
    test('в списке скрина есть 2500 и 5000 мм, предел — 5000', () {
      expect(
        FilmMaterial.screen.rollWidths,
        [1400, 1800, 2000, 2400, 2500, 2600, 5000],
      );
      // Прежние ширины сохранены, добавились две новые.
      for (final width in [1400, 1800, 2000, 2400, 2600]) {
        expect(FilmMaterial.screen.rollWidths, contains(width));
      }
      expect(FilmMaterial.screen.rollWidths, contains(2500));
      expect(FilmMaterial.screen.rollWidths, contains(5000));
      expect(FilmMaterial.screen.maxRollWidth, 5000);
      // По умолчанию по-прежнему 2000 мм.
      expect(FilmMaterial.screen.defaultRollWidth, 2000);
      // Список отсортирован: из него строятся чипы панели.
      final sorted = [...FilmMaterial.screen.rollWidths]..sort();
      expect(FilmMaterial.screen.rollWidths, orderedEquals(sorted));
      // Подпись доступных рулонов показывает новые ширины в сантиметрах.
      expect(FilmMaterial.screen.rollWidthsLabel, contains('250'));
      expect(FilmMaterial.screen.rollWidthsLabel, contains('500'));
      // Панель берёт список из материала окна.
      expect(
        const WindowParams(material: FilmMaterial.screen).availableRollWidths,
        contains(5000),
      );
    });

    test('выбор ширины 2500 и 5000 мм сохраняется в JSON и читается обратно', () {
      const project = OrderProject();
      for (final width in [2500.0, 5000.0]) {
        final chosen = project
            .updateSelected(const WindowParams(material: FilmMaterial.screen))
            .setRollWidth(FilmMaterial.screen, width);

        expect(chosen.rollWidthFor(FilmMaterial.screen), width);
        final json = orderToJson(chosen);
        expect(json['rollWidths'], isA<Map<String, dynamic>>());

        final restored = orderFromJson(json);
        expect(restored.rollWidths[FilmMaterial.screen], width);
        expect(restored.rollWidthFor(FilmMaterial.screen), width);
        expect(restored.windows.first.material, FilmMaterial.screen);
      }
    });

    test('раскладка на рулоне пользуется новой шириной', () {
      // Скрин 4000 × 2000: заготовка 4080 × 2080 шире рулона 2000 мм.
      const screen = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 4000,
        topWidth: 4000,
        leftHeight: 2000,
        rightHeight: 2000,
        hemBottomMm: 40,
        hemRightMm: 40,
        hemTopMm: 40,
        hemLeftMm: 40,
      );
      const project = OrderProject(windows: [screen]);

      final narrow = CostsSummary(project).rollPlans.single;
      expect(narrow.rollWidth, 2000);
      expect(narrow.layout.warnings, isNotEmpty,
          reason: 'заготовка 4080 мм шире рулона 2000 мм');

      final wide =
          CostsSummary(project.setRollWidth(FilmMaterial.screen, 5000))
              .rollPlans
              .single;
      expect(wide.rollWidth, 5000);
      expect(wide.layout.warnings, isEmpty);
      expect(wide.layout.placements.single.width, lessThanOrEqualTo(5000));
    });
  });
}

// --- Стороны без люверсов ---------------------------------------------------

void _eyeletlessSideRules() {
  group('Стороны без люверсов', () {
    // Окно 2000 × 1500, окантовка 100 мм (линия люверсов 1950 × 1450),
    // шаг 300 мм: 24 люверса, из них внизу 8 (оба нижних угла — её),
    // справа 5, сверху 7 (левый верхний угол — её), слева 4.
    WindowParams base({bool top = false, bool bottom = false}) => WindowParams(
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 1500,
          rightHeight: 1500,
          noEyeletsTop: top,
          noEyeletsBottom: bottom,
        );

    WindowLayers layersOf(WindowParams params) =>
        WindowLayers(params, WindowGeometry.of(params));

    test('по умолчанию стороны без люверсов не выключаются', () {
      final params = base();
      expect(params.hasEyeletlessSides, isFalse);
      expect(params.eyeletlessSides, isEmpty);
      expect(params.noEyeletsTop, isFalse);
      expect(params.noEyeletsBottom, isFalse);
      expect(layersOf(params).eyeletCount, 24);
    });

    test('только сверху: минус 7 люверсов, оба верхних угла уходят', () {
      final params = base(top: true);
      final layers = layersOf(params);

      // Сверху было 7 (её левый верхний угол + 6 промежуточных) — их нет.
      expect(layers.eyeletCount, 17);
      expect(layers.eyelets.any((e) => e.side == WindowSide.top), isFalse);
      // Нижние стороны сохранили свои углы.
      expect(
        layers.eyelets.where((e) => e.side == WindowSide.bottom).length,
        8,
      );
      // Правый верхний угол принадлежит правой стороне — он остаётся.
      expect(
        layers.eyelets.any((e) =>
            e.side == WindowSide.right &&
            (e.center.dy - 1475).abs() < 1 &&
            (e.center.dx - 1975).abs() < 1),
        isTrue,
        reason: 'соседняя сторона свои углы сохраняет',
      );
      // В фактический интервал попали только три стороны с люверсами.
      expect(layers.eyeletSteps, hasLength(3));
      expect(params.eyeletlessSides, [EdgeSide.top]);
      expect(params.eyeletlessSidesLabel, 'верх');
      expect(layers.eyeletlessSidesLabel, 'верх');
    });

    test('только снизу: минус 8 люверсов вместе с нижними углами', () {
      final layers = layersOf(base(bottom: true));

      expect(layers.eyeletCount, 16);
      expect(layers.eyelets.any((e) => e.side == WindowSide.bottom), isFalse);
      // Верхние углы остаются: правый — у правой стороны, левый — у верхней.
      expect(layers.eyelets.any((e) => e.side == WindowSide.top), isTrue);
      expect(layers.eyeletSteps, hasLength(3));
      expect(base(bottom: true).eyeletlessSidesLabel, 'низ');
    });

    test('обе стороны: 24 − 8 − 7 = 9 люверсов, по 5 и 4 на боках', () {
      final params = base(top: true, bottom: true);
      final layers = layersOf(params);

      expect(layers.eyeletCount, 9);
      expect(
        layers.eyelets.where((e) => e.side == WindowSide.right).length,
        5,
      );
      expect(
        layers.eyelets.where((e) => e.side == WindowSide.left).length,
        4,
      );
      expect(layers.eyeletSteps, hasLength(2));
      expect(params.eyeletlessSidesLabel, 'низ и верх');
      expect(layers.eyeletlessSidesLabel, 'низ и верх');
    });

    test('расход и подписи честно уменьшаются', () {
      final plain = WindowSpec.of(base());
      final topOff = WindowSpec.of(base(top: true));
      final summary =
          CostsSummary(OrderProject(windows: [base(top: true), base()]));

      expect(plain.eyeletCount, 24);
      expect(topOff.eyeletCount, 17);
      // Расход люверсов по заказу: 17 + 24 = 41, по типу — все круглые.
      expect(summary.eyeletTotal, 41);
      // Примечания чертежа называют сторону без люверсов.
      expect(topOff.notes.join('\n'), contains('без люверсов: верх'));
    });

    test('JSON round-trip: обе кнопки читаются обратно', () {
      final json = windowToJson(base(top: true, bottom: true));
      expect(json['noEyeletsTop'], isTrue);
      expect(json['noEyeletsBottom'], isTrue);

      final restored = windowFromJson(json);
      expect(restored.noEyeletsTop, isTrue);
      expect(restored.noEyeletsBottom, isTrue);
      expect(restored.hasEyeletlessSides, isTrue);
      expect(restored.eyeletlessSides, [EdgeSide.bottom, EdgeSide.top]);
      // Старый заказ без полей — обе стороны с люверсами.
      final legacy = windowFromJson(const {'bottomWidth': 2000});
      expect(legacy.noEyeletsTop, isFalse);
      expect(legacy.noEyeletsBottom, isFalse);
    });

    test('подпись состояния меняется от кнопок', () {
      expect(
        base(top: true).signature,
        isNot(base().signature),
      );
      expect(
        base(bottom: true).signature,
        isNot(base(top: true).signature),
      );
    });
  });
}

// --- Любой тип люверса на любом окне ---------------------------------------

void _anyEyeletTypeRules() {
  group('Любой люверс на любом окне', () {
    const oval = EyeletType.oval42x22;

    const fixedOval = WindowParams(
      windowType: WindowType.fixed,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      eyeletType: oval,
    );

    test('глухое окно ставит овальный люверс по сторонам', () {
      final spec = WindowSpec.of(fixedOval);
      final layers = spec.layers;

      expect(spec.eyeletType, oval);
      expect(spec.eyeletCount, 24);
      final sides = layers.eyelets.where((eyelet) => !eyelet.isCorner).toList();
      final corners = layers.eyelets.where((eyelet) => eyelet.isCorner).toList();
      expect(sides, isNotEmpty);
      expect(corners, isNotEmpty);
      for (final eyelet in sides) {
        expect(layers.typeFor(eyelet), oval);
      }
      for (final eyelet in corners) {
        expect(layers.typeFor(eyelet), EyeletType.round10);
      }
    });

    test('в расходе овальный люверс учитывается по своему типу', () {
      final summary =
          CostsSummary(const OrderProject(windows: [fixedOval]));

      // По сторонам — овальные, четыре угла — круглые: расход сходится
      // с чертежом и с техкартой.
      expect(summary.eyeletsByType[oval], 20);
      expect(summary.eyeletsByType[EyeletType.round10], 4);
      expect(summary.eyeletTotal, 24);

      final prices = PriceList.defaults();
      // Овальный дороже круглого; цена уже есть в прайсе.
      expect(
        prices.eyeletPerEach(oval),
        greaterThan(prices.eyeletPerEach(EyeletType.round10)),
      );
    });
  });
}

// --- Молния на скрине -------------------------------------------------------

void _screenZipperRules() {
  group('Молния на скрине', () {
    WindowParams screen({
      List<ZipperSpec> zippers = const [ZipperSpec(centered: true)],
      double bottom = 2000,
      double top = 2000,
    }) =>
        WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: bottom,
          topWidth: top,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: 40,
          hemRightMm: 40,
          hemTopMm: 40,
          hemLeftMm: 40,
          zippers: zippers,
        );

    test('молния больше не игнорируется: линия, полоса и зазоры есть', () {
      final spec = WindowSpec.of(screen());
      final layers = spec.layers;

      expect(spec.params.hasZipper, isTrue);
      expect(layers.zippers, hasLength(1));
      expect(layers.zipperBands, hasLength(1));
      // Полоса 50 мм по центру 2000-мм полотна: 975 мм до кромки подворота.
      final gaps = layers.zipperGaps!;
      expect(gaps.band, closeTo(defaultZipperBandWidth, 0.01));
      expect(gaps.left, closeTo(975, 0.02));
      expect(gaps.right, closeTo(975, 0.02));
      expect(gaps.left, greaterThanOrEqualTo(minScreenZipperHemMm));
      // Полоса лежит внутри заготовки: её края не выходят за filmEdge.
      final cut = layers.filmCutBounds;
      final band = layers.zipperBand!;
      expect(band.left, greaterThanOrEqualTo(cut.left));
      expect(band.right, lessThanOrEqualTo(cut.right));
      expect(band.top, greaterThanOrEqualTo(cut.top));
      expect(band.bottom, lessThanOrEqualTo(cut.bottom));
      // Подписи говорят про полосу скрина, а не про спайку тента.
      expect(spec.zipperBandSummary, contains('полоса скрина'));
      expect(spec.zipperBandSummary, contains('шов 3 мм'));
      expect(spec.zipperBandSummary, isNot(contains('тента')));
      expect(spec.notes.join('\n'), contains('Полоса молнии из скрина'));
    });

    test('одна молния: расход ткани и работа шва по длине полосы', () {
      final summary = CostsSummary(OrderProject(windows: [screen()]));
      final spec = WindowSpec.of(screen());

      // Заготовка 2080 × 2080 = 4,3264 м² плюс полоса 50 × 2000 = 0,1 м².
      expect(spec.screenZipperBandAreaM2, closeTo(0.1, 1e-9));
      expect(summary.filmAreaM2, closeTo(4.3264 + 0.1, 1e-9));
      expect(summary.filmAreaWithShrinkageM2, closeTo(4.3264 + 0.1, 1e-9));
      expect(summary.screenZipperBandAreaM2, closeTo(0.1, 1e-9));
      expect(summary.screenZipperCount, 1);
      expect(summary.zipperCount, 1);
      expect(summary.zipperBandLengthMm, closeTo(2000, 1e-9));
      // Подворот по периметру 8000 мм плюс шов полосы 2000 мм.
      expect(summary.screenHemLengthMm, closeTo(10000, 1e-9));
      // У скрина полоса — не тент: окантовки в расходе нет.
      expect(summary.edgeByRoll, isEmpty);
      expect(
        summary.extraLabels.any((label) => label.contains('скрина')),
        isTrue,
      );
    });

    test('две молнии: расход и подписи удваиваются', () {
      final params = screen().addZipper().addZipper();
      expect(params.zippers, hasLength(2));
      final spec = WindowSpec.of(params);
      final summary = CostsSummary(OrderProject(windows: [params]));

      expect(spec.layers.zipperBands, hasLength(2));
      expect(spec.screenZipperBandAreaM2, closeTo(0.2, 1e-9));
      expect(summary.screenZipperCount, 2);
      expect(summary.zipperBandLengthMm, closeTo(4000, 1e-9));
      expect(summary.screenHemLengthMm, closeTo(12000, 1e-9));
      expect(summary.filmAreaM2, closeTo(4.3264 + 0.2, 1e-9));
      expect(spec.zippersSummary, contains('2 шт'));
      expect(spec.zippersSummary, contains('полоса скрина'));
      // Полосы разнесены по ширине и не пересекаются.
      expect(
        spec.layers.zipperBands[0].overlaps(spec.layers.zipperBands[1]),
        isFalse,
      );
    });

    test('валидация: полоса не выходит за заготовку и не ближе 100 мм', () {
      // По центру — замечаний о кромке нет.
      expect(
        validateParams(screen()).any(
          (issue) => issue.message.contains('кромки подворота'),
        ),
        isFalse,
      );

      // Смещение 100 мм: полоса в 75 мм от кромки — замечание.
      final near = screen(zippers: const [
        ZipperSpec(centered: false, offsetMm: 100),
      ]);
      final nearIssues = validateParams(near);
      final nearIssue = nearIssues.firstWhere(
        (issue) => issue.message.contains('кромки подворота'),
      );
      expect(nearIssue.isError, isFalse);
      expect(nearIssue.message, contains('меньше 100 мм'));

      // Смещение 20 мм уводит полосу за заготовку — ошибка.
      final outside = screen(zippers: const [
        ZipperSpec(centered: false, offsetMm: 20),
      ]);
      expect(
        validateParams(outside).any(
          (issue) =>
              issue.isError && issue.message.contains('пределы заготовки'),
        ),
        isTrue,
      );
    });

    test('JSON: молния скрина сохраняется и читается', () {
      final params = screen().addZipper().addZipper();
      final restored = windowFromJson(windowToJson(params));

      expect(restored.material, FilmMaterial.screen);
      expect(restored.zippers, hasLength(2));
      expect(restored.zipperBandWidth, params.zipperBandWidth);
      expect(WindowSpec.of(restored).layers.zippers, hasLength(2));
    });
  });
}
