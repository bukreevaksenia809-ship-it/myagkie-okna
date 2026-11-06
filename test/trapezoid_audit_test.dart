// Независимая проверка расчёта косых окон (трапеций и окон с разными
// высотами слева/справа).
//
// Правило заказчика: каждая сторона заготовки = сторона изделия
// − 2 × (готовая полоса) + 2 × запайка. Стороны считаются по длине КАЖДОЙ
// стороны отдельно, форма остаётся косой, а площадь считается по формуле
// Гаусса (не по габаритному прямоугольнику).
//
// Числа в тестах посчитаны ВРУЧНУЮ, отдельно от кода приложения: стороны
// заготовки — по формуле, площадь — по средней ширине и средней высоте
// трапеции. Приложение сравнивается с этими числами, поэтому тест ловит
// ошибку и в геометрии, и в площади, и в расходе.
//
// Четыре примера заказчика:
//   а) трапеция 2000/1000 × 1000, окантовка 100 по всем, запайка 5;
//   б) разные высоты: лево 1000, право 1400, ширина 1200/1200, окантовка
//      100, запайка 5;
//   в) та же трапеция 2000/1000 × 1000, окантовка низ 120 / верх 80 /
//      бока 100, запайка 10;
//   г) скрин 2000/1000 × 1000, подворот низ/право/верх/лево = 80/80/100/100.
//
// Запуск: flutter test test/trapezoid_audit_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

WindowParams _pvc({
  required double bottom,
  required double top,
  required double left,
  required double right,
  double rollBottom = 100,
  double rollRight = 100,
  double rollTop = 100,
  double rollLeft = 100,
  double weld = 5,
}) => WindowParams(
  bottomWidth: bottom,
  topWidth: top,
  leftHeight: left,
  rightHeight: right,
  rollBottom: rollBottom,
  rollRight: rollRight,
  rollTop: rollTop,
  rollLeft: rollLeft,
  weldOverlapMm: weld,
);

/// Ручные стороны заготовки ПВХ: [низ, право, верх, лево].
///
/// Каждая сторона = сторона изделия − 2d, где d = готовая полоса − запайка.
/// Для ширин берутся вычеты левой и правой кромок, для высот — нижней и
/// верхней: при одинаковой полосе это ровно «сторона − 2d».
List<double> _manualPvcSides(WindowParams params) {
  double d(EdgeSide side) =>
      math.max(params.rollForSide(side) / 2 - params.weldOverlapMm, 0.0);
  final widthDeduction = d(EdgeSide.left) + d(EdgeSide.right);
  final heightDeduction = d(EdgeSide.bottom) + d(EdgeSide.top);
  return [
    params.bottomWidth - widthDeduction,
    params.rightHeight - heightDeduction,
    params.topWidth - widthDeduction,
    params.leftHeight - heightDeduction,
  ];
}

/// Ручные стороны заготовки скрина: изделие плюс прибавка по осям.
List<double> _manualScreenSides(WindowParams params) {
  final width = params.hemAxisLeftRightIncrease;
  final height = params.hemAxisBottomTopIncrease;
  return [
    params.bottomWidth + width,
    params.rightHeight + height,
    params.topWidth + width,
    params.leftHeight + height,
  ];
}

List<double> _manualBlankSides(WindowParams params) =>
    params.isScreen ? _manualScreenSides(params) : _manualPvcSides(params);

/// Ручные стороны к раскрою: припуск и усадка.
List<double> _manualCutSides(WindowParams params) {
  final blank = _manualBlankSides(params);
  final zipper = params.zippers.fold<double>(
    0,
    (sum, spec) => sum + spec.bandWidth,
  );
  final maxWidth = math.max(blank[0], blank[2]);
  final maxHeight = math.max(blank[1], blank[3]);
  final targetWidth = maxWidth - zipper + params.allowanceWidthMm;
  final targetHeight = maxHeight + params.effectiveAllowanceHeightMm;
  final fx = targetWidth / maxWidth;
  final fy = targetHeight / maxHeight;
  final shrink = 1 + params.effectiveShrinkagePercent / 100;
  return [
    blank[0] * fx * shrink,
    blank[1] * fy * shrink,
    blank[2] * fx * shrink,
    blank[3] * fy * shrink,
  ];
}

/// Ручная площадь заготовки: средняя ширина × средняя высота трапеции.
double _manualAreaM2(List<double> sides) =>
    (sides[0] + sides[2]) / 2 * (sides[1] + sides[3]) / 2 / 1000000;

