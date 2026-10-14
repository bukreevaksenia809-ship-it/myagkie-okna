// Тесты технологической карты производства: состав и порядок операций,
// ключевые числа из модели окна, заказ из нескольких окон и PNG-превью листа.
//
// Запуск: flutter test test/tech_card_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/tech_card_sheet.dart';

import 'test_fonts.dart';

/// Окно 1500 × 2520 с молнией, карманом и люверсами по всему периметру.
const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-014',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  zippers: [ZipperSpec(centered: false, offsetMm: 500)],
  pocket: true,
);

/// Богатое подъёмное окно: две молнии, вырезы, спайка, карман, дренаж.
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
  eyeletType: EyeletType.oval42x22,
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
  pocket: true,
  drainHoles: true,
);

/// Простое глухое окно из москитной сетки.
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

TechOperation _op(TechCard card, TechOperationKind kind) =>
    card.operations.firstWhere((operation) => operation.kind == kind);

/// Суммы по ширинам рулонов, посчитанные по материалам операции «Окантовка».
Map<double, double> _edgeSumsFromMaterials(TechOperation operation) {
  final sums = <double, double>{};
  for (final material in operation.materials) {
    final roll = material.roll;
    if (roll == null) continue;
    sums[roll] = (sums[roll] ?? 0) + (material.quantity ?? 0);
  }
  return sums;
}

