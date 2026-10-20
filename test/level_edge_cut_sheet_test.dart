import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

import 'test_fonts.dart';

/// Окно с разными высотами: ширины равны, низ/верх наклоняются режимом
/// «Ровно». Именно на нём заказчик видел противоположную ориентацию раскроя.
WindowParams _differentHeights(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: разные высоты',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  levelEdge: edge,
  pvcHeightAllowanceEnabled: false,
);

/// Окно с разными ширинами и равными высотами.
WindowParams _differentWidths(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: разные ширины',
  bottomWidth: 1200,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  levelEdge: edge,
  pvcHeightAllowanceEnabled: false,
);

/// Трапеция: низ 2000, верх 1000, высоты равны.
WindowParams _trapezoid(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: трапеция',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  levelEdge: edge,
  pvcHeightAllowanceEnabled: false,
);

/// Скрин с разными высотами: подвороты и +20 к высоте должны сохраниться.
WindowParams _screen(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: скрин',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  levelEdge: edge,
  material: FilmMaterial.screen,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
);

/// Прямоугольник: режим «Ровно» ничего не меняет, числа прежние.
WindowParams _rectangle(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: прямоугольник',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1400,
  rightHeight: 1400,
  levelEdge: edge,
  pvcHeightAllowanceEnabled: false,
);

/// Т-окно: контур из прямоугольников частей, режим «Ровно» его не ломает.
WindowParams _tShape(LevelEdge edge) => WindowParams(
  projectName: 'Ровно: Т-окно',
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  tWelded: true,
  levelEdge: edge,
  pvcHeightAllowanceEnabled: false,
);

/// Контуры к раскрою в координатах геометрии, приведённые к левому нижнему
/// углу габарита — ровно так их хранит [CutPiece].
List<List<Offset>> _geometryContours(WindowSpec spec) {
  final polygons = spec.filmCutPolygonsWithShrinkage;
  final bounds = boundsOfAll(polygons);
  return [
    for (final polygon in polygons)
      [
        for (final point in polygon)
          Offset(point.dx - bounds.left, point.dy - bounds.top),
      ],
  ];
}

/// Сверка контура «Раскроя» с контуром чертежа по каждой вершине.
void _expectSameContours(WindowSpec spec, String reason) {
  final expected = _geometryContours(spec);
  final piece = CutPiece.ofSpec(spec);
  final actual = piece.allContours;
  expect(actual.length, expected.length, reason: '$reason: число контуров');
  // Лист рисует этот же контур в своих координатах: Y зеркалится.
  final sheet = cutSheetContours(
    Rect.fromLTWH(0, 0, piece.widthMm, piece.heightMm),
    piece,
  );
  for (var c = 0; c < expected.length; c++) {
    expect(
      actual[c].length,
      expected[c].length,
      reason: '$reason: вершин в контуре $c',
    );
    expect(
      sheet[c].length,
      expected[c].length,
      reason: '$reason: вершин на листе в контуре $c',
    );
    for (var i = 0; i < expected[c].length; i++) {
      expect(
        actual[c][i].dx,
        closeTo(expected[c][i].dx, 0.01),
        reason: '$reason: X вершины $i контура $c',
      );
      expect(
        actual[c][i].dy,
        closeTo(expected[c][i].dy, 0.01),
        reason: '$reason: Y вершины $i контура $c',
      );
      // На листе та же точка: X совпадает, Y зеркалится от высоты.
      expect(
        sheet[c][i].dx,
        closeTo(expected[c][i].dx, 0.01),
        reason: '$reason: X вершины $i на листе',
      );
      expect(
        sheet[c][i].dy,
        closeTo(piece.heightMm - expected[c][i].dy, 0.01),
        reason: '$reason: Y вершины $i на листе',
      );
    }
  }
}

