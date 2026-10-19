// Независимая проверка расчёта косых окон (трапеций и окон с разными
// высотами слева/справа).
//
// Правило заказчика: раскрой трапеции считается КАК ПРЯМОУГОЛЬНИК. Заготовка —
// это габарит изделия минус окантовка (плюс запайка) по сторонам, как у
// прямоугольного окна; никакой площади по полигону. Изделие на чертеже
// остаётся фактической формы (трапецией), но плёнка кроится прямоугольником,
// поэтому «пустые» углы честно входят в расход.
//
// Числа в тестах посчитаны ВРУЧНУЮ, отдельно от кода приложения: габарит
// берётся по углам изделия, вычеты — половина рулона минус запайка, площадь —
// произведение ширины на высоту. Приложение сравнивается с этими числами,
// поэтому тест ловит ошибку и в геометрии, и в площади, и в расходе.
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
import 'dart:ui' show Rect;

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

/// Ручная прямоугольная заготовка ПВХ: габарит минус окантовка плюс запайка.
Rect _manualPvcBlank(WindowParams params) {
  final bounds = WindowSpec.of(params).geometry.productBounds;
  double deduction(double roll) =>
      math.max(roll / 2 - params.weldOverlapMm, 0.0);
  return Rect.fromLTRB(
    bounds.left + deduction(params.rollLeft),
    bounds.top + deduction(params.rollBottom),
    bounds.right - deduction(params.rollRight),
    bounds.bottom - deduction(params.rollTop),
  );
}

/// Ручная прямоугольная заготовка скрина: габарит плюс прибавка по осям.
Rect _manualScreenBlank(WindowParams params) {
  final bounds = WindowSpec.of(params).geometry.productBounds;
  final halfHeight = params.hemAxisBottomTopIncrease / 2;
  final halfWidth = params.hemAxisLeftRightIncrease / 2;
  return Rect.fromLTRB(
    bounds.left - halfWidth,
    bounds.top - halfHeight,
    bounds.right + halfWidth,
    bounds.bottom + halfHeight,
  );
}

Rect _manualBlank(WindowParams params) =>
    params.isScreen ? _manualScreenBlank(params) : _manualPvcBlank(params);

/// Заготовка к раскрою: прямоугольник плюс припуск и минус полосы молний,
/// ровно как у прямоугольного окна. Припуск растягивает прямоугольник
/// относительно его центра — как в WindowSpec.filmCutPolygons.
Rect _manualCut(WindowParams params) {
  final blank = _manualBlank(params);
  final zipper = params.zippers.fold<double>(
    0,
    (sum, spec) => sum + spec.bandWidth,
  );
  final targetWidth = blank.width - zipper + params.allowanceWidthMm;
  final targetHeight = blank.height + params.effectiveAllowanceHeightMm;
  final sx = targetWidth / blank.width;
  final sy = targetHeight / blank.height;
  final center = blank.center;
  return Rect.fromLTRB(
    center.dx + (blank.left - center.dx) * sx,
    center.dy + (blank.top - center.dy) * sy,
    center.dx + (blank.right - center.dx) * sx,
    center.dy + (blank.bottom - center.dy) * sy,
  );
}

void _expectSides(
  List<double> actual,
  List<double> expected,
  String what,
) {
  expect(actual.length, expected.length, reason: '$what: число сторон');
  for (var i = 0; i < expected.length; i++) {
    expect(
      actual[i],
      closeTo(expected[i], 1e-4),
      reason: '$what: сторона $i',
    );
  }
}

/// Прямоугольник заготовки против ручного: углы и площадь.
void _expectRect(List<Offset> actual, Rect expected, String what) {
  expect(actual.length, 4, reason: '$what: это прямоугольник');
  expect(actual[0].dx, closeTo(expected.left, 1e-6), reason: '$what: лево');
  expect(actual[0].dy, closeTo(expected.top, 1e-6), reason: '$what: низ');
  expect(actual[2].dx, closeTo(expected.right, 1e-6), reason: '$what: право');
  expect(actual[2].dy, closeTo(expected.bottom, 1e-6), reason: '$what: верх');
}