void main() {
  setUpAll(loadRealFonts);

  group('карта одного окна', () {
    final spec = WindowSpec.of(_window);
    final card = TechCard.forWindow(_window);

    test('содержит операции окна в технологическом порядке', () {
      final kinds = [for (final operation in card.operations) operation.kind];
      expect(kinds, contains(TechOperationKind.cutting));
      expect(kinds, contains(TechOperationKind.welding));
      expect(kinds, contains(TechOperationKind.edging));
      expect(kinds, contains(TechOperationKind.eyelets));
      expect(kinds, contains(TechOperationKind.zipper));
      expect(kinds, contains(TechOperationKind.pocket));
      expect(kinds, contains(TechOperationKind.control));

      // Номера идут подряд, «Контроль» — последняя операция.
      expect(
        [for (final operation in card.operations) operation.number],
        [for (var i = 1; i <= card.operations.length; i++) i],
      );
      expect(card.operations.last.kind, TechOperationKind.control);
      expect(card.operations.last.title, 'Контроль');
      expect(card.operations.last.control, contains('маркировка'));
    });

    test('раскрой плёнки совпадает с раскроем модели (с усадкой)', () {
      final cutting = _op(card, TechOperationKind.cutting);
      expect(cutting.title, 'Раскрой плёнки');

      final expectedSize =
          '${formatMm(spec.filmCutWidthWithShrinkage)} × '
          '${formatMm(spec.filmCutHeightWithShrinkage)} мм';
      expect(cutting.materials.first.size, expectedSize);
      expect(cutting.text, contains(formatMm(spec.filmCutWidthWithShrinkage)));
      expect(cutting.text, contains(formatMm(spec.filmCutHeightWithShrinkage)));
      expect(
        cutting.description,
        contains(formatPercent(_window.shrinkagePercent)),
      );
      expect(cutting.text, contains(formatMm(weldOverlap)));
    });

    test('напайка содержит режим сварки из примечаний приложения', () {
      final welding = _op(card, TechOperationKind.welding);
      expect(welding.text, contains('400–500'));
      expect(welding.text, contains(formatMm(weldOverlap)));
    });

    test('окантовка сходится с edgeConsumption по типам рулонов', () {
      final edging = _op(card, TechOperationKind.edging);
      final sums = _edgeSumsFromMaterials(edging);

      expect(sums.keys.toSet(), spec.edgeConsumption.keys.toSet());
      for (final entry in spec.edgeConsumption.entries) {
        expect(sums[entry.key], closeTo(entry.value, 1e-6));
        expect(edging.edgeTotals[entry.key], closeTo(entry.value, 1e-6));
      }
      // Готовая полоса — половина рулона.
      expect(edging.text, contains(formatMm(WindowParams.finishedEdgeWidth(100))));
      // Окантовка есть по каждой неспаянной стороне.
      expect(
        [
          for (final material in edging.materials) material.side,
        ].whereType<String>().toSet(),
        {'Низ', 'Право', 'Верх', 'Лево'},
      );
    });

    test('операция «Окантовка» показывает и пресеты, и свою ширину', () {
      final custom = _window.copyWith(rollBottom: 150);
      final edging = _op(TechCard.forWindow(custom), TechOperationKind.edging);

      // В описании — все пресеты и правило «половина рулона».
      expect(edging.text, contains('100 → 50'));
      expect(edging.text, contains('200 → 100'));
      expect(edging.text, contains('240 → 120'));
      // Своя ширина нижней стороны видна и в описании, и в позиции материала.
      expect(edging.text, contains('Тент 150 мм'));
      expect(
        edging.materials.any((m) => m.roll == 150 && m.side == 'Низ'),
        isTrue,
      );
    });

    test('люверсы: количество и шаг из модели', () {
      final eyelets = _op(card, TechOperationKind.eyelets);
      final pieces = [
        for (final material in eyelets.materials)
          if (material.unit == 'шт') material,
      ];
      expect(pieces, hasLength(1));
      expect(pieces.first.quantity, spec.eyeletCount);
      expect(spec.eyeletCount, greaterThan(0));
      expect(eyelets.text, contains(spec.eyeletStepLabel));
      expect(eyelets.text, contains('углах только круглые'));
      expect(eyelets.text, contains(formatMm(_window.eyeletCornerOffset)));
    });

    test('молния: количество и полоса тента из zipperBandPiece', () {
      final zipper = _op(card, TechOperationKind.zipper);
      final piece = spec.zipperBandPiece!;
      expect(zipper.text, contains(spec.zippersSummary));
      expect(zipper.text, contains(formatMm(piece.$2)));
      expect(zipper.text, contains(formatMm(_window.zipperBandWidth)));
      expect(
        zipper.materials.any(
          (material) => material.name.contains('Полоса тента под молнию №1'),
        ),
        isTrue,
      );
    });

    test('карман: тент 200 мм складывается пополам до 100 мм', () {
      final pocket = _op(card, TechOperationKind.pocket);
      expect(pocket.text, contains(formatMm(pocketRollWidth)));
      expect(pocket.text, contains(formatMm(_window.pocketWidth)));
      expect(_window.pocketWidth, pocketFinishedWidth);
      expect(pocket.materials.first.quantity, spec.geometry.bottomWidth);
    });
  });

  group('спайка с соседним окном', () {
    final base = TechCard.forWindow(_window);
    final weldedParams = _window.copyWith(weldedSides: const [EdgeSide.right]);
    final weldedSpec = WindowSpec.of(weldedParams);
    final welded = TechCard.forWindow(weldedParams);

    test('появляется операция про спайку', () {
      final weld = _op(welded, TechOperationKind.weldNeighbor);
      expect(weld.title, 'Спайка с соседним окном');
      expect(weld.text, contains(weldedSpec.weldSummary));
      expect(weld.text, contains(formatMm(weldedSpec.layers.weldLengthMm)));
      expect(weld.materials.first.side, 'Право');
    });

    test('окантовка по правой стороне исчезает', () {
      final edging = _op(welded, TechOperationKind.edging);
      expect(
        edging.materials.any((material) => material.side == 'Право'),
        isFalse,
      );
      expect(
        edging.materials.any((material) => material.side == 'Низ'),
        isTrue,
      );

      final sums = _edgeSumsFromMaterials(edging);
      expect(sums.keys.toSet(), weldedSpec.edgeConsumption.keys.toSet());
      for (final entry in weldedSpec.edgeConsumption.entries) {
        expect(sums[entry.key], closeTo(entry.value, 1e-6));
      }

      // Из расхода ушла ровно длина правой стороны.
      final rightLength = weldedSpec.geometry.sideLengths[1];
      expect(base.edgeTotalMm - welded.edgeTotalMm, closeTo(rightLength, 1e-6));
    });
  });

  test('карта заказа из трёх окон содержит три карты', () {
    const project = OrderProject(windows: [_window, _rich, _mesh]);
    final cards = TechCard.forOrder(project);

    expect(cards, hasLength(3));
    expect([for (final card in cards) card.index], [1, 2, 3]);
    expect(cards[0].title, 'Окно №1');
    expect(cards[2].title, 'Окно №3');
    expect(cards[1].params.drawingNumber, 'МО-018');

    // Порядок операций: раскрой раньше люверсов, «Контроль» — последний.
    for (final card in cards) {
      final kinds = [for (final operation in card.operations) operation.kind];
      expect(
        kinds.indexOf(TechOperationKind.cutting),
        lessThan(kinds.indexOf(TechOperationKind.eyelets)),
      );
      expect(card.operations.last.kind, TechOperationKind.control);
    }

    // Сводка по заказу собирается из карт.
    final totals = TechCard.orderEdgeTotals(cards);
    expect(
      totals.values.reduce((a, b) => a + b),
      closeTo(cards.fold(0, (sum, card) => sum + card.edgeTotalMm), 1e-6),
    );
    expect(
      TechCard.orderEyeletsByType(cards).values.reduce((a, b) => a + b),
      cards.fold(0, (sum, card) => sum + card.eyeletCount),
    );
  });

  testWidgets('лист техкарты строится и растёт под заказ', (tester) async {
    const project = OrderProject(windows: [_window, _rich, _mesh]);

    // Три окна с операциями не влезают в окно — лист должен вырасти.
    final size = TechCardSheet.sheetSize(project, const Size(1720, 1080));
    expect(size, isNotNull);
    expect(size!.height, greaterThan(1080));
    expect(size.width, greaterThanOrEqualTo(1360));

    final captureKey = GlobalKey();
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TechCardSheet(
            project: project,
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Технологическая карта'), findsOneWidget);
    expect(find.textContaining('Окно №1 —'), findsOneWidget);
    expect(find.textContaining('Окно №3 —'), findsOneWidget);
    expect(find.text('КОНТРОЛЬ'), findsNWidgets(3));
  });

  testWidgets('пустой заказ не роняет лист', (tester) async {
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TechCardSheet(
            project: const OrderProject(windows: []),
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('нет окон'), findsOneWidget);
    expect(find.text('Окон в заказе: 0'), findsOneWidget);
    expect(
      TechCardSheet.sheetSize(
        const OrderProject(windows: []),
        const Size(1720, 1080),
      ),
      isNull,
    );
  });

  testWidgets('пишет PNG-превью листа техкарты', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const single = OrderProject(windows: [_rich]);
    final order = _previewOrder();
    final cases = <String, ({Size viewport, OrderProject project})>{
      'tehkarta': (viewport: const Size(1720, 1080), project: single),
      'tehkarta-zakaz': (
        viewport:
            TechCardSheet.sheetSize(order, const Size(1720, 1080)) ??
            const Size(1720, 1080),
        project: order,
      ),
    };

    final directory = Directory('build/preview')..createSync(recursive: true);

    for (final entry in cases.entries) {
      final captureKey = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = entry.value.viewport;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: TechCardSheet(
              project: entry.value.project,
              captureKey: captureKey,
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bytes = await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
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

/// Заказ для превью: три разных окна, включая богатое подъёмное.
OrderProject _previewOrder() =>
    const OrderProject(windows: [_rich, _window, _mesh]);
