// Автоматическая раскладка 2–3 окон на одном A4: перебор вариантов,
// независимые повороты на 90°, точный масштаб, отсутствие обрезки и PDF
// ровно на одну страницу.
//
// Запуск: flutter test test/drawing_layout_test.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

/// Широкое окно: в узкой ячейке «2 в ряд» мешает ширина, после поворота —
/// наоборот, ширина становится высотой.
const _wideA = WindowParams(
  projectName: 'Раскладка',
  drawingNumber: 'МО-101',
  bottomWidth: 2600,
  topWidth: 2600,
  leftHeight: 1400,
  rightHeight: 1400,
);

const _wideB = WindowParams(
  projectName: 'Раскладка',
  drawingNumber: 'МО-102',
  bottomWidth: 2400,
  topWidth: 2400,
  leftHeight: 1200,
  rightHeight: 1200,
);

/// Высокие окна: в «2 в ряд» их ограничивает ширина ячейки.
const _tallA = WindowParams(
  projectName: 'Раскладка',
  drawingNumber: 'МО-103',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

const _tallB = WindowParams(
  projectName: 'Раскладка',
  drawingNumber: 'МО-104',
  bottomWidth: 1600,
  topWidth: 1600,
  leftHeight: 2500,
  rightHeight: 2500,
);

/// Т-окно с пристройкой: у него габарит шире самого полотна.
const _tShape = WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  pvcHeightAllowanceEnabled: false,
);

/// Разные окна для трёхоконной раскладки.
const _mixed = WindowParams(
  projectName: 'Раскладка',
  drawingNumber: 'МО-105',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 2000,
  rightHeight: 2000,
  pocket: true,
);

OrderProject _two(WindowParams a, WindowParams b) =>
    OrderProject(windows: [a, b], sheetMode: SheetMode.grid, gridColumns: 0);

OrderProject _three() => const OrderProject(
  windows: [_tallA, _wideB, _mixed],
  sheetMode: SheetMode.grid,
  gridColumns: 0,
);

/// Поле страницы A4 под план — с учётом фартука, как в самом виджете.
Size _gridAreaFor(OrderProject project) => DrawingSheet.optimizedGridArea(
  apronHeight: project.windows.any((w) => w.pocket || w.pocketTop) ? 32 : 0,
);

/// Масштаб, который давали СТАРЫЕ 2 колонки (gridColumns == 2), точек/мм.
///
/// Повторяет [_buildGridRow] и [_buildCell] старого листа: поля по 2 точки,
/// подпись окна 42 точки, внутренний отступ 4, поля чертежа по 100.
double _legacyTwoColumnScale(WindowParams params) {
  const pad = 100.0;
  const caption = 42.0;
  final area = DrawingSheet.optimizedGridArea();
  final cellWidth = (area.width - 4) / 2;
  final cellHeight = area.height - 4;
  final cellArea = Size(cellWidth - 4, cellHeight - 4 - caption);
  final spec = WindowSpec.of(params);
  final first = DrawingLayout(
    size: cellArea,
    geometry: spec.geometry,
    padLeft: pad,
    padRight: pad,
    padTop: pad,
    padBottom: pad,
    fitExactly: true,
  );
  // Рамка с запасом 2 точки, в ней painter рисует окончательный масштаб.
  final frame = Size(
    spec.geometry.spanX * first.scale + 2 * pad + 2,
    spec.geometry.spanY * first.scale + 2 * pad + 2,
  );
  return DrawingLayout(
    size: frame,
    geometry: spec.geometry,
    padLeft: pad,
    padRight: pad,
    padTop: pad,
    padBottom: pad,
    fitExactly: true,
  ).scale;
}

