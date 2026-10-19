// Тесты Т-образного окна: модель, геометрия, расход, JSON и смета.
//
// Основной пример заказчика: 2000 × 1500 плюс приставка 800 × 600 со
// смещением 200 мм. Окантовка 100 мм (готовая 50), запайка 5 мм, авто-припуск
// +10 мм к высоте отключён — числа в тестах считаются вручную.
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

WindowParams tWindow({
  TShapeSide side = TShapeSide.right,
  double offset = 200,
  bool welded = true,
  FilmMaterial material = FilmMaterial.clearPvc,
}) => WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: side,
  tWidth: 800,
  tHeight: 600,
  tOffset: offset,
  tWelded: welded,
  material: material,
  pvcHeightAllowanceEnabled: false,
);

void main() {
  tShapeSheetTests();

  group('Т-окно: модель', () {
    test('тип окна и поля приставки читаются и копируются', () {
      final params = tWindow();
      expect(params.isTShape, isTrue);
      expect(params.windowType.label, 'Т-образное');
      expect(params.tSide, TShapeSide.right);
      expect(params.tWidth, 800);
      expect(params.tHeight, 600);
      expect(params.tOffset, 200);
      expect(params.tWelded, isTrue);
      expect(params.isLifting, isFalse);
      expect(params.isFixedShape, isTrue);

      final copy = params.copyWith(
        tSide: TShapeSide.bottom,
        tWidth: 900,
        tHeight: 500,
        tOffset: 100,
        tWelded: false,
      );
      expect(copy.tSide, TShapeSide.bottom);
      expect(copy.tWidth, 900);
      expect(copy.tHeight, 500);
      expect(copy.tOffset, 100);
      expect(copy.tWelded, isFalse);
      // Обычное окно не становится Т-образным само по себе.
      expect(const WindowParams().isTShape, isFalse);
    });

    test('JSON: поля приставки переживают round-trip', () {
      final params = tWindow(side: TShapeSide.bottom, offset: 150);
      final json = windowToJson(params);
      expect(json['windowType'], 'tShape');
      expect(json['tSide'], 'bottom');
      expect(json['tWidth'], 800);
      expect(json['tHeight'], 600);
      expect(json['tOffset'], 150);
      expect(json['tWelded'], isTrue);

      final back = windowFromJson(json);
      expect(back.windowType, WindowType.tShape);
      expect(back.tSide, TShapeSide.bottom);
      expect(back.tWidth, 800);
      expect(back.tHeight, 600);
      expect(back.tOffset, 150);
      expect(back.tWelded, isTrue);

      final project = orderFromJson(
        orderToJson(OrderProject(windows: [params])),
      );
      expect(project.windows.first.isTShape, isTrue);
      expect(project.windows.first.tSide, TShapeSide.bottom);

      // Старый заказ без полей: обычное окно, значения по умолчанию.
      final legacy = windowFromJson(const <String, dynamic>{});
      expect(legacy.isTShape, isFalse);
      expect(legacy.tSide, TShapeSide.right);
      expect(legacy.tWidth, 800);
      expect(legacy.tHeight, 600);
      expect(legacy.tWelded, isTrue);
    });
  });

  group('Т-окно: геометрия, приставка справа', () {
    final params = tWindow();
    final spec = WindowSpec.of(params);
    final geometry = spec.geometry;

    test('контур: восемь вершин и длины всех сторон', () {
      expect(geometry.isTShape, isTrue);
      expect(geometry.corners, const [
        Offset(0, 0),
        Offset(2000, 0),
        Offset(2000, 200),
        Offset(2800, 200),
        Offset(2800, 800),
        Offset(2000, 800),
        Offset(2000, 1500),
        Offset(0, 1500),
      ]);
      // Стороны по обходу: низ 2000, правый низ 200, низ приставки 800,
      // право приставки 600, верх приставки 800, правый верх 700,
      // верх 2000, лево 1500.
      expect(geometry.sideLengths, [2000, 200, 800, 600, 800, 700, 2000, 1500]);
      expect(geometry.perimeter, 8600);
    });

    test('площадь полотна = сумма площадей двух частей', () {
      expect(geometry.areaMm2, closeTo(2000 * 1500 + 800 * 600, 1e-9));
      expect(spec.productAreaM2, closeTo(3.48, 1e-9));
      expect(geometry.spanX, 2800);
      expect(geometry.overallHeight, 1500);
    });

    test('расход окантовки — только внешние стороны', () {
      // Спайка по общей стороне: её длина 600 мм в расход не входит.
      expect(spec.layers.weldLengthMm, 600);
      expect(spec.layers.edgeConsumption, {100.0: 8600.0});
      // Длины изделия по сторонам: низ 2800, право 1500, верх 2800, лево 1500.
      final bySide = spec.layers.edgeLengthsBySide;
      expect(bySide[EdgeSide.bottom], 2800);
      expect(bySide[EdgeSide.top], 2800);
      expect(bySide[EdgeSide.right], 1500);
      expect(bySide[EdgeSide.left], 1500);
    });

    test('заготовка — контур с окантовкой по внешним сторонам', () {
      // ПВХ 50 готовой окантовки минус запайка 5 = 45 мм подреза с каждой
      // внешней стороны. Общая сторона припуска не имеет — там шов.
      expect(spec.layers.filmPolygons, hasLength(1));
      expect(spec.filmCutWidth, closeTo(2710, 1e-9));
      expect(spec.filmCutHeight, closeTo(1410, 1e-9));
      // Основное полотно: 1955 × 1410, приставка: 755 × 510.
      expect(spec.filmCutAreaM2, closeTo(3.1416, 1e-6));
      expect(spec.filmCutAreaWithShrinkageM2, closeTo(3.1416, 1e-6));
    });

    test('приставка снизу: контур, площадь и расход', () {
      final bottom = WindowSpec.of(tWindow(side: TShapeSide.bottom));
      expect(bottom.geometry.corners, const [
        Offset(0, 0),
        Offset(200, 0),
        Offset(200, -600),
        Offset(1000, -600),
        Offset(1000, 0),
        Offset(2000, 0),
        Offset(2000, 1500),
        Offset(0, 1500),
      ]);
      expect(bottom.geometry.sideLengths, [
        200,
        600,
        800,
        600,
        1000,
        1500,
        2000,
        1500,
      ]);
      expect(bottom.geometry.perimeter, 8200);
      expect(bottom.productAreaM2, closeTo(3.48, 1e-9));
      expect(bottom.layers.weldLengthMm, 800);
      expect(bottom.edgeConsumption, {100.0: 8200.0});
      final bySide = bottom.layers.edgeLengthsBySide;
      expect(bySide[EdgeSide.bottom], 2000);
      expect(bySide[EdgeSide.top], 2000);
      expect(bySide[EdgeSide.left], 2100);
      expect(bySide[EdgeSide.right], 2100);
      // Заготовка: 1955 × 1455 + 710 × 555 = 3,238575 м².
      expect(bottom.filmCutAreaM2, closeTo(3.1731, 1e-6));
    });

    test('приставка слева и сверху: контур и площадь симметричны', () {
      final left = WindowSpec.of(tWindow(side: TShapeSide.left));
      expect(left.productAreaM2, closeTo(3.48, 1e-9));
      expect(left.geometry.perimeter, 8600);
      expect(left.geometry.minX, -800);
      expect(left.layers.weldLengthMm, 600);

      final top = WindowSpec.of(tWindow(side: TShapeSide.top));
      expect(top.productAreaM2, closeTo(3.48, 1e-9));
      expect(top.geometry.perimeter, 8200);
      expect(top.geometry.maxY, 2100);
      expect(top.layers.weldLengthMm, 800);
    });
  });

  group('Т-окно без спайки: два отдельных окна', () {
    final spec = WindowSpec.of(tWindow(welded: false));

    test('площадь и расход считаются по двум частям раздельно', () {
      expect(spec.productAreaM2, closeTo(3.48, 1e-9));
      // Два периметра: 7000 + 2800 = 9800. Общей стороны в расходе нет —
      // каждая часть окантовывается целиком.
      expect(spec.edgeConsumption, {100.0: 9800.0});
      expect(spec.layers.weldLengthMm, 0);
      // Две заготовки: 1955 × 1410 и 710 × 510 = 3,11865 м².
      expect(spec.layers.filmPolygons, hasLength(2));
      expect(spec.filmCutAreaM2, closeTo(3.0552, 1e-6));
    });

    test('люверсы ставятся по периметру каждой части', () {
      expect(spec.eyeletCount, greaterThan(0));
      expect(spec.layers.eyeletPolygons, hasLength(2));
      expect(
        spec.layers.eyelets.any((eyelet) => eyelet.side == WindowSide.right),
        isTrue,
      );
    });
  });

  group('Т-окно: скрин', () {
    final params = tWindow(material: FilmMaterial.screen);
    final spec = WindowSpec.of(params);

    test('подворот по внешним сторонам, окантовки нет', () {
      expect(params.isScreen, isTrue);
      expect(spec.edgeConsumption, isEmpty);
      // Подворот 40/40: прибавка по оси (40 + 40) / 2 + 20 = 60, по 30 мм
      // наружу на кромку. Заготовка: 2030 × 1560 + 830 × 660 = 3,7146 м².
      expect(spec.layers.filmPolygons, hasLength(1));
      expect(spec.filmCutWidth, closeTo(2860, 1e-9));
      expect(spec.filmCutHeight, closeTo(1560, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(3.7146, 1e-6));
      expect(spec.layers.weldLengthMm, 600);
    });

    test('люверсы идут по всему внешнему контуру Т-формы', () {
      expect(spec.eyeletCount, greaterThan(0));
      expect(spec.layers.eyeletLine, hasLength(8));
      // Люверсы не ставятся на общую сторону: она внутри контура.
      final onShared = spec.layers.eyelets.where(
        (eyelet) =>
            (eyelet.center.dx - 2000).abs() < 1e-6 &&
            eyelet.center.dy > 200 &&
            eyelet.center.dy < 800,
      );
      expect(onShared, isEmpty);
    });
  });

  group('Т-окно: смета и техкарта', () {
    test('смета считается и включает обе части и шов', () {
      final params = tWindow();
      final prices = PriceList.defaults();
      final estimate = Estimate.ofWindow(params, prices);
      expect(estimate.total, greaterThan(0));

      final titles = estimate.lines.map((line) => line.title).join(' | ');
      expect(titles, contains('Окантовка'));
      expect(titles, contains('Люверсы'));

      // Полотно: площадь заготовки Т-окна (3,1416 м²) — в строке материала.
      final film = estimate.lines.firstWhere(
        (line) =>
            line.title.contains(params.material.thickness) ||
            line.title.contains('Полотно'),
      );
      expect(film.quantity, closeTo(3.1416, 1e-4));

      // Спайка по общей стороне — отдельная строка с длиной 0,6 м.
      final weld = estimate.lines.firstWhere(
        (line) => line.title.contains('общим сторонам Т-окна'),
      );
      expect(weld.quantity, closeTo(0.6, 1e-9));
      // Спайка с соседними окнами отдельной строкой не появляется.
      expect(
        estimate.lines.where((line) => line.title.contains('между окнами')),
        isEmpty,
      );
    });

    test('расход и техкарта: окантовка только по внешнему периметру', () {
      final params = tWindow();
      final summary = CostsSummary(OrderProject(windows: [params]));
      expect(summary.edgeByRoll, {100.0: 8600.0});
      expect(summary.weldLengthMm, 600);
      expect(summary.tShapeSeamMm, 600);
      expect(summary.productAreaM2, closeTo(3.48, 1e-9));
      expect(summary.filmAreaM2, closeTo(3.1416, 1e-6));

      final card = TechCard.forWindow(params);
      final edging = card.operations.firstWhere(
        (op) => op.kind == TechOperationKind.edging,
      );
      expect(edging.edgeTotals, {100.0: 8600.0});
      final edgeLength = edging.materials
          .where((material) => material.name.contains('полоса'))
          .fold<double>(0, (sum, material) => sum + (material.quantity ?? 0));
      expect(edgeLength, 8600);
      final weldOp = card.operations.where(
        (op) => op.kind == TechOperationKind.weldNeighbor,
      );
      expect(weldOp, isNotEmpty);
      expect(weldOp.first.text, contains(formatMm(600)));
    });

    test('техкарта показывает обе части приставки', () {
      final card = TechCard.forWindow(tWindow());
      final text = card.operations.map((op) => op.text).join('\n');
      expect(text, contains('Пристройка 1'));
      expect(text, contains(formatMm(800)));
      expect(text, contains(formatMm(600)));
      expect(text, contains(formatMm(200)));
    });

    test('техпроверки и раскладка на рулоне не падают на Т-окне', () {
      final params = tWindow();
      // Проверки параметров производства: Т-окно не должно давать исключений
      // и блокирующих ошибок.
      final checks = techChecksFor(params);
      expect(checks.where((check) => check.isBlocking), isEmpty);

      final plans = buildRollPlans(OrderProject(windows: [params]));
      expect(plans, hasLength(1));
      final plan = plans.single;
      expect(plan.layout.placements, hasLength(1));
      // На рулон укладывается габарит заготовки, площадь в документах —
      // фактическая (они не обязаны совпадать у Т-формы).
      final placement = plan.layout.placements.single;
      final spec = WindowSpec.of(params);
      // Заготовку можно повернуть на 90° — габарит должен совпасть с одним
      // из двух размеров.
      expect(
        {placement.width, placement.height},
        {
          closeTo(spec.filmCutWidthWithShrinkage, 1e-6),
          closeTo(spec.filmCutHeightWithShrinkage, 1e-6),
        },
      );
      expect(
        WindowSpec.of(params).filmCutAreaWithShrinkageM2,
        closeTo(3.1416, 1e-6),
      );
    });
  });
}

// --- Листы «Чертёж» и «Раскрой» для Т-окна ---------------------------------

void tShapeSheetTests() {
  group('Т-окно: листы', () {
    test('раскрой Т-окна: заготовка по фактической форме', () {
      final welded = CutSheet.piecesOf(
        OrderProject(windows: [tWindow()]),
      ).single;
      expect(welded.widthMm, closeTo(2710, 1e-9));
      expect(welded.heightMm, closeTo(1410, 1e-9));
      expect(welded.allContours, hasLength(1));
      // Восемь сторон заготовки: контур 8 600 минус 45 мм запайки на каждой.
      expect(welded.sideLengths, hasLength(8));
      expect(welded.sideLengths.reduce((a, b) => a + b), closeTo(8240, 1e-9));
      expect(welded.areaM2, closeTo(3.1416, 1e-6));

      final separate = CutSheet.piecesOf(
        OrderProject(windows: [tWindow(welded: false)]),
      ).single;
      expect(separate.allContours, hasLength(2));
      expect(separate.sideLengths, hasLength(8));
      // Две заготовки: 6 640 + 2 440 = 9 080 мм.
      expect(separate.sideLengths.reduce((a, b) => a + b), closeTo(9080, 1e-9));
      expect(separate.areaM2, closeTo(3.0552, 1e-6));
    });

    testWidgets('лист «Чертёж» рисует Т-окно без ошибок', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = OrderProject(windows: [tWindow()]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DrawingSheet(project: project)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Т-окно с молнией, вырезом и фартуком рисуется', (
      WidgetTester tester,
    ) async {
      final params = tWindow().copyWith(
        zippers: const [ZipperSpec(centered: true)],
        cutouts: const [
          Cutout(width: 300, height: 300, centerXMm: 700, centerYMm: 500),
        ],
        pocket: true,
        pocketWidth: 100,
      );
      final project = OrderProject(windows: [params]);
      // Все прежние элементы должны уживаться с Т-контуром и не ронять листы.
      expect(WindowSpec.of(params).eyeletCount, greaterThan(0));
      expect(WindowSpec.of(params).layers.zippers, hasLength(1));
      expect(WindowSpec.of(params).layers.cutouts, hasLength(1));

      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DrawingSheet(project: project)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('лист «Раскрой» рисует Т-окно без ошибок', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = OrderProject(windows: [tWindow(welded: false)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CutSheet(project: project)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
