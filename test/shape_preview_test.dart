import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadRealFonts);

  Future<void> shot(
    WidgetTester tester,
    WindowParams params,
    String name,
    Widget Function(GlobalKey) build,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/preview/$name.png').writeAsBytesSync(bytes!);
  }

  const triangle = WindowParams(
    windowType: WindowType.triangle,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 1500,
    rightHeight: 1500,
  );
  const house = WindowParams(
    windowType: WindowType.house,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 1800,
    rightHeight: 1800,
    roofHeightMm: 500,
    roofOverhangMm: 80,
  );

  testWidgets('треугольник: чертёж и раскрой', (tester) async {
    await shot(
      tester,
      triangle,
      'treugolnik',
      (key) => DrawingSheet(
        project: const OrderProject(windows: [triangle]),
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );
    await shot(
      tester,
      triangle,
      'treugolnik-raskroy',
      (key) => CutSheet(
        project: const OrderProject(windows: [triangle]),
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );
  });

  testWidgets('домик: чертёж и раскрой', (tester) async {
    await shot(
      tester,
      house,
      'domik',
      (key) => DrawingSheet(
        project: const OrderProject(windows: [house]),
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );
    await shot(
      tester,
      house,
      'domik-raskroy',
      (key) => CutSheet(
        project: const OrderProject(windows: [house]),
        captureKey: key,
        labelFontFamily: testFontFamily,
      ),
    );
  });
}