void _expectSides(List<double> actual, List<double> expected, String what) {
  expect(actual.length, expected.length, reason: '$what: число сторон');
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-4), reason: '$what: сторона $i');
  }
}

void main() {
  group('Косые окна: ручной расчёт против WindowSpec', () {
    test('а) трапеция 2000/1000 × 1000, окантовка 100, запайка 5', () {
      final params = _pvc(
        bottom: 2000,
        top: 1000,
        left: 1000,
        right: 1000,
        weld: 5,
      );
      final spec = WindowSpec.of(params);

      // Изделие остаётся трапецией: низ 2000, бока по √(500² + 1000²),
      // верх 1000.
      _expectSides(spec.geometry.sideLengths, [
        2000,
        1118.0339887,
        1000,
        1118.0339887,
      ], 'стороны изделия');
      expect(spec.productAreaM2, closeTo(1.5, 1e-9));

      // Заготовка: вычет 50 / 2 − 5 = 45 мм с каждой стороны.
      // Низ 2000 − 90 = 1910, верх 1000 − 90 = 910, высоты 1000 − 90 = 910.
      final blank = _manualPvcSides(params);
      expect(blank, [1910, 910, 910, 910]);
      _expectSides(spec.blankSideLengths, blank, 'стороны заготовки');
      expect(spec.filmCutWidth, closeTo(1910, 1e-9));
      expect(spec.filmCutHeight, closeTo(910, 1e-9));
      // Площадь трапеции: (1910 + 910) / 2 × 910 = 1,2831 м².
      expect(spec.filmAreaM2, closeTo(1.2831, 1e-9));
      expect(spec.filmAreaM2, closeTo(_manualAreaM2(blank), 1e-9));
      // Форма заготовки — косой четырёхугольник.
      expect(spec.layers.filmEdge, hasLength(4));
      expect(spec.layers.blankAreaMm2 / 1e6, closeTo(1.2831, 1e-9));

      // К раскрою: авто +10 мм к высоте — высоты 920, стороны
      // [1910, 920, 910, 920], площадь (1910 + 910) / 2 × 920 = 1,2972.
      final cut = _manualCutSides(params);
      _expectSides(spec.filmCutSideLengths, cut, 'стороны к раскрою');
      expect(spec.filmCutWidthWithAllowance, closeTo(1910, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(920, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.2972, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(_manualAreaM2(cut), 1e-9));
      expect(spec.filmCutPolygon, hasLength(4));

      // Лист «Раскрой» подписывает те же стороны.
      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, cut, 'CutPiece');
      expect(piece.widthMm, closeTo(1910, 1e-9));
      expect(piece.heightMm, closeTo(920, 1e-9));
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
      expect(piece.areaMm2 / 1e6, closeTo(1.2972, 1e-9));

      // Расход окантовки — по НАРУЖНЫМ сторонам ИЗДЕЛИЯ, а не заготовки.
      expect(spec.edgeConsumption[100], closeTo(5236.0679775, 1e-4));
      expect(spec.edgeConsumption.length, 1);
    });

    test('б) разные высоты: лево 1000, право 1400, ширина 1200/1200', () {
      final params = _pvc(
        bottom: 1200,
        top: 1200,
        left: 1000,
        right: 1400,
        weld: 5,
      );
      final spec = WindowSpec.of(params);

      // Верх наклонён: 1200 × 400 → длина √(1200² + 400²) = 1264,911.
      _expectSides(spec.geometry.sideLengths, [
        1200,
        1400,
        1264.9110641,
        1000,
      ], 'стороны изделия');
      expect(spec.productAreaM2, closeTo(1.44, 1e-9));

      // Заготовка: низ/верх 1200 − 90 = 1110, высоты 1000 − 90 = 910 и
      // 1400 − 90 = 1310.
      final blank = _manualPvcSides(params);
      expect(blank, [1110, 1310, 1110, 910]);
      _expectSides(spec.blankSideLengths, blank, 'стороны заготовки');
      expect(spec.filmCutWidth, closeTo(1110, 1e-9));
      expect(spec.filmCutHeight, closeTo(1310, 1e-9));
      expect(spec.filmAreaM2, closeTo(_manualAreaM2(blank), 1e-9));
      expect(spec.filmAreaM2, closeTo(1.2321, 1e-9));

      // К раскрою: высота 1320, площадь (1110 + 1110) / 2 × 1320 = 1,2415.
      final cut = _manualCutSides(params);
      _expectSides(spec.filmCutSideLengths, cut, 'стороны к раскрою');
      expect(spec.filmCutHeightWithAllowance, closeTo(1320, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(_manualAreaM2(cut), 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.2415, 1e-3));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, cut, 'CutPiece');
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));

      // Окантовка: низ 1200 + право 1400 + верх 1264,911 + лево 1000.
      expect(spec.edgeConsumption[100], closeTo(4864.9110641, 1e-4));
    });

    test('в) разная окантовка: низ 120, верх 80, бока 100, запайка 10', () {
      final params = _pvc(
        bottom: 2000,
        top: 1000,
        left: 1000,
        right: 1000,
        rollBottom: 120,
        rollTop: 80,
        rollLeft: 100,
        rollRight: 100,
        weld: 10,
      );
      final spec = WindowSpec.of(params);

      // Готовые полосы: низ 60, верх 40, бока 50; вычет запайки 10.
      // Низ/верх: 2000 − (50 − 10) − (50 − 10) = 1920 и 920.
      // Высоты: 1000 − (60 − 10) − (40 − 10) = 920.
      final blank = _manualPvcSides(params);
      expect(blank, [1920, 920, 920, 920]);
      _expectSides(spec.blankSideLengths, blank, 'стороны заготовки');
      expect(spec.filmCutWidth, closeTo(1920, 1e-9));
      expect(spec.filmCutHeight, closeTo(920, 1e-9));
      expect(spec.filmAreaM2, closeTo(_manualAreaM2(blank), 1e-9));
      expect(spec.filmAreaM2, closeTo(1.3064, 1e-9));

      // К раскрою: высоты 930, площадь (1920 + 920) / 2 × 930 = 1,3206.
      final cut = _manualCutSides(params);
      _expectSides(spec.filmCutSideLengths, cut, 'стороны к раскрою');
      expect(spec.filmCutHeightWithAllowance, closeTo(930, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(_manualAreaM2(cut), 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.3206, 1e-9));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, cut, 'CutPiece');

      // Расход по рулонам: низ 2000 → 120, бока 2 × 1118,034 → 100,
      // верх 1000 → 80.
      expect(spec.edgeConsumption[120], closeTo(2000, 1e-9));
      expect(spec.edgeConsumption[100], closeTo(2236.0679775, 1e-4));
      expect(spec.edgeConsumption[80], closeTo(1000, 1e-9));
    });

    test('г) скрин 2000/1000 × 1000, подворот 80/80/100/100', () {
      const params = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
        hemBottomMm: 80,
        hemRightMm: 80,
        hemTopMm: 100,
        hemLeftMm: 100,
      );
      final spec = WindowSpec.of(params);

      // В заготовку идёт половина подворота каждой стороны:
      // по высоте 40 + 50 + 20 = 110; по ширине 50 + 40 = 90.
      // Заготовка: низ 2090, верх 1090, высоты 1110.
      expect(params.hemAxisBottomTopIncrease, closeTo(110, 1e-9));
      expect(params.hemAxisLeftRightIncrease, closeTo(90, 1e-9));
      final blank = _manualScreenSides(params);
      expect(blank, [2090, 1110, 1090, 1110]);
      _expectSides(spec.blankSideLengths, blank, 'стороны заготовки');
      expect(spec.filmCutWidth, closeTo(2090, 1e-9));
      expect(spec.filmCutHeight, closeTo(1110, 1e-9));
      // Площадь трапеции: (2090 + 1090) / 2 × 1110 = 1,7649 м².
      expect(spec.filmAreaM2, closeTo(_manualAreaM2(blank), 1e-9));
      expect(spec.filmAreaM2, closeTo(1.7649, 1e-9));

      // Наклона сторон в прибавке по осям больше нет.
      expect(spec.widthSlopeExtraMm, closeTo(0, 1e-9));
      expect(spec.heightSlopeExtraMm, closeTo(0, 1e-9));
      final widthFormula = spec.screenBlankWidthFormulaLabel;
      expect(
        widthFormula,
        contains(
          '${formatMm(2000)} + ${formatMm(50)} + ${formatMm(40)}',
        ),
      );
      expect(widthFormula, isNot(contains('наклон')));
      expect(widthFormula, contains('= ${formatMm(2090)} мм'));

      // У скрина нет ни припуска, ни усадки — площадь та же.
      final cut = _manualCutSides(params);
      _expectSides(spec.filmCutSideLengths, cut, 'стороны к раскрою');
      expect(spec.filmCutAreaM2, closeTo(1.7649, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(_manualAreaM2(cut), 1e-9));
      expect(spec.filmCutAreaWithShrinkageM2, closeTo(1.7649, 1e-9));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, cut, 'CutPiece');
      expect(piece.widthMm, closeTo(2090, 1e-9));
      expect(piece.heightMm, closeTo(1110, 1e-9));

      // Окантовки у скрина нет: расход пуст, длина подворота — периметр.
      expect(spec.edgeConsumption, isEmpty);
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.screenHemLengthMm, closeTo(5236.0679775, 1e-4));
      expect(summary.filmAreaM2, closeTo(1.7649, 1e-9));
    });

    test('д) косой скрин заказчика: низ 2000, верх 1000, высоты 1000/1000, '
        'подвороты 80 на все стороны', () {
      const params = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
        hemBottomMm: 80,
        hemRightMm: 80,
        hemTopMm: 80,
        hemLeftMm: 80,
      );
      final spec = WindowSpec.of(params);

      // Вручную по каждой стороне: 80 / 2 = 40.
      // Низ: 2000 + 40 + 40 = 2080.
      // Верх: 1000 + 40 + 40 = 1080.
      // Правая и левая высоты: 1000 + 40 + 40 + 20 = 1100 каждая.
      final blank = _manualScreenSides(params);
      expect(blank, [2080, 1100, 1080, 1100]);
      _expectSides(spec.blankSideLengths, blank, 'стороны заготовки');
      expect(spec.filmCutWidth, closeTo(2080, 1e-9));
      expect(spec.filmCutHeight, closeTo(1100, 1e-9));
      // Площадь трапеции: (2080 + 1080) / 2 × 1100 = 1,738 м².
      expect(spec.filmAreaM2, closeTo(_manualAreaM2(blank), 1e-9));
      expect(spec.filmAreaM2, closeTo(1.738, 1e-9));

      // Формулы показывают половины подворотов и +20 только к высоте.
      expect(
        spec.screenBlankWidthFormulaLabel,
        contains(
          '${formatMm(2000)} + ${formatMm(40)} + ${formatMm(40)} = '
          '${formatMm(2080)} мм',
        ),
      );
      expect(
        spec.screenBlankHeightFormulaLabel,
        contains(
          '${formatMm(1000)} + ${formatMm(40)} + ${formatMm(40)} + '
          '${formatMm(screenHemAxisExtraMm)} = ${formatMm(1100)} мм',
        ),
      );
      expect(spec.widthSlopeExtraMm, closeTo(0, 1e-9));
      expect(spec.heightSlopeExtraMm, closeTo(0, 1e-9));
    });

    test('молния на трапеции сужает ширину, форма остаётся косой', () {
      final params = _pvc(
        bottom: 2000,
        top: 1000,
        left: 1000,
        right: 1000,
        weld: 5,
      );
      final plain = WindowSpec.of(params);
      final withZipper = WindowSpec.of(
        params.copyWith(zippers: const [ZipperSpec(centered: true)]),
      );
      // Молния по центру делит на сегменты, габарит и высота не меняются.
      expect(withZipper.zipperBandTotalMm, 0);
      expect(withZipper.filmCutWidth, closeTo(plain.filmCutWidth, 1e-9));
      expect(withZipper.filmCutHeight, closeTo(plain.filmCutHeight, 1e-9));
      expect(withZipper.filmCutPolygons, hasLength(2));
      expect(withZipper.filmCutAreaM2, lessThan(plain.filmCutAreaM2));
      expect(withZipper.zipperWidthReductionLabel, isNull);
    });

    test('Т-окно: заготовка — прямоугольник по каждой части', () {
      const params = WindowParams(
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
      final spec = WindowSpec.of(params);
      // Части: основное 1955 × 1410, пристройка 755 × 510 — по прямоугольнику.
      expect(spec.filmPartBounds, hasLength(2));
      expect(spec.filmPartBounds[0].width, closeTo(1955, 1e-9));
      expect(spec.filmPartBounds[0].height, closeTo(1410, 1e-9));
      expect(spec.filmPartBounds[1].width, closeTo(755, 1e-9));
      expect(spec.filmPartBounds[1].height, closeTo(510, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(3.1416, 1e-6));
    });
  });
}