/// Режим «Ровно» по нормализованному контуру: какие кромки горизонтальны.
void _expectLevelEdge(WindowSpec spec, LevelEdge edge, String reason) {
  final contour = CutPiece.ofSpec(spec).allContours.first;
  expect(contour, hasLength(4), reason: '$reason: четыре вершины');
  final y = [for (final point in contour) point.dy];
  final bottomEqual = (y[0] - y[1]).abs() < 0.01;
  final topEqual = (y[2] - y[3]).abs() < 0.01;
  switch (edge) {
    case LevelEdge.bottom:
      expect(bottomEqual, isTrue, reason: '$reason: низ горизонтален');
      expect(topEqual, isFalse, reason: '$reason: верх наклонён');
    case LevelEdge.top:
      expect(topEqual, isTrue, reason: '$reason: верх горизонтален');
      expect(bottomEqual, isFalse, reason: '$reason: низ наклонён');
    case LevelEdge.none:
      expect(bottomEqual, isFalse, reason: '$reason: низ наклонён');
      expect(topEqual, isFalse, reason: '$reason: верх наклонён');
  }
}

/// Размеры и деньги от режима «Ровно» не зависят: меняются только углы.
void _expectSameSizesAndMoney(WindowParams params, String reason) {
  final specs = [
    for (final edge in LevelEdge.values) WindowSpec.of(params.copyWith(levelEdge: edge)),
  ];
  final summaries = [
    for (final spec in specs) CostsSummary(OrderProject(windows: [spec.params])),
  ];
  final estimates = [
    for (final spec in specs)
      Estimate.of(
        OrderProject(windows: [spec.params]),
        PriceList.defaults(),
      ),
  ];
  final quantity = [
    for (final estimate in estimates)
      estimate.lines
          .firstWhere((line) => line.title.startsWith('Полотно'))
          .quantity,
  ];
  final base = specs.first;
  for (var i = 1; i < specs.length; i++) {
    final spec = specs[i];
    expect(
      spec.filmCutWidthWithShrinkage,
      closeTo(base.filmCutWidthWithShrinkage, 1e-9),
      reason: '$reason: ширина заготовки (${LevelEdge.values[i].name})',
    );
    expect(
      spec.filmCutHeightWithShrinkage,
      closeTo(base.filmCutHeightWithShrinkage, 1e-9),
      reason: '$reason: высота заготовки (${LevelEdge.values[i].name})',
    );
    expect(
      spec.blankSideLengths.length,
      base.blankSideLengths.length,
      reason: '$reason: число сторон (${LevelEdge.values[i].name})',
    );
    for (var side = 0; side < base.blankSideLengths.length; side++) {
      expect(
        spec.blankSideLengths[side],
        closeTo(base.blankSideLengths[side], 1e-9),
        reason: '$reason: сторона $side (${LevelEdge.values[i].name})',
      );
    }
    expect(
      spec.filmCutAreaM2,
      closeTo(base.filmCutAreaM2, 1e-9),
      reason: '$reason: площадь (${LevelEdge.values[i].name})',
    );
    expect(
      spec.filmCutAreaWithShrinkageM2,
      closeTo(base.filmCutAreaWithShrinkageM2, 1e-9),
      reason: '$reason: площадь с усадкой (${LevelEdge.values[i].name})',
    );
    expect(
      summaries[i].filmAreaM2,
      closeTo(summaries.first.filmAreaM2, 1e-9),
      reason: '$reason: расход плёнки (${LevelEdge.values[i].name})',
    );
    expect(
      quantity[i],
      closeTo(quantity.first, 1e-9),
      reason: '$reason: смета (${LevelEdge.values[i].name})',
    );
  }
}