void main() {
  setUpAll(loadRealFonts);

  test('2 широких окна: авто-раскладка крупнее старых 2 колонок', () {
    final project = _two(_wideA, _wideB);
    final plan = DrawingSheet.optimizedGridPlan(
      project,
      DrawingSheet.optimizedGridArea(),
    );
    expect(plan, isNotNull);
    expect(plan!.cells, hasLength(2));

    final legacyA = _legacyTwoColumnScale(_wideA);
    final legacyB = _legacyTwoColumnScale(_wideB);
    // ignore: avoid_print
    print(
      '2 широких: ${plan.arrangement.label}, '
      'min=${plan.minScale.toStringAsFixed(4)} '
      '(1:${((96 / 25.4) / plan.minScale).toStringAsFixed(1)}), '
      'legacy=${legacyA.toStringAsFixed(4)}/${legacyB.toStringAsFixed(4)}, '
      'rot=${plan.cells.map((c) => c.quarterTurns).toList()}',
    );

    // Новый вариант крупнее САМОГО КРУПНОГО из старых окон — то есть
    // выигрывает у старых 2 колонок по каждому окну.
    expect(plan.minScale, greaterThan(legacyA));
    expect(plan.minScale, greaterThan(legacyB));
    // Поворот не обязан включаться всегда: для широких окон в столбце
    // выгоднее оставить их как есть. Главное — масштаб вырос.
    expect(plan.cells, hasLength(2));
  });

  test('2 высоких окна: раскладка/поворот не хуже старых 2 колонок', () {
    final project = _two(_tallA, _tallB);
    final plan = DrawingSheet.optimizedGridPlan(
      project,
      DrawingSheet.optimizedGridArea(),
    );
    expect(plan, isNotNull);
    final legacy = _legacyTwoColumnScale(_tallA);
    // ignore: avoid_print
    print(
      '2 высоких: ${plan!.arrangement.label}, '
      'min=${plan.minScale.toStringAsFixed(4)}, '
      'legacy=${legacy.toStringAsFixed(4)}, '
      'rot=${plan.cells.map((c) => c.quarterTurns).toList()}',
    );
    expect(plan.minScale, greaterThan(legacy));
    // Высокие окна в столбце выгодно повернуть на 90° — вместе с подписями.
    expect(plan.cells.every((cell) => cell.isRotated), isTrue);
  });

  test('3 окна: все три ячейки внутри A4, ничего не обрезано', () {
    final project = _three();
    final area = _gridAreaFor(project);
    final plan = DrawingSheet.optimizedGridPlan(project, area);
    expect(plan, isNotNull);
    expect(plan!.cells, hasLength(3));

    for (final cell in plan.cells) {
      // ignore: avoid_print
      print(
        '3 окна: №${cell.windowIndex + 1} ${plan.arrangement.label} '
        'rot=${cell.quarterTurns} scale=${cell.scale.toStringAsFixed(4)} '
        '1:${((96 / 25.4) / cell.scale).toStringAsFixed(1)} '
        'cell=${cell.rect.size} draw=${cell.drawingRect.size}',
      );
    }
    // Ячейки и рамки внутри A4, ничего не обрезано, масштаб точный.
    _expectPlanFits(plan, area);
    expect(plan.pad, greaterThanOrEqualTo(80));

    // Один A4, PDF резать нечего.
    expect(DrawingSheet.a4PageCount(project), 1);
    expect(
      DrawingSheet.safeBreakFractions(project, const Size(800, 600)),
      isNull,
    );
    final sheet = DrawingSheet.detailedSheetSize(
      project,
      const Size(800, 600),
    )!;
    expect(sheet.height, closeTo(DrawingSheet.a4Height + 40, 0.01));
    expect(sheet.width, closeTo(DrawingSheet.a4Width + 40, 0.01));
  });

  test('3 окна: разные наборы — план всегда внутри A4 и без обрезки', () {
    final sets = <List<WindowParams>>[
      const [_tallA, _tallB, _mixed],
      const [_wideA, _wideB, _mixed],
      const [_tallA, _wideA, _mixed],
      const [_wideB, _tallB, _mixed],
      const [_tallA, _tallB, _wideB],
      const [_tShape, _wideA, _mixed],
    ];
    var sawRotation = false;
    for (final windows in sets) {
      final project = OrderProject(
        windows: windows,
        sheetMode: SheetMode.grid,
        gridColumns: 0,
      );
      final apron = windows.any((w) => w.pocket || w.pocketTop) ? 32.0 : 0.0;
      final area = DrawingSheet.optimizedGridArea(apronHeight: apron);
      final plan = DrawingSheet.optimizedGridPlan(project, area);
      expect(plan, isNotNull);
      expect(plan!.cells, hasLength(3));
      _expectPlanFits(plan, area);
      sawRotation |= plan.hasRotations;
      expect(plan.scaleSummary, isNotEmpty);
    }
    // Хотя бы для одного набора перебор выбрал поворот — значит, вариант
    // «повернуть на 90°» реально участвует в выборе, а не только объявлен.
    expect(sawRotation, isTrue);
  });

  testWidgets('лист 2–3 окон строится на ширинах 360/390/430', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [360.0, 390.0, 430.0]) {
      for (final project in [_two(_wideA, _wideB), _three()]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DrawingSheet(
                project: project,
                labelFontFamily: testFontFamily,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(DrawingSheet),
          findsOneWidget,
          reason: 'ширина $width, окон ${project.windowCount}',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'ширина $width, окон ${project.windowCount}',
        );
      }
    }
  });

  testWidgets('PDF для 2 и 3 окон — ровно одна страница A4', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );

    const mmToPt = 72 / 25.4;
    for (final project in [_two(_wideA, _wideB), _three()]) {
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingSheet(
              project: project,
              captureKey: captureKey,
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bytes = await tester.runAsync(
        () => buildSheetPdf(
          captureKey: captureKey,
          params: project.selected,
          pixelRatio: 1,
          safeBreakFractions: DrawingSheet.safeBreakFractions(
            project,
            tester.view.physicalSize,
          ),
        ),
      );
      expect(bytes, isNotNull);
      final media = _mediaBoxes(bytes!);
      expect(
        media,
        hasLength(1),
        reason: 'окон ${project.windowCount}, страниц ${media.length}',
      );
      expect(media.single.widthPt, closeTo(210 * mmToPt, 2));
      expect(media.single.heightPt, closeTo(297 * mmToPt, 2));
    }
  });

  testWidgets('явные колонки остаются прежними, авто — без боковой панели', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );

    Future<void> pump(OrderProject project) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingSheet(
              project: project,
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // Явные «2 в ряд» для двух высоких окон: старая сетка без поворотов,
    // боковой панели у «2 в ряд» и раньше не было.
    await pump(
      const OrderProject(
        windows: [_tallA, _tallB],
        sheetMode: SheetMode.grid,
        gridColumns: 2,
      ),
    );
    expect(find.textContaining('поворот 90°'), findsNothing);
    expect(find.text('ОБОЗНАЧЕНИЯ'), findsOneWidget);

    // Одиночное окно не задето: подробный лист с боковой панелью.
    await pump(const OrderProject(windows: [_tallA]));
    expect(find.text('УСЛОВНЫЕ ОБОЗНАЧЕНИЯ'), findsOneWidget);

    // Явные «3 в ряд»: старая сетка без поворотов и без боковой панели —
    // для 2–3 окон её заменяет компактная легенда.
    await pump(
      const OrderProject(
        windows: [_tallA, _wideB, _mixed],
        sheetMode: SheetMode.grid,
        gridColumns: 3,
      ),
    );
    expect(find.byType(RotatedBox), findsNothing);
    expect(find.text('УСЛОВНЫЕ ОБОЗНАЧЕНИЯ'), findsNothing);
    expect(find.text('ОБОЗНАЧЕНИЯ'), findsOneWidget);

    // Авто: компактная легенда внизу, боковой панели нет.
    await pump(_three());
    expect(find.text('УСЛОВНЫЕ ОБОЗНАЧЕНИЯ'), findsNothing);
    expect(find.text('ОБОЗНАЧЕНИЯ'), findsOneWidget);
    // Точный масштаб виден в подписи окна.
    expect(find.textContaining(RegExp(r'М 1:\d')), findsWidgets);
  });

  testWidgets('повёрнутое окно подписано «поворот 90°» и точным масштабом', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: _two(_tallA, _tallB),
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Оба высоких окна повёрнуты — в подписи есть поворот и точный масштаб.
    expect(find.textContaining('поворот 90°'), findsNWidgets(2));
    expect(find.textContaining(RegExp(r'М 1:\d+,\d')), findsNWidgets(2));
  });

  test('формат точного масштаба не округляет до стандартного ряда', () {
    // 0,189 точек/мм — это ровно 1:20; 0,2 — уже 1:18,9 (не «красивое»).
    expect(formatExactScaleLabel((96 / 25.4) / 20), 'М 1:20,0');
    expect(formatExactScaleLabel((96 / 25.4) / 18.4), 'М 1:18,4');
    expect(formatExactScaleLabel(0), 'М 1:—');
  });
}

