// Тесты Т-окна с ДВУМЯ пристройками: угловая форма.
//
// Основной пример: полотно 2000 × 1500, пристройка 1 — 800 × 600 справа со
// смещением 200, пристройка 2 — 700 × 500 снизу со смещением 300. Окантовка
// 100 мм (готовая 50), запайка 5 мм, авто-припуск +10 мм к высоте отключён,
// чтобы числа считались вручную.
//
// Контур — объединение трёх прямоугольников; окантовка и подворот идут только
// по внешним рёбрам, внутренние стороны пристроек — швы. Швы считаются по
// каждой пристройке отдельно. Без спайки каждая часть — отдельное окно.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/roll_plan.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/services/tech_checks.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

/// Угловое Т-окно: пристройка 800 × 600 справа (смещение 200) и
/// 700 × 500 снизу (смещение 300).
WindowParams twoAnnexWindow({
  bool welded1 = true,
  bool welded2 = true,
  TShapeSide side2 = TShapeSide.bottom,
  FilmMaterial material = FilmMaterial.clearPvc,
}) => WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  tWelded: welded1,
  t2Enabled: true,
  t2Side: side2,
  t2Width: 700,
  t2Height: 500,
  t2Offset: 300,
  t2Welded: welded2,
  material: material,
  pvcHeightAllowanceEnabled: false,
);

void main() {
  twoAnnexGeometryRules();
  twoAnnexSheetRules();
  twoAnnexJsonRules();
}

// --- Геометрия, площадь, швы, заготовка, расход -----------------------------

