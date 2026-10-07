// Генерирует PNG-превью листов в build/preview/, чтобы можно было
// посмотреть, как выглядит чертёж и раскладка, без запуска приложения.
//
// Запуск: flutter test test/drawing_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/costs_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/roll_sheet.dart';

import 'test_fonts.dart';

/// Пример заказчика: 1500 × 2520 мм, окантовка 100 мм (50 мм готовых).
/// Глухое окно с молнией и карманом.
const _fixed = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-014',
  windowType: WindowType.fixed,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  zipperEnabled: true,
  zipperCentered: false,
  zipperOffsetMm: 500,
  pocket: true,
);

/// Подъёмное окно: сверху люверсы, ниже скобы, висят ремни, внизу рулон.
const _lifting = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-015',
  windowType: WindowType.lifting,
  bottomWidth: 1400,
  topWidth: 1400,
  leftHeight: 1800,
  rightHeight: 1800,
  rollTop: EdgeRoll.roll200,
  fastenerType: FastenerType.turnBuckles,
  drainHoles: true,
  drainCount: 3,
);

/// Широкое подъёмное окно — три подъёмных ремня.
const _liftingWide = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-016',
  windowType: WindowType.lifting,
  bottomWidth: 2600,
  topWidth: 2600,
  leftHeight: 2000,
  rightHeight: 2000,
  fastenerType: FastenerType.turnBuckles,
  drainHoles: true,
);

/// Окно из москитной сетки.
const _mesh = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-017',
  material: FilmMaterial.mosquitoNet,
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _order = OrderProject(
  windows: [_fixed, _lifting, _fixed, _liftingWide, _mesh],
  sheetMode: SheetMode.grid,
  gridColumns: 3,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('строит PNG-превью листов', (tester) async {
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Для каждого листа — свой размер окна: подробный режим длиннее экрана.
    final cases = <String, ({Size viewport, Widget Function(GlobalKey) build})>{
      'odno-okno': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_fixed]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'podyomnoe': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_liftingWide]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'zakaz-5-okon': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: _order,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'zakaz-podrobno': (
        viewport: const Size(1500, 3400),
        build: (key) => DrawingSheet(
          project: _order.setGridColumns(1),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'rashody': (
        viewport: const Size(1720, 1080),
        build: (key) => CostsSheet(
          project: _order,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'raskladka': (
        viewport: const Size(1720, 1080),
        build: (key) => RollSheet(
          project: _order,
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
        final image = await boundary.toImage(pixelRatio: 2.2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });

      final file = File('${directory.path}/chertezh-${entry.key}.png')
        ..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }
  });
}
