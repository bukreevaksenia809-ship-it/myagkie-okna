// Превью чертежа и раскроя в сантиметрах.
//
// Запуск: flutter test test/units_preview_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-СМ',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('пишет превью чертежа и раскроя в сантиметрах', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DisplayUnits.setUnit(LengthUnit.cm);
    addTearDown(DisplayUnits.resetForTest);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    final directory = Directory('build/preview')..createSync(recursive: true);

    // 1. Чертёж A4 в см.
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    final drawingKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DrawingSheet(
            project: const OrderProject(windows: [_window]),
            captureKey: drawingKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('см'), findsWidgets,
        reason: 'подписи листа переведены в см');

    final drawingBytes = await tester.runAsync(() async {
      final boundary = drawingKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final longest = math.max(boundary.size.width, boundary.size.height);
      final ratio = math.min(2.2, 10000 / longest);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final drawingFile = File('${directory.path}/chertezh-v-sm.png')
      ..writeAsBytesSync(drawingBytes!);
    expect(drawingFile.lengthSync(), greaterThan(5000));

    // 2. Раскрой в см.
    const project = OrderProject(windows: [_window]);
    final viewport =
        CutSheet.sheetSize(project, const Size(1720, 1080));
    tester.view.physicalSize = viewport;
    final cutKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: CutSheet(
            project: project,
            captureKey: cutKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('размеры в см'), findsOneWidget);

    final cutBytes = await tester.runAsync(() async {
      final boundary = cutKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final cutFile = File('${directory.path}/raskroy-v-sm.png')
      ..writeAsBytesSync(cutBytes!);
    expect(cutFile.lengthSync(), greaterThan(5000));
    // ignore: avoid_print
    print('Превью записано: ${drawingFile.path}');
    // ignore: avoid_print
    print('Превью записано: ${cutFile.path}');
  });
}
