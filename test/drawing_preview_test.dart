// Генерирует PNG-превью листов в build/preview/, чтобы можно было
// посмотреть, как выглядит чертёж и раскладка, без запуска приложения.
//
// Лист чертежа — A4 в портретной ориентации (1240 × 1754 точки), поэтому
// превью чертежей снимается в размере листа: одна страница — одна A4,
// режим «Все окна» — несколько страниц, сшитых вертикально.
//
// Запуск: flutter test test/drawing_preview_test.dart
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
import 'package:soft_window_drawer/widgets/roll_sheet.dart';

import 'test_fonts.dart';

/// Пример заказчика: 1500 × 2520 мм, окантовка 100 мм (50 мм готовых).
/// Глухое окно с молнией и фартуком.
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

/// Скрин 2000 × 2000 с подворотом на каждую сторону: низ 40, право 50,
/// верх 60, лево 40 мм. Заготовка 2045 × 2070 мм (половина каждой стороны:
/// 20 + 25 по ширине и 20 + 30 + 20 по высоте), тента нет.
const _screen = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-022',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 50,
  hemTopMm: 60,
  hemLeftMm: 40,
  pocketTop: true,
);

/// Главный пример заказчика: скрин 2000 × 2000, подворот низ 40, право 40,
/// верх 60, лево 40 мм. Заготовка 2040 × 2070 мм: по высоте прибавляется
/// 20 + 30 + 20 = 70 мм, по ширине 20 + 20 = 40 мм.
const _screenHem40x60 = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-024',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 60,
  hemLeftMm: 40,
);

/// Косое окно-трапеция: низ 2000, верх 1000, высота 1000 мм.
const _trapezoid = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-040',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  weldOverlapMm: 25,
);

/// Прямоугольное окно с фартуком снизу и сверху: видно, что полосы идут от
/// внутреннего края окантовки до внешнего и немного дальше, не закрывая
/// люверсы и размеры.
const _aprons = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-041',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  pocket: true,
  pocketTop: true,
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

/// Окно с припуском на раскрой: изделие 2000 × 2000 мм, припуск +120 по
/// ширине и +80 по высоте. Изделие на чертеже остаётся 2000 × 2000, а плёнка
/// в раскрое кроится 2 070 × 2 030 мм (плюс усадка).
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

    // Чертежи снимаем ровно в размере листа A4 (1240 × 1754 на страницу),
    // табличные листы — в размере окна программы: у них свой формат.
    const a4Viewport = Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    const twoPagesViewport = Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height * 2 + 40,
    );
    const fivePagesViewport = Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height * 5 + 40,
    );

    final cases = <String, ({Size viewport, Widget Function(GlobalKey) build})>{
      'odno-okno': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_fixed]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'podyomnoe': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_liftingWide]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'zakaz-5-okon': (
        viewport: twoPagesViewport,
        build: (key) => DrawingSheet(
          project: _order,
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'zakaz-podrobno': (
        viewport: fivePagesViewport,
        build: (key) => DrawingSheet(
          project: _order.setGridColumns(1),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'dve-molnii-vyrezy': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_rich]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'skrin': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_screen]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'skrin-rashody': (
        viewport: const Size(1720, 1080),
        build: (key) => CostsSheet(
          project: const OrderProject(windows: [_screen]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      // Главный пример заказчика по подвороту: низ 40, верх 60 → высота
      // заготовки 2000 + 70 = 2070 мм, ширина +40 → 2040 мм.
      'skrin-podvorot-niz-40-verh-60': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_screenHem40x60]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      // Крепёж скрина — французский замок: размер берётся от подворота.
      'skrin-francuzskiy-zamok': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: OrderProject(
            windows: [_screen.copyWith(fastenerType: FastenerType.frenchLocks)],
          ),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      'svoi-shiriny': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_customEdges]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      // Косое окно: трапеция, а не габаритный прямоугольник.
      'trapetsiya': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_trapezoid]),
          captureKey: key,
          labelFontFamily: testFontFamily,
        ),
      ),
      // Фартук снизу и сверху: полупрозрачные полосы поверх окантовки.
      'fartuki': (
        viewport: a4Viewport,
        build: (key) => DrawingSheet(
          project: const OrderProject(windows: [_aprons]),
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
        viewport: a4Viewport,
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
        viewport: a4Viewport,
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
      // Раскладка окна с припуском: на рулон ложится заготовка с припуском.
      'raskladka-pripusk': (
        viewport: const Size(1720, 1080),
        build: (key) => RollSheet(
          project: const OrderProject(windows: [_allowance]),
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
        // Лист может быть длинным (несколько A4) — держим превью разумного
        // размера, чтобы файл можно было открыть и посмотреть глазами.
        final longest =
            math.max(boundary.size.width, boundary.size.height);
        final ratio = math.min(2.2, 10000 / longest);
        final image = await boundary.toImage(pixelRatio: ratio);
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

  testWidgets('легенда скрина подписывает выбранный крепёж по подвороту', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Тип крепежа → подпись в «Условных обозначениях».
    final cases = <FastenerType, String>{
      FastenerType.turnBuckles: 'Поворотная скоба по подвороту',
      FastenerType.frenchLocks: 'Французский замок по подвороту',
      FastenerType.straps: 'Силиконовый ремень по подвороту',
      FastenerType.eyeletsOnly: 'Саморезы по верхней кромке',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(
                windows: [_screen.copyWith(fastenerType: entry.key)],
              ),
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget,
          reason: 'крепёж ${entry.key}');
      expect(tester.takeException(), isNull);
    }
  });
}