/// Общие проверки плана: ячейки и рамки не выходят за поле A4.
void _expectPlanFits(DrawingGridPlan plan, Size area) {
  final page = Rect.fromLTWH(0, 0, area.width, area.height);
  for (final cell in plan.cells) {
    expect(cell.rect.left, greaterThanOrEqualTo(page.left - 0.01));
    expect(cell.rect.top, greaterThanOrEqualTo(page.top - 0.01));
    expect(cell.rect.right, lessThanOrEqualTo(page.right + 0.01));
    expect(cell.rect.bottom, lessThanOrEqualTo(page.bottom + 0.01));
    expect(cell.drawingRect.left, greaterThanOrEqualTo(cell.rect.left));
    expect(cell.drawingRect.top, greaterThanOrEqualTo(cell.rect.top));
    expect(cell.drawingRect.right, lessThanOrEqualTo(cell.rect.right));
    expect(cell.drawingRect.bottom, lessThanOrEqualTo(cell.rect.bottom - 42));
    // Допуск на погрешность double: solver отсекает варианты с запасом 0,001.
    expect(
      cell.footprint.width,
      lessThanOrEqualTo(cell.available.width + 0.001),
    );
    expect(
      cell.footprint.height,
      lessThanOrEqualTo(cell.available.height + 0.001),
    );
    expect(cell.scale, greaterThan(0));
    expect(formatExactScaleLabel(cell.scale), startsWith('М 1:'));
  }
}

/// Размеры страниц PDF: ширина и высота MediaBox каждой страницы, в точках.
List<({double widthPt, double heightPt})> _mediaBoxes(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  return [
    for (final match in RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(text))
      _mediaBox(match.group(1)!),
  ];
}

({double widthPt, double heightPt}) _mediaBox(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  final left = double.parse(parts[0]);
  final bottom = double.parse(parts[1]);
  final right = double.parse(parts[2]);
  final top = double.parse(parts[3]);
  return (widthPt: right - left, heightPt: top - bottom);
}
