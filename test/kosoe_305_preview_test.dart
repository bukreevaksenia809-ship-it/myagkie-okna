// Превью примера заказчика: косое окно 3 050/3 050 × 2 140/2 800,
// полоса 50 мм, запайка 20 мм.
//
// Пишет два PNG в build/preview/:
//  * raskroy-kosoe-305.png — лист «Раскрой» с косой заготовкой;
//  * chertezh-kosoe-305.png — лист «Чертёж» с размерами и цепочкой крепежа.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/label_settings.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

const _customer = WindowParams(
  projectName: 'Косое окно 305',
  customer: 'Заказчик',
  drawingNumber: 'КОС-305',
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
  eyeletStep: 300,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('пишет превью косого окна 305: раскрой и чертёж', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(LabelSettings.resetForTest);
    SharedPreferences.setMockInitialValues({});
    LabelSettings.resetForTest();

    final directory = Directory('build/preview')..createSync(recursive: true);
    const project = OrderProject(windows: [_customer]);

    Future<void> shoot(
      String name,
      Size viewport,
      Widget Function(GlobalKey) build,
    ) async {
      tester.view.physicalSize = viewport;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: build(key)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File('build/preview/$name.png')..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }

    final cutViewport =
        CutSheet.sheetSize(project, const Size(1720, 1080));
    await shoot(
      'raskroy-kosoe-305',
      cutViewport,
      (key) => CutSheet(
        project: project,
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );

    await shoot(
      'chertezh-kosoe-305',
      Size(DrawingSheet.a4Width + 40, DrawingSheet.a4Height + 40),
      (key) => DrawingSheet(
        project: project,
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );

    expect(directory.existsSync(), isTrue);
  });
}