void main() {
  setUpAll(loadRealFonts);

  group('Раскрой использует контур чертежа при любом «Ровно»', () {
    for (final (name, make) in <(String, WindowParams Function(LevelEdge))>[
      ('разные высоты 1000/1400', _differentHeights),
      ('разные ширины 1200/1000', _differentWidths),
      ('трапеция 2000/1000', _trapezoid),
      ('скрин 1200 × 1000/1400', _screen),
      ('прямоугольник 1200 × 1400', _rectangle),
      ('Т-окно', _tShape),
    ]) {
      for (final edge in LevelEdge.values) {
        test('$name, режим ${edge.name}: контур совпадает с геометрией', () {
          final spec = WindowSpec.of(make(edge));
          _expectSameContours(spec, '$name / ${edge.name}');
        });
      }
    }
  });

  group('Ориентация кромок на раскрое', () {
    for (final (name, make) in <(String, WindowParams Function(LevelEdge))>[
      ('разные высоты 1000/1400', _differentHeights),
      ('скрин 1200 × 1000/1400', _screen),
    ]) {
      for (final edge in LevelEdge.values) {
        test('$name, режим ${edge.name}', () {
          final spec = WindowSpec.of(make(edge));
          _expectLevelEdge(spec, edge, '$name / ${edge.name}');
        });
      }
    }

    // При равных высотах режим «Ровно» не может наклонить низ или верх:
    // контур обязан быть одинаковым во всех трёх режимах.
    for (final (name, make) in <(String, WindowParams Function(LevelEdge))>[
      ('разные ширины 1200/1000', _differentWidths),
      ('трапеция 2000/1000', _trapezoid),
    ]) {
      test('$name: равные высоты — контур одинаков во всех режимах', () {
        final shapes = [
          for (final edge in LevelEdge.values)
            CutPiece.ofSpec(WindowSpec.of(make(edge))).allContours,
        ];
        for (var mode = 1; mode < shapes.length; mode++) {
          expect(shapes[mode].length, shapes.first.length);
          for (var c = 0; c < shapes.first.length; c++) {
            for (var i = 0; i < shapes.first[c].length; i++) {
              expect(
                shapes[mode][c][i].dx,
                closeTo(shapes.first[c][i].dx, 0.01),
                reason: '$name: X $i, режим ${LevelEdge.values[mode].name}',
              );
              expect(
                shapes[mode][c][i].dy,
                closeTo(shapes.first[c][i].dy, 0.01),
                reason: '$name: Y $i, режим ${LevelEdge.values[mode].name}',
              );
            }
          }
        }
      });
    }
  });

  group('«Ровно» не меняет размеры, площадь и смету', () {
    for (final (name, make) in <(String, WindowParams Function(LevelEdge))>[
      ('разные высоты 1000/1400', _differentHeights),
      ('разные ширины 1200/1000', _differentWidths),
      ('трапеция 2000/1000', _trapezoid),
      ('скрин 1200 × 1000/1400', _screen),
      ('прямоугольник 1200 × 1400', _rectangle),
      ('Т-окно', _tShape),
    ]) {
      test('$name: размеры, площадь, расход и смета одинаковы', () {
        _expectSameSizesAndMoney(make(LevelEdge.bottom), name);
      });
    }
  });

  group('Регресс: прежние числа', () {
    test('прямоугольник 1200 × 1400: заготовка 1110 × 1310', () {
      final spec = WindowSpec.of(_rectangle(LevelEdge.bottom));
      expect(spec.filmCutWidth, 1110);
      expect(spec.filmCutHeight, 1310);
      expect(spec.filmCutAreaM2, closeTo(1.4541, 1e-9));
    });

    test('скрин 2000 × 2000, подворот 40 → 2040 × 2060', () {
      final spec = WindowSpec.of(
        const WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: 40,
          hemRightMm: 40,
          hemTopMm: 40,
          hemLeftMm: 40,
        ),
      );
      expect(spec.filmCutWidth, 2040);
      expect(spec.filmCutHeight, 2060);
      expect(spec.filmCutAreaM2, closeTo(4.2024, 1e-9));
    });

    test('ПВХ 3050/3050 × 2140/2800 → стороны 2990/2740/2990/2080', () {
      final spec = WindowSpec.of(
        const WindowParams(
          bottomWidth: 3050,
          topWidth: 3050,
          leftHeight: 2140,
          rightHeight: 2800,
          rollBottom: 100,
          rollRight: 100,
          rollTop: 100,
          rollLeft: 100,
          weldOverlapMm: 20,
          pvcHeightAllowanceEnabled: false,
        ),
      );
      expect(spec.blankSideLengths, [2990, 2740, 2990, 2080]);
      expect(spec.filmCutWidth, closeTo(2990, 1e-9));
    });
  });

  testWidgets('пишет превью раскроя «Ровно: верх» для глаз', (tester) async {
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = OrderProject(
      windows: [_differentHeights(LevelEdge.top)],
    );
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: CutSheet(
            project: project,
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bytes = await tester.runAsync(() async {
      final boundary = captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final longest = math.max(boundary.size.width, boundary.size.height);
      final ratio = math.min(2.2, 10000 / longest);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    final directory = Directory('build/preview')..createSync(recursive: true);
    final file = File('${directory.path}/rovno-verh-raskroy-posle.png')
      ..writeAsBytesSync(bytes!);
    expect(file.lengthSync(), greaterThan(5000));
    // ignore: avoid_print
    print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
  });
}