/// Стороны CutPiece прямоугольной заготовки: низ, право, верх, лево.
List<double> _rectCutSides(Rect cut) => [
  cut.width,
  cut.height,
  cut.width,
  cut.height,
];

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
      _expectSides(
        spec.geometry.sideLengths,
        [2000, 1118.0339887, 1000, 1118.0339887],
        'стороны изделия',
      );
      expect(spec.productAreaM2, closeTo(1.5, 1e-9));

      // Заготовка — ПРЯМОУГОЛЬНИК по габариту. Вычет с каждой стороны:
      // 100 / 2 − 5 = 45 мм. Ширина 2000 − 90 = 1910, высота 1000 − 90 = 910.
      final blank = _manualPvcBlank(params);
      expect(blank.width, closeTo(1910, 1e-9));
      expect(blank.height, closeTo(910, 1e-9));
      _expectRect(spec.layers.filmEdge, blank, 'заготовка WindowSpec');
      expect(spec.filmCutWidth, closeTo(1910, 1e-9));
      expect(spec.filmCutHeight, closeTo(910, 1e-9));
      // Площадь прямоугольника: 1910 × 910 = 1,7381 м² (а не 1,27 по
      // контуру трапеции).
      expect(spec.filmAreaM2, closeTo(1.7381, 1e-9));
      expect(
        spec.layers.filmAreaM2,
        closeTo(1910 * 910 / 1000000, 1e-9),
      );

      // К раскрою: авто +10 мм к высоте — 1910 × 920.
      final cut = _manualCut(params);
      expect(cut.width, closeTo(1910, 1e-9));
      expect(cut.height, closeTo(920, 1e-9));
      expect(spec.filmCutWidthWithAllowance, closeTo(1910, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(920, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.7572, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(cut.width * cut.height / 1e6, 1e-9));
      _expectRect(spec.filmCutPolygon, cut, 'раскрой WindowSpec');
      expect(spec.filmCutPolygon, hasLength(4));

      // Лист «Раскрой» рисует прямоугольную заготовку с четырьмя равными
      // парами сторон: 1910, 920, 1910, 920.
      final piece = CutPiece.ofSpec(spec);
      _expectSides(
        piece.sideLengths,
        _rectCutSides(cut),
        'CutPiece',
      );
      expect(piece.widthMm, closeTo(1910, 1e-9));
      expect(piece.heightMm, closeTo(920, 1e-9));
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));

      // Расход окантовки — по НАРУЖНЫМ сторонам ИЗДЕЛИЯ, а не по заготовке.
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
      _expectSides(
        spec.geometry.sideLengths,
        [1200, 1400, 1264.9110641, 1000],
        'стороны изделия',
      );
      expect(spec.productAreaM2, closeTo(1.44, 1e-9));

      // Заготовка-прямоугольник: ширина 1200 − 90 = 1110, высота берётся по
      // габариту (верх на 1400) и тоже минус 90: 1400 − 90 = 1310.
      final blank = _manualPvcBlank(params);
      expect(blank.width, closeTo(1110, 1e-9));
      expect(blank.height, closeTo(1310, 1e-9));
      _expectRect(spec.layers.filmEdge, blank, 'заготовка WindowSpec');
      expect(spec.filmCutWidth, closeTo(1110, 1e-9));
      expect(spec.filmCutHeight, closeTo(1310, 1e-9));
      expect(spec.filmAreaM2, closeTo(1110 * 1310 / 1000000, 1e-9));

      // К раскрою: 1110 × (1310 + 10) = 1110 × 1320.
      final cut = _manualCut(params);
      expect(cut.width, closeTo(1110, 1e-9));
      expect(cut.height, closeTo(1320, 1e-9));
      expect(spec.filmCutWidth, closeTo(1110, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(1320, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.4652, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(cut.width * cut.height / 1e6, 1e-9));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, _rectCutSides(cut), 'CutPiece');
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
      // Ширина: 2000 − (50 − 10) − (50 − 10) = 1920.
      // Высота: 1000 − (60 − 10) − (40 − 10) = 920.
      final blank = _manualPvcBlank(params);
      expect(blank.width, closeTo(1920, 1e-9));
      expect(blank.height, closeTo(920, 1e-9));
      _expectRect(spec.layers.filmEdge, blank, 'заготовка WindowSpec');
      expect(spec.filmCutWidth, closeTo(1920, 1e-9));
      expect(spec.filmCutHeight, closeTo(920, 1e-9));
      expect(spec.filmAreaM2, closeTo(1920 * 920 / 1000000, 1e-9));

      // К раскрою: 1920 × (920 + 10) = 1920 × 930.
      final cut = _manualCut(params);
      expect(cut.width, closeTo(1920, 1e-9));
      expect(cut.height, closeTo(930, 1e-9));
      expect(spec.filmCutWidth, closeTo(1920, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(930, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(1.7856, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(cut.width * cut.height / 1e6, 1e-9));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, _rectCutSides(cut), 'CutPiece');

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

      // Прибавка по высоте: (80 + 100) / 2 + 20 = 110;
      // по ширине: (100 + 80) / 2 + 20 = 110. Заготовка-прямоугольник:
      // (2000 + 110) × (1000 + 110) = 2110 × 1110.
      expect(params.hemAxisBottomTopIncrease, closeTo(110, 1e-9));
      expect(params.hemAxisLeftRightIncrease, closeTo(110, 1e-9));
      expect(spec.filmCutWidth, closeTo(2110, 1e-9));
      expect(spec.filmCutHeight, closeTo(1110, 1e-9));
      // Наклона сторон в прямоугольном раскрое больше нет.
      expect(spec.widthSlopeExtraMm, closeTo(0, 1e-9));
      expect(spec.heightSlopeExtraMm, closeTo(0, 1e-9));
      final widthFormula = spec.screenBlankWidthFormulaLabel;
      expect(widthFormula, contains('${formatMm(2000)} + ${formatMm(110)}'));
      expect(widthFormula, isNot(contains('наклон')));
      expect(widthFormula, contains('= ${formatMm(2110)} мм'));

      final blank = _manualScreenBlank(params);
      expect(blank.width, closeTo(2110, 1e-9));
      expect(blank.height, closeTo(1110, 1e-9));
      _expectRect(spec.layers.filmEdge, blank, 'заготовка WindowSpec');
      expect(spec.filmAreaM2, closeTo(2110 * 1110 / 1000000, 1e-9));

      // У скрина нет ни припуска, ни усадки — площадь та же, прямоугольная.
      final cut = _manualCut(params);
      expect(spec.filmCutAreaM2, closeTo(2.3421, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(cut.width * cut.height / 1e6, 1e-9));
      expect(spec.filmCutAreaWithShrinkageM2, closeTo(2.3421, 1e-9));
      _expectRect(spec.filmCutPolygon, cut, 'раскрой WindowSpec');

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths, _rectCutSides(cut), 'CutPiece');
      expect(piece.widthMm, closeTo(2110, 1e-9));
      expect(piece.heightMm, closeTo(1110, 1e-9));

      // Окантовки у скрина нет: расход пуст, длина подворота — периметр.
      expect(spec.edgeConsumption, isEmpty);
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.screenHemLengthMm, closeTo(5236.0679775, 1e-4));
      expect(summary.filmAreaM2, closeTo(2.3421, 1e-9));
    });

    test('молния на трапеции сужает ширину, высота не меняется', () {
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
      expect(withZipper.zipperBandTotalMm, closeTo(50, 1e-9));
      expect(
        withZipper.filmCutWidth,
        closeTo(plain.filmCutWidth - 50, 1e-9),
      );
      expect(withZipper.filmCutHeight, closeTo(plain.filmCutHeight, 1e-9));
      // Площадь прямоугольника уменьшается пропорционально ширине:
      // 50 / 1910.
      expect(
        withZipper.filmCutAreaM2,
        closeTo(
          plain.filmCutAreaM2 * (plain.filmCutWidth - 50) / plain.filmCutWidth,
          1e-9,
        ),
      );
      // Подпись вычета — та же, что у прямоугольного окна.
      expect(
        withZipper.zipperWidthReductionLabel,
        contains('минус полоса молнии ${formatMm(50)} мм'),
      );
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
