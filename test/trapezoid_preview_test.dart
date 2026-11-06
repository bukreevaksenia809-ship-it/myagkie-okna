// Превью четырёх примеров косых окон для заказчика: чертёж, лист «Раскрой»
// и лист «Расходы» по каждому примеру. Пишет PNG в build/preview/.
//
// Запуск: flutter test test/trapezoid_preview_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/costs_sheet.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

/// а) Трапеция 2000/1000 × 1000, окантовка 100 по всем сторонам, запайка 5.
const _trapezoidA = WindowParams(
  projectName: 'Косое окно, пример А',
  customer: 'Заказчик: пример А',
  drawingNumber: 'КОС-А',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
);

/// б) Разные высоты: лево 1000, право 1400, ширина 1200/1200.
const _trapezoidB = WindowParams(
  projectName: 'Косое окно, пример Б',
  customer: 'Заказчик: пример Б',
  drawingNumber: 'КОС-Б',
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

/// в) Разная окантовка: низ 120, верх 80, бока 100; запайка 10.
const _trapezoidC = WindowParams(
  projectName: 'Косое окно, пример В',
  customer: 'Заказчик: пример В',
  drawingNumber: 'КОС-В',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  rollBottom: 120,
  rollRight: 100,
  rollTop: 80,
  rollLeft: 100,
  weldOverlapMm: 10,
);

/// г) Скрин 2000/1000 × 1000, подворот низ/право/верх/лево = 80/80/100/100.
const _screenD = WindowParams(
  projectName: 'Косой скрин, пример Г',
  customer: 'Заказчик: пример Г',
  drawingNumber: 'КОС-Г',
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

void main() {
  setUpAll(loadRealFonts);

  testWidgets('пишет PNG-превью четырёх косых окон', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const a4Viewport = Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    const sheetViewport = Size(1720, 1080);

    final examples = <String, WindowParams>{
      'a': _trapezoidA,
      'b': _trapezoidB,
      'c': _trapezoidC,
      'g': _screenD,
    };

    final cases = <String, ({Size viewport, Widget Function(GlobalKey) build})>{};
    for (final entry in examples.entries) {
      final project = OrderProject(windows: [entry.value]);
      // 1. Чертёж окна с размерами и окантовкой по сторонам.
      cases['kosoe-primer-${entry.key}-chertezh'] = (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: project,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      );
      // 2. Лист «Раскрой»: фактическая трапеция с длинами четырёх сторон.
      cases['kosoe-primer-${entry.key}-raskroy'] = (
        viewport: sheetViewport,
        build: (key) => CutSheet(
          project: project,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      );
      // 3. Лист «Расходы»: площади, окантовка, люверсы, работа.
      cases['kosoe-primer-${entry.key}-rashody'] = (
        viewport: sheetViewport,
        build: (key) => CostsSheet(
          project: project,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      );
    }

    final directory = Directory('build/preview')..createSync(recursive: true);

    for (final entry in cases.entries) {
      final captureKey = GlobalKey();
      tester.view.physicalSize = entry.value.viewport;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: entry.value.build(captureKey)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '${entry.key}: вёрстка без переполнений');

      final bytes = await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final longest = math.max(boundary.size.width, boundary.size.height);
        final ratio = math.min(2.2, 10000 / longest);
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });

      final file = File('${directory.path}/${entry.key}.png')
        ..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }
  });
}
