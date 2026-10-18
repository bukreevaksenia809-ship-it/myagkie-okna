// Независимая проверка расчёта косых окон (трапеций и окон с разными
// высотами слева/справа).
//
// Числа в тестах посчитаны ВРУЧНУЮ, отдельно от кода приложения: контур
// изделия задаётся углами, стороны сдвигаются по своим нормалям, соседние
// сдвинутые прямые пересекаются, площадь берётся формулой Гаусса, длины
// сторон — по теореме Пифагора. Приложение сравнивается с этими числами,
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

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

/// Независимый четырёхугольник: углы против часовой стрелки, начало в левом
/// нижнем. Никаких функций приложения — только аналитическая геометрия.
class _Quad {
  const _Quad(this.points);

  factory _Quad.window({
    required double bottomWidth,
    required double topWidth,
    required double leftHeight,
    required double rightHeight,
  }) {
    final offset = (bottomWidth - topWidth) / 2;
    return _Quad([
      Offset.zero,
      Offset(bottomWidth, 0),
      Offset(offset + topWidth, rightHeight),
      Offset(offset, leftHeight),
    ]);
  }

  final List<Offset> points;

  List<double> get sideLengths => [
        for (var i = 0; i < points.length; i++)
          (points[(i + 1) % points.length] - points[i]).distance,
      ];

  double get areaMm2 {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return (sum / 2).abs();
  }

  double get width => _maxX - _minX;
  double get height => _maxY - _minY;
  double get _minX => points.map((p) => p.dx).reduce(math.min);
  double get _maxX => points.map((p) => p.dx).reduce(math.max);
  double get _minY => points.map((p) => p.dy).reduce(math.min);
  double get _maxY => points.map((p) => p.dy).reduce(math.max);

