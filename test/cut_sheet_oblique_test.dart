// Косое окно на листе «Раскрой»: заготовка-прямоугольник не пропадает.
//
// Регрессия: после перехода на прямоугольный раскрой трапеции лист мог
// остаться пустым — контур заготовки не рисовался. Тест фиксирует: у
// трапеции и у окна с разными высотами заготовка прямоугольная, размеры и
// площадь считаются, лист и PDF-страница не пустые.
//
// Запуск: flutter test test/cut_sheet_oblique_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

import 'test_fonts.dart';

/// Трапеция: низ 2000, верх 1000, высоты 1000/1000, окантовка 100.
const _trapezoid = WindowParams(
  projectName: 'Косое окно, трапеция',
  drawingNumber: 'КОС-1',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
  allowanceWidthMm: 100,
  allowanceHeightMm: 100,
);

/// Окно с разными высотами: 1200 × 1000/1400, окантовка 100.
const _differentHeights = WindowParams(
  projectName: 'Косое окно, разные высоты',
  drawingNumber: 'КОС-2',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
);

/// Проверяет косую заготовку: четыре стороны по формуле заказчика и
/// площадь по контуру (формула Гаусса), а не прямоугольник по габариту.
void _expectOblique(WindowParams params) {
  final spec = WindowSpec.of(params);
  final piece = CutPiece.ofSpec(spec);

  expect(piece.widthMm, greaterThan(0), reason: 'ширина заготовки');
  expect(piece.heightMm, greaterThan(0), reason: 'высота заготовки');
  expect(piece.hasContour, isTrue, reason: 'контур есть — лист не пустой');
  expect(piece.allContours, hasLength(1));
  expect(piece.sideLengths, hasLength(4));
  // Подписи сторон — номинальные стороны заготовки по формуле заказчика.
  expect(piece.sideLengths, spec.filmCutSideLengths);
  expect(piece.sideLengths[0], closeTo(piece.widthMm, 1e-9), reason: 'низ');
  expect(
    piece.sideLengths[2],
    lessThan(piece.widthMm + 1e-9),
    reason: 'верх уже низа',
  );
  // Габарит к раскрою — те же числа, что в документах.
  expect(piece.widthMm, closeTo(spec.filmCutWidthWithShrinkage, 1e-9));
  expect(piece.heightMm, closeTo(spec.filmCutHeightWithShrinkage, 1e-9));
  // Площадь — по контуру, а не ширина × высота.
  expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
  expect(piece.areaMm2, closeTo(spec.filmCutAreaM2 * 1000000, 1e-6));
  expect(piece.areaMm2, lessThan(piece.widthMm * piece.heightMm));

  final layout = CutLayout.place([piece], const Size(1600, 600));
  final placement = layout.placements.single;
  expect(placement.rect.width, greaterThan(0));
  expect(placement.rect.height, greaterThan(0));
  expect(placement.rect.left, greaterThanOrEqualTo(0));
  expect(placement.rect.right, lessThanOrEqualTo(1600));
}

/// Считает непрозрачные (не белые) точки PNG: пустая страница даёт мало.
Future<int> _nonWhitePixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var colored = 0;
  for (var i = 0; i < data!.lengthInBytes; i += 4) {
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    if (!(r > 248 && g > 248 && b > 248)) colored++;
  }
  image.dispose();
  return colored;
}

void main() {
  setUpAll(loadRealFonts);

  group('CutPiece косого окна', () {
    test('трапеция: косая заготовка, четыре стороны, площадь по контуру', () {
      _expectOblique(_trapezoid);
    });

    test('окно с разными высотами: косая заготовка и четыре стороны', () {
      _expectOblique(_differentHeights);
    });

    test('припуск и усадка сохраняют косую форму заготовки', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
        weldOverlapMm: 5,
        allowanceWidthMm: 100,
        allowanceHeightMm: 100,
        shrinkageEnabled: true,
        shrinkagePercent: 2,
      );
      final spec = WindowSpec.of(params);
      final piece = CutPiece.ofSpec(spec);
      expect(piece.widthMm, greaterThan(0));
      expect(piece.heightMm, greaterThan(0));
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
      expect(piece.areaMm2, lessThan(piece.widthMm * piece.heightMm));
    });
  });

  testWidgets('лист «Раскрой» показывает трапецию и разные высоты', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    const project = OrderProject(windows: [_trapezoid, _differentHeights]);
    final viewport =
CutSheet.sheetSize(project, const Size(1720, 1080));
    tester.view.physicalSize = viewport;

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
    expect(tester.takeException(), isNull);
    expect(find.text('Заготовок: 2 шт'), findsOneWidget);

    final bytes = await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final file = File('build/preview/raskroy-kosoe.png')
      ..writeAsBytesSync(bytes!);
    expect(file.lengthSync(), greaterThan(5000));
    final colored = await tester.runAsync(() => _nonWhitePixels(bytes));
    expect(
      colored,
      greaterThan(30000),
      reason: 'на листе есть заготовки, а не пустое поле',
    );
    // ignore: avoid_print
    print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
  });

  testWidgets('PDF листа «Раскрой» для косого окна не пустой', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: CutSheet(
            project: const OrderProject(windows: [_trapezoid]),
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pages = <Uint8List>[];
    final count = await tester.runAsync(
      () => renderSheetPagesEach(
        captureKey: captureKey,
        onPage: (png, index) async => pages.add(png),
        pageFormat: SheetPageFormat.a3LandscapeAuto,
      ),
    );
    expect(count, greaterThanOrEqualTo(1));
    expect(pages, isNotEmpty);
    final colored = await tester.runAsync(() => _nonWhitePixels(pages.first));
    expect(
      colored,
      greaterThan(30000),
      reason: 'страница PDF не пустая: заготовка на месте',
    );
    expect(tester.takeException(), isNull);
  });
}