void twoAnnexGeometryRules() {
  group('Т-окно с двумя пристройками: геометрия', () {
    final params = twoAnnexWindow();
    final spec = WindowSpec.of(params);
    final geometry = spec.geometry;

    test('общий контур — объединение трёх прямоугольников', () {
      // 12 вершин: низ пристройки 2, её бока, низ основного полотна справа,
      // пристройка 1 справа, верх и левая кромка.
      expect(geometry.isTShape, isTrue);
      expect(geometry.corners, const [
        Offset(0, 0),
        Offset(300, 0),
        Offset(300, -500),
        Offset(1000, -500),
        Offset(1000, 0),
        Offset(2000, 0),
        Offset(2000, 200),
        Offset(2800, 200),
        Offset(2800, 800),
        Offset(2000, 800),
        Offset(2000, 1500),
        Offset(0, 1500),
      ]);
      // Обход: 300 + 500 + 700 + 500 + 1000 + 200 + 800 + 600 + 800 + 700 +
      // 2000 + 1500 = 9600 мм. Внутренние стороны пристроек (600 и 700)
      // в периметр не входят — там швы.
      expect(geometry.sideLengths, [
        300,
        500,
        700,
        500,
        1000,
        200,
        800,
        600,
        800,
        700,
        2000,
        1500,
      ]);
      expect(geometry.perimeter, 9600);
    });

    test('площадь полотна — сумма площадей трёх частей', () {
      expect(geometry.areaMm2, closeTo(2000 * 1500 + 800 * 600 + 700 * 500, 1e-9));
      expect(spec.productAreaM2, closeTo(3.83, 1e-9));
      expect(geometry.spanX, 2800);
      // Высота изделия — от низа пристройки 2 до верха основного полотна.
      expect(geometry.overallHeight, 2000);
      expect(geometry.minY, -500);
      expect(geometry.maxY, 1500);
    });

    test('швы — по каждой пристройке отдельно', () {
      expect(spec.tAnnexes, hasLength(2));
      expect(spec.tAnnexes[0].sharedLength, 600);
      expect(spec.tAnnexes[1].sharedLength, 700);
      expect(spec.tSeamsLength, 1300);
      expect(spec.tWeldedSeamLength, 1300);
      expect(spec.layers.weldLengthMm, 1300);
      // Отдельных (несваренных) частей нет.
      expect(spec.layers.tAnySeparate, isFalse);
    });

    test('окантовка — только по внешним рёбрам', () {
      expect(spec.layers.edgeConsumption, {100.0: 9600.0});
      final bySide = spec.layers.edgeLengthsBySide;
      expect(bySide[EdgeSide.bottom], 2800);
      expect(bySide[EdgeSide.top], 2800);
      expect(bySide[EdgeSide.right], 2000);
      expect(bySide[EdgeSide.left], 2000);
    });

    test('заготовка — прямоугольник по каждой части', () {
      // Внешние стороны подрезаны на 45 мм (50 − запайка 5), общие стороны —
      // нет, там шов.
      final parts = spec.layers.partBlankRects;
      expect(parts, hasLength(3));
      expect(parts[0].width, closeTo(1955, 1e-9));
      expect(parts[0].height, closeTo(1455, 1e-9));
      expect(parts[1].width, closeTo(755, 1e-9));
      expect(parts[1].height, closeTo(510, 1e-9));
      expect(parts[2].width, closeTo(610, 1e-9));
      expect(parts[2].height, closeTo(455, 1e-9));
      // Сумма прямоугольников: 2 844 525 + 385 050 + 277 550 = 3 507 125 мм².
      expect(spec.filmCutAreaM2, closeTo(3.507125, 1e-6));
      expect(spec.layers.filmPolygons, hasLength(1));
      expect(spec.filmCutWidth, closeTo(2710, 1e-9));
      expect(spec.filmCutHeight, closeTo(1910, 1e-9));
      expect(spec.filmPartBounds, hasLength(3));
    });

    test('чертёж и смета видят обе пристройки и оба шва', () {
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.productAreaM2, closeTo(3.83, 1e-9));
      expect(summary.edgeByRoll, {100.0: 9600.0});
      expect(summary.weldLengthMm, 1300);
      expect(summary.tShapeSeamMm, 1300);
      expect(summary.filmAreaM2, closeTo(3.507125, 1e-6));

      final estimate = Estimate.ofWindow(params, PriceList.defaults());
      final film = estimate.lines.firstWhere(
        (line) => line.title.startsWith('Полотно'),
      );
      expect(film.quantity, closeTo(3.507125, 1e-6));
      // Каждый шов — отдельная операция: пристройка 1 — 0,6 м,
      // пристройка 2 — 0,7 м.
      final seams = estimate.lines
          .where((line) => line.title.contains('Т-окна') &&
              line.title.contains('Спайка'))
          .toList();
      expect(seams, hasLength(2));
      expect(seams[0].title, contains('пристройки 1'));
      expect(seams[0].quantity, closeTo(0.6, 1e-9));
      expect(seams[1].title, contains('пристройки 2'));
      expect(seams[1].quantity, closeTo(0.7, 1e-9));

      final card = TechCard.forWindow(params);
      final text = card.operations.map((op) => op.text).join('\n');
      expect(text, contains('Пристройка 1'));
      expect(text, contains('Пристройка 2'));
      expect(text, contains(formatMm(700)));
      expect(text, contains(formatMm(500)));
      expect(text, contains(formatMm(300)));
      final weld = card.operations.firstWhere(
        (op) => op.kind == TechOperationKind.weldNeighbor,
      );
      final weldSizes = weld.materials
          .where((material) => material.name.contains('пристройки'))
          .map((material) => material.quantity)
          .toList();
      expect(weldSizes, hasLength(2));
      expect(weldSizes[0], 600);
      expect(weldSizes[1], 700);
    });

    test('рулон, люверсы и техпроверки не падают', () {
      expect(spec.eyeletCount, greaterThan(0));
      expect(spec.layers.eyeletPolygons, hasLength(1));
      final plans = buildRollPlans(OrderProject(windows: [params]));
      expect(plans, hasLength(1));
      final placement = plans.single.layout.placements.single;
      expect(
        {placement.width, placement.height},
        {
          closeTo(spec.filmCutWidthWithShrinkage, 1e-6),
          closeTo(spec.filmCutHeightWithShrinkage, 1e-6),
        },
      );
      expect(techChecksFor(params).where((check) => check.isBlocking), isEmpty);
    });
  });

  group('Т-окно с двумя пристройками без спайки', () {
    final params = twoAnnexWindow(welded1: false, welded2: false);
    final spec = WindowSpec.of(params);

    test('каждая часть — отдельное окно со своим контуром', () {
      expect(spec.tSeamsLength, 1300);
      expect(spec.tWeldedSeamLength, 0);
      expect(spec.layers.weldLengthMm, 0);
      // Три периметра: 7000 + 2800 + 2400 = 12 200 мм.
      expect(spec.layers.edgeConsumption, {100.0: 12200.0});
      expect(spec.layers.filmPolygons, hasLength(3));
      expect(spec.layers.tAnySeparate, isTrue);
      // Заготовки: 1955 × 1410, 710 × 510 и 610 × 410.
      expect(spec.filmCutAreaM2, closeTo(3.3053, 1e-6));
      expect(spec.layers.partBlankRects, hasLength(3));
    });

    test('контур изделия и площадь те же, швов нет', () {
      expect(spec.geometry.corners, WindowSpec.of(twoAnnexWindow()).geometry.corners);
      expect(spec.productAreaM2, closeTo(3.83, 1e-9));
      expect(spec.tAnnexConflict, isNull);
      expect(spec.layers.eyeletPolygons, hasLength(3));
      expect(spec.eyeletCount, greaterThan(0));
    });

    test('смета и техкарта описывают отдельные окна', () {
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.tShapeSeamMm, 0);
      expect(summary.weldLengthMm, 0);
      expect(spec.tShapeSummary, contains('без спайки'));
      expect(spec.notes.join('\n'), contains('отдельные окна'));
    });
  });

  group('Т-окно с двумя пристройками: скрин', () {
    final params = twoAnnexWindow(material: FilmMaterial.screen);
    final spec = WindowSpec.of(params);

    test('подворот по внешнему контуру, окантовки нет', () {
      expect(params.isScreen, isTrue);
      expect(spec.edgeConsumption, isEmpty);
      // В заготовку идёт половина каждой стороны: по ширине +20, по высоте
      // +30 на кромку. Заготовка-объединение: 2840 × 2060,
      // площадь — 4,024 м².
      expect(spec.filmCutWidth, closeTo(2840, 1e-9));
      expect(spec.filmCutHeight, closeTo(2060, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(4.024, 1e-6));
      expect(spec.layers.filmPolygons, hasLength(1));
      expect(spec.layers.screenHemPolygons, hasLength(1));
      expect(spec.eyeletCount, greaterThan(0));
    });
  });

  group('Т-окно: две пристройки на одной стороне запрещены', () {
    final params = twoAnnexWindow(side2: TShapeSide.right);
    final spec = WindowSpec.of(params);

    test('в расчёте остаётся только первая пристройка', () {
      expect(params.tAnnexSideConflict, isTrue);
      expect(spec.tAnnexConflict, isNotNull);
      expect(spec.tAnnexes, hasLength(1));
      // Контур — как у Т-окна с одной пристройкой справа.
      expect(spec.geometry.corners, const [
        Offset(0, 0),
        Offset(2000, 0),
        Offset(2000, 200),
        Offset(2800, 200),
        Offset(2800, 800),
        Offset(2000, 800),
        Offset(2000, 1500),
        Offset(0, 1500),
      ]);
      expect(spec.productAreaM2, closeTo(3.48, 1e-9));
      expect(spec.tSeamsLength, 600);
      // Расчёт не ломается: смета, техкарта и рулон считаются.
      expect(
        Estimate.ofWindow(params, PriceList.defaults()).total,
        greaterThan(0),
      );
      expect(TechCard.forWindow(params).operations, isNotEmpty);
      expect(buildRollPlans(OrderProject(windows: [params])), hasLength(1));
      expect(techChecksFor(params).where((check) => check.isBlocking), isEmpty);
      // Проверка параметров объясняет, что поменять.
      final issue = validateParams(params).firstWhere(
        (issue) => issue.message.contains('одной стороне'),
      );
      expect(issue.isWarning, isTrue);
      expect(issue.isError, isFalse);
    });

    test('панель показывает предупреждение о конфликте', () {
      expect(spec.tShapeSummary, contains('одной стороне'));
    });
  });

  group('Т-окно: вторая пристройка и обратная совместимость', () {
    test('copyWith управляет второй пристройкой', () {
      final base = twoAnnexWindow();
      final copy = base.copyWith(
        t2Enabled: false,
        t2Side: TShapeSide.top,
        t2Width: 900,
        t2Height: 400,
        t2Offset: 50,
        t2Welded: false,
        tEnabled: false,
      );
      expect(copy.t2Enabled, isFalse);
      expect(copy.t2Side, TShapeSide.top);
      expect(copy.t2Width, 900);
      expect(copy.t2Height, 400);
      expect(copy.t2Offset, 50);
      expect(copy.t2Welded, isFalse);
      expect(copy.tEnabled, isFalse);
      final spec = WindowSpec.of(copy);
      // Обе пристройки выключены — просто прямоугольное полотно.
      expect(spec.tAnnexes, isEmpty);
      expect(spec.productAreaM2, closeTo(3.0, 1e-9));
      expect(spec.geometry.corners, const [
        Offset(0, 0),
        Offset(2000, 0),
        Offset(2000, 1500),
        Offset(0, 1500),
      ]);
    });

    test('JSON: вторая пристройка переживает round-trip', () {
      final params = twoAnnexWindow(side2: TShapeSide.left);
      final json = windowToJson(params);
      expect(json['t2Enabled'], isTrue);
      expect(json['t2Side'], 'left');
      expect(json['t2Width'], 700);
      expect(json['t2Height'], 500);
      expect(json['t2Offset'], 300);
      expect(json['t2Welded'], isTrue);
      expect(json['tEnabled'], isTrue);

      final back = windowFromJson(json);
      expect(back.isTShape, isTrue);
      expect(back.t2Enabled, isTrue);
      expect(back.t2Side, TShapeSide.left);
      expect(back.t2Width, 700);
      expect(back.t2Height, 500);
      expect(back.t2Offset, 300);
      expect(back.t2Welded, isTrue);
      expect(back.tEnabled, isTrue);

      final project = orderFromJson(
        orderToJson(OrderProject(windows: [params])),
      );
      expect(project.windows.first.hasSecondAnnex, isTrue);
      expect(project.windows.first.t2Side, TShapeSide.left);
    });

    test('старый заказ: вторая пристройка выключена', () {
      // Старый JSON без полей t2* и tEnabled — прежнее Т-окно с одной
      // пристройкой, контур не меняется.
      final legacy = windowFromJson(const {
        'windowType': 'tShape',
        'bottomWidth': 2000,
        'topWidth': 2000,
        'leftHeight': 1500,
        'rightHeight': 1500,
        'tSide': 'right',
        'tWidth': 800,
        'tHeight': 600,
        'tOffset': 200,
        'tWelded': true,
      });
      expect(legacy.tEnabled, isTrue);
      expect(legacy.t2Enabled, isFalse);
      expect(legacy.hasSecondAnnex, isFalse);
      expect(legacy.t2Side, TShapeSide.bottom);
      final spec = WindowSpec.of(legacy);
      expect(spec.tAnnexes, hasLength(1));
      expect(spec.productAreaM2, closeTo(3.48, 1e-9));
      expect(spec.tSeamsLength, 600);
    });

    test('signature меняется от второй пристройки', () {
      final base = twoAnnexWindow();
      expect(
        base.copyWith(t2Offset: 310).signature,
        isNot(base.signature),
      );
      expect(
        base.copyWith(t2Enabled: false).signature,
        isNot(base.signature),
      );
      expect(
        base.copyWith(t2Welded: false).signature,
        isNot(base.signature),
      );
    });
  });
}