  /// Сдвиг каждой стороны по нормали внутрь (outward = false) или наружу.
  _Quad offset(List<double> distances, {required bool outward}) {
    final shifted = <(Offset, Offset)>[];
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final direction = b - a;
      final unit = direction / direction.distance;
      // Обход против часовой: внутренняя нормаль (−dy, dx).
      final inward = Offset(-unit.dy, unit.dx);
      final normal = outward ? -inward : inward;
      final distance = distances[i];
      shifted.add((a + normal * distance, b + normal * distance));
    }
    final result = <Offset>[];
    for (var i = 0; i < shifted.length; i++) {
      final previous = shifted[(i - 1 + shifted.length) % shifted.length];
      final current = shifted[i];
      result.add(
        _intersection(previous.$1, previous.$2, current.$1, current.$2),
      );
    }
    return _Quad(result);
  }

  /// Растяжение относительно центра габарита — как припуск и усадка.
  _Quad scale(double sx, double sy) {
    final center = Offset((_minX + _maxX) / 2, (_minY + _maxY) / 2);
    return _Quad([
      for (final point in points)
        Offset(
          center.dx + (point.dx - center.dx) * sx,
          center.dy + (point.dy - center.dy) * sy,
        ),
    ]);
  }

  static Offset _intersection(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d1 = p2 - p1;
    final d2 = p4 - p3;
    final denominator = d1.dx * d2.dy - d1.dy * d2.dx;
    final t =
        ((p3.dx - p1.dx) * d2.dy - (p3.dy - p1.dy) * d2.dx) / denominator;
    return p1 + d1 * t;
  }
}

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
}) =>
    WindowParams(
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

/// Заготовка ПВХ по ручному расчёту: окантовка / 2 минус запайка.
_Quad _manualPvcFilm(WindowParams params) {
  final outer = _Quad.window(
    bottomWidth: params.bottomWidth,
    topWidth: params.topWidth,
    leftHeight: params.leftHeight,
    rightHeight: params.rightHeight,
  );
  final distances = [
    for (final roll in [
      params.rollBottom,
      params.rollRight,
      params.rollTop,
      params.rollLeft,
    ])
      math.max(roll / 2 - params.weldOverlapMm, 0.0),
  ];
  return outer.offset(distances, outward: false);
}

/// Заготовка скрина: прибавка по оси — (сторона 1 + сторона 2) / 2 + 20,
/// половина прибавки на каждую кромку оси.
_Quad _manualScreenFilm(WindowParams params) {
  final outer = _Quad.window(
    bottomWidth: params.bottomWidth,
    topWidth: params.topWidth,
    leftHeight: params.leftHeight,
    rightHeight: params.rightHeight,
  );
  final heightIncrease =
      (params.hemBottomMm + params.hemTopMm) / 2 + screenHemAxisExtraMm;
  final widthIncrease =
      (params.hemLeftMm + params.hemRightMm) / 2 + screenHemAxisExtraMm;
  return outer.offset(
    [
      heightIncrease / 2,
      widthIncrease / 2,
      heightIncrease / 2,
      widthIncrease / 2,
    ],
    outward: true,
  );
}

/// Контур к раскрою с припуском: у ПВХ авто +10 мм к высоте, у скрина — нет.
_Quad _manualCut(WindowSpec spec) {
  final film = spec.params.isScreen
      ? _manualScreenFilm(spec.params)
      : _manualPvcFilm(spec.params);
  final extraHeight = spec.params.effectiveAllowanceHeightMm;
  return film.scale(1, (film.height + extraHeight) / film.height);
}

List<double> _sidesOf(List<Offset> polygon) => [
      for (var i = 0; i < polygon.length; i++)
        (polygon[(i + 1) % polygon.length] - polygon[i]).distance,
    ];

void _expectSides(List<double> actual, List<double> expected, String what) {
  expect(actual.length, expected.length, reason: '$what: число сторон');
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-4),
        reason: '$what: сторона $i');
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

      // Ручной контур изделия: низ 2000, бока по √(500² + 1000²) = 1118,034,
      // верх 1000.
      _expectSides(spec.geometry.sideLengths,
          [2000, 1118.0339887, 1000, 1118.0339887], 'стороны изделия');

      // Ручная заготовка: низ 1854,377, верх 944,377, бока 1017,411.
      final film = _manualPvcFilm(params);
      _expectSides(_sidesOf(film.points),
          [1854.3769335, 1017.4108918, 944.3769335, 1017.4108918],
          'ручная заготовка');
      _expectSides(_sidesOf(spec.layers.filmEdge),
          [1854.3769335, 1017.4108918, 944.3769335, 1017.4108918],
          'заготовка WindowSpec');
      expect(spec.filmAreaM2, closeTo(1.273433, 1e-6));
      expect(film.areaMm2 / 1e6, closeTo(1.273433, 1e-6));

      // К раскрою: авто +10 мм к высоте — 1854,377 × 920; стороны 1026,365.
      final cut = _manualCut(spec);
      expect(spec.filmCutWidth, closeTo(1854.3769335, 1e-4));
      expect(spec.filmCutHeightWithAllowance, closeTo(920, 1e-6));
      expect(spec.filmCutAreaM2, closeTo(1.287427, 1e-6));
      expect(cut.areaMm2 / 1e6, closeTo(1.287427, 1e-6));

      // Лист «Раскрой»: длины четырёх сторон фактической трапеции.
      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths,
          [1854.3769335, 1026.364918, 944.3769335, 1026.364918], 'CutPiece');
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));

      // Расход окантовки — по НАРУЖНЫМ сторонам изделия, а не по заготовке.
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
      _expectSides(spec.geometry.sideLengths,
          [1200, 1400, 1264.9110641, 1000], 'стороны изделия');
      expect(spec.productAreaM2, closeTo(1.44, 1e-9));

      final film = _manualPvcFilm(params);
      _expectSides(_sidesOf(film.points),
          [1110, 1292.5658107, 1170.0427301, 922.5658107],
          'ручная заготовка');
      _expectSides(_sidesOf(spec.layers.filmEdge),
          [1110, 1292.5658107, 1170.0427301, 922.5658107],
          'заготовка WindowSpec');
      expect(spec.filmAreaM2, closeTo(1.229398, 1e-6));

      // К раскрою: 1110 × 1302,566; наклонный верх 1170,951, бока 1302,566
      // и 929,703.
      final cut = _manualCut(spec);
      expect(spec.filmCutWidth, closeTo(1110, 1e-9));
      expect(spec.filmCutHeightWithAllowance, closeTo(1302.5658107, 1e-4));
      expect(spec.filmCutAreaM2, closeTo(1.238909, 1e-6));
      expect(cut.areaMm2 / 1e6, closeTo(1.238909, 1e-6));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths,
          [1110, 1302.5658107, 1170.9511136, 929.7032958], 'CutPiece');
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
      final film = _manualPvcFilm(params);
      _expectSides(_sidesOf(film.points),
          [1860.5572809, 1028.5913142, 940.5572809, 1028.5913142],
          'ручная заготовка');
      _expectSides(_sidesOf(spec.layers.filmEdge),
          [1860.5572809, 1028.5913142, 940.5572809, 1028.5913142],
          'заготовка WindowSpec');
      expect(spec.filmAreaM2, closeTo(1.288513, 1e-6));

      final cut = _manualCut(spec);
      expect(spec.filmCutWidth, closeTo(1860.5572809, 1e-4));
      expect(spec.filmCutHeightWithAllowance, closeTo(930, 1e-6));
      expect(spec.filmCutAreaM2, closeTo(1.302518, 1e-6));
      expect(cut.areaMm2 / 1e6, closeTo(1.302518, 1e-6));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths,
          [1860.5572809, 1037.5451605, 940.5572809, 1037.5451605], 'CutPiece');

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
      // по ширине: (100 + 80) / 2 + 20 = 110. У прямоугольника это дало бы
      // 2110 × 2110, но у трапеции наклон боковых сторон добавляет к габариту
      // заготовки ещё 67,984 мм по ширине.
      expect(params.hemAxisBottomTopIncrease, closeTo(110, 1e-9));
      expect(params.hemAxisLeftRightIncrease, closeTo(110, 1e-9));
      expect(spec.filmCutWidth, closeTo(2177.9837411, 1e-4));
      expect(spec.filmCutHeight, closeTo(1110, 1e-9));
      expect(spec.widthSlopeExtraMm, closeTo(67.9837411, 1e-4));
      expect(spec.heightSlopeExtraMm, closeTo(0, 1e-9));
      // Формула честно показывает три слагаемых: готовый габарит, прибавку
      // по оси и наклон боковых сторон.
      final widthFormula = spec.screenBlankWidthFormulaLabel;
      expect(widthFormula, contains('${formatMm(2000)} + ${formatMm(110)}'));
      expect(widthFormula, contains('наклон боковых сторон'));
      expect(widthFormula, contains('= ${formatMm(2177.9837411)} мм'));

      // Ручная заготовка: низ 2177,984, верх 1067,984, бока 1241,018.
      final film = _manualScreenFilm(params);
      _expectSides(_sidesOf(film.points),
          [2177.9837411, 1241.0177022, 1067.9837411, 1241.0177022],
          'ручная заготовка скрина');
      _expectSides(_sidesOf(spec.layers.filmEdge),
          [2177.9837411, 1241.0177022, 1067.9837411, 1241.0177022],
          'заготовка WindowSpec');
      expect(spec.filmAreaM2, closeTo(1.801512, 1e-6));

      // У скрина нет ни припуска, ни усадки — площадь заготовки та же.
      expect(spec.filmCutAreaM2, closeTo(1.801512, 1e-6));
      expect(spec.filmCutAreaWithShrinkageM2, closeTo(1.801512, 1e-6));
      expect(_manualCut(spec).areaMm2 / 1e6, closeTo(1.801512, 1e-6));

      final piece = CutPiece.ofSpec(spec);
      _expectSides(piece.sideLengths,
          [2177.9837411, 1241.0177022, 1067.9837411, 1241.0177022], 'CutPiece');

      // Окантовки у скрина нет: расход пуст, длина подворота — периметр.
      expect(spec.edgeConsumption, isEmpty);
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.screenHemLengthMm, closeTo(5236.0679775, 1e-4));
      expect(summary.filmAreaM2, closeTo(1.801512, 1e-6));
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
      final withZipper = WindowSpec.of(params.copyWith(
        zippers: const [ZipperSpec(centered: true)],
      ));
      expect(withZipper.zipperBandTotalMm, closeTo(50, 1e-9));
      expect(withZipper.filmCutWidth,
          closeTo(plain.filmCutWidth - 50, 1e-9));
      expect(withZipper.filmCutHeight,
          closeTo(plain.filmCutHeight, 1e-9));
      // Площадь уменьшается пропорционально ширине: 50 / 1854,377.
      expect(
        withZipper.filmCutAreaM2,
        closeTo(plain.filmCutAreaM2 * (plain.filmCutWidth - 50) /
            plain.filmCutWidth, 1e-6),
      );
      // Подпись вычета — та же, что у прямоугольного окна.
      expect(
        withZipper.zipperWidthReductionLabel,
        contains('минус полоса молнии ${formatMm(50)} мм'),
      );
    });
  });
}
