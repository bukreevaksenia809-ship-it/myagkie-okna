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
  zippers: [ZipperSpec(centered: false, offsetMm: 500)],
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
  rollTop: 200,
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

/// Окно с двумя молниями, вырезами под трубу и спайкой с соседним окном.
const _rich = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-018',
  windowType: WindowType.lifting,
  bottomWidth: 2200,
  topWidth: 2200,
  leftHeight: 2400,
  rightHeight: 2400,
  rollBottom: 200,
  fastenerType: FastenerType.frenchLocks,
  zippers: [
    ZipperSpec(centered: false, offsetMm: 600),
    ZipperSpec(centered: false, offsetMm: 1500),
  ],
  cutouts: [
    Cutout(
      shape: CutoutShape.circle,
      width: 200,
      centerXMm: 1100,
      centerYMm: 1900,
    ),
    Cutout(width: 400, height: 300, centerXMm: 400, centerYMm: 700),
  ],
  weldedSides: [EdgeSide.right],
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

/// Окно со своими (нетиповыми) ширинами окантовки на каждую сторону:
/// низ 150, право 210, верх 95, лево 240 мм — полосы на чертеже разной
/// толщины.
const _customEdges = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-019',
  bottomWidth: 1800,
  topWidth: 1800,
  leftHeight: 2200,
  rightHeight: 2200,
  rollBottom: 150,
  rollRight: 210,
  rollTop: 95,
  rollLeft: 240,
);

/// Окно с припуском на раскрой: замер 2000 × 2000 мм, припуск +120 по ширине
/// и +80 по высоте, то есть изделие 2120 × 2080 мм.
const _allowance = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-020',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  allowanceWidthMm: 120,
  allowanceHeightMm: 80,
);

/// Окно, спаянное с соседом сверху и снизу (вертикальная спайка).
const _weldedVertically = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-021',
  bottomWidth: 1800,
  topWidth: 1800,
  leftHeight: 2200,
  rightHeight: 2200,
  weldedSides: [EdgeSide.top],
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
      'dve-molnii-vyrezy': (
        viewport: const Size(1720, 1180),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_rich]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'svoi-shiriny': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_customEdges]),
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
      'pripusk': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_allowance]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'pripusk-rashody': (
        viewport: const Size(1720, 1080),
        build: (key) => CostsSheet(
          project: const OrderProject(windows: [_allowance]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'spayka-vertikalnaya': (
        viewport: const Size(1720, 1080),
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_weldedVertically, _weldedVertically]),
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