// --- Листы «Чертёж» и «Раскрой», A4 -----------------------------------------

void twoAnnexSheetRules() {
  group('Т-окно с двумя пристройками: листы', () {
    test('раскрой — общий контур с двумя швами отдельными операциями', () {
      final piece = CutSheet.piecesOf(
        OrderProject(windows: [twoAnnexWindow()]),
      ).single;
      expect(piece.widthMm, closeTo(2710, 1e-9));
      expect(piece.heightMm, closeTo(1910, 1e-9));
      // Один общий контур (сварено всё), 12 сторон заготовки.
      expect(piece.allContours, hasLength(1));
      expect(piece.sideLengths, hasLength(12));
      expect(piece.areaM2, closeTo(3.507125, 1e-6));

      final separate = CutSheet.piecesOf(
        OrderProject(windows: [twoAnnexWindow(welded1: false, welded2: false)]),
      ).single;
      expect(separate.allContours, hasLength(3));
      expect(separate.sideLengths, hasLength(12));
      expect(separate.areaM2, closeTo(3.3053, 1e-6));
    });

    testWidgets('лист «Чертёж» (A4) рисует угловое Т-окно без ошибок', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(windows: [twoAnnexWindow()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('лист «Раскрой» рисует угловое Т-окно без ошибок', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CutSheet(
              project: OrderProject(windows: [twoAnnexWindow()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('лист «Чертёж» рисует конфликт пристроек без исключений', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(
                windows: [twoAnnexWindow(side2: TShapeSide.right)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

// --- JSON: отдельные мелкие проверки ----------------------------------------

void twoAnnexJsonRules() {
  test('вторая пристройка по умолчанию выключена у обычного окна', () {
    const params = WindowParams();
    expect(params.t2Enabled, isFalse);
    expect(params.hasSecondAnnex, isFalse);
    expect(params.tAnnexes, isEmpty);
    expect(windowFromJson(windowToJson(params)).t2Enabled, isFalse);
  });
}
