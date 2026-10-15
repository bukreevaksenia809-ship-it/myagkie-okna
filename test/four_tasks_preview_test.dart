// Превью четырёх правок заказчика: молния на скрине и окна без люверсов
// сверху/снизу. Пишет PNG в build/preview/, чтобы посмотреть глазами.
//
// Запуск: flutter test test/four_tasks_preview_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/costs_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

/// Скрин 2000 × 2000 с одной молнией по центру: полоса из скрина, шов 3 мм.
const _screenOneZipper = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-030',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 50,
  hemTopMm: 60,
  hemLeftMm: 40,
  zippers: [ZipperSpec(centered: true)],
);

/// Скрин с двумя молниями.
const _screenTwoZippers = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-031',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 50,
  hemTopMm: 60,
  hemLeftMm: 40,
  zippers: [
    ZipperSpec(centered: false, offsetMm: 600),
    ZipperSpec(centered: false, offsetMm: 1400),
  ],
);

/// ПВХ-окно 1500 × 2520 без люверсов сверху.
const _withoutTop = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-032',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  noEyeletsTop: true,
);

/// ПВХ-окно без люверсов снизу и сверху.
const _withoutBoth = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-033',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  noEyeletsTop: true,
  noEyeletsBottom: true,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('пишет PNG-превью молнии на скрине и сторон без люверсов', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const a4Viewport = Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );

    final cases = <String, ({Size viewport, Widget Function(GlobalKey) build})>{
      'skrin-molniya': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_screenOneZipper]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'skrin-dve-molnii': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_screenTwoZippers]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'skrin-molniya-rashody': (
        viewport: const Size(1720, 1080),
        build: (key) => CostsSheet(
          project: const OrderProject(windows: [_screenOneZipper]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'bez-lyuversov-sverhu': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_withoutTop]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'bez-lyuversov-sverhu-i-snizu': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_withoutBoth]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
    };

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
