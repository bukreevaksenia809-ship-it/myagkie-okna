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

/// Окно 1500 × 2520 с молнией, фартуком и люверсами по всему периметру.
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

/// Богатое подъёмное окно: две молнии, вырезы, спайка, фартук, дренаж.
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

/// Скрин 2000 × 2000: подворот по сторонам (низ 40, право 50, верх 60,
/// лево 40 мм), заготовка 2100 × 2120, без тента.
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

/// Скрин 2000 × 2000 с молнией: полоса из скрина, шов 3 мм по краям.
const _screenZipper = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-023',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
  zippers: [ZipperSpec(centered: true)],
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

    test('раскрой плёнки совпадает с раскроем модели (авто-припуск ПВХ)', () {
      final cutting = _op(card, TechOperationKind.cutting);
      expect(cutting.title, 'Раскрой плёнки');

      final expectedSize =
          '${formatMm(spec.filmCutWidthWithShrinkage)} × '
          '${formatMm(spec.filmCutHeightWithShrinkage)} мм';
      expect(cutting.materials.first.size, expectedSize);
      expect(cutting.text, contains(formatMm(spec.filmCutWidthWithShrinkage)));
      expect(cutting.text, contains(formatMm(spec.filmCutHeightWithShrinkage)));
      // Усадка по умолчанию выключена, зато виден авто-припуск +10 мм к
      // высоте заготовки для ПВХ.
      expect(cutting.description, isNot(contains('плюс усадка')));
      expect(
        cutting.description,
        contains('авто +${formatMm(pvcHeightAllowanceMm)} мм к высоте'),
      );
      expect(cutting.text, contains(formatMm(defaultWeldOverlapMm)));
    });

    test('включённая усадка видна в раскрое карты', () {
      final params = _window.copyWith(
        shrinkageEnabled: true,
        shrinkagePercent: defaultShrinkagePercent,
      );
      final shrunkCard = TechCard.forWindow(params);
      final cutting = _op(shrunkCard, TechOperationKind.cutting);
      final shrunkSpec = WindowSpec.of(params);

      expect(
        cutting.description,
        contains('плюс усадка ${formatPercent(defaultShrinkagePercent)}'),
      );
      expect(cutting.text, contains(formatMm(shrunkSpec.filmCutWidthWithShrinkage)));
      expect(
        cutting.text,
        contains(formatMm(shrunkSpec.filmCutHeightWithShrinkage)),
      );
    });

    test('напайка содержит режим сварки из примечаний приложения', () {
      final welding = _op(card, TechOperationKind.welding);
      expect(welding.text, contains('400–500'));
      expect(welding.text, contains(formatMm(defaultWeldOverlapMm)));
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

    test('люверсы: в операции и заданный интервал, и фактический', () {
      final eyelets = _op(card, TechOperationKind.eyelets);
      final requested = formatMm(_window.eyeletStep);

      // Заданный интервал вводит пользователь; фактический не больше него.
      expect(eyelets.text, contains('интервал задан $requested мм'));
      expect(
        eyelets.text,
        contains('фактически ${spec.eyeletStepLabel} по сторонам'),
      );
      expect(eyelets.control, contains('Интервал задан $requested мм'));
      expect(eyelets.control, contains('фактический ${spec.eyeletStepLabel}'));
      expect(spec.eyeletStepMax, lessThanOrEqualTo(_window.eyeletStep));
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

    test('фартук: тент 200 мм складывается пополам до 100 мм', () {
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

  group('припуск на раскрой в техкарте', () {
    // Изделие 2000 × 2000, припуск +100/+100: плёнка кроится 2050 × 2050.
    const withAllowance = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      allowanceWidthMm: 100,
      allowanceHeightMm: 100,
    );
    const plain = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
    );

    test('раскрой — с припуском, окантовка и люверсы — по изделию', () {
      final card = TechCard.forWindow(withAllowance);
      final base = TechCard.forWindow(plain);
      final spec = WindowSpec.of(withAllowance);

      final cutting = _op(card, TechOperationKind.cutting);
      expect(cutting.title, 'Раскрой плёнки');
      expect(
        cutting.text,
        contains('припуск на раскрой +100 по ширине и +100 по высоте'),
      );
      expect(
        cutting.materials.first.size,
        '${formatMm(spec.filmCutWidthWithShrinkage)} × '
        '${formatMm(spec.filmCutHeightWithShrinkage)} мм',
      );
      expect(
        cutting.text,
        contains('${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²'),
      );

      // Окантовка и люверсы в припуске не нуждаются — числа те же.
      final edging = _op(card, TechOperationKind.edging);
      final baseEdging = _op(base, TechOperationKind.edging);
      expect(edging.edgeTotals, baseEdging.edgeTotals);
      expect(
        _op(card, TechOperationKind.eyelets).text,
        _op(base, TechOperationKind.eyelets).text,
      );

      // Контроль и спайка — по габариту изделия 2000 × 2000.
      expect(
        _op(card, TechOperationKind.control).text,
        contains('2\u202F000 × 2\u202F000 мм'),
      );
      expect(
        _op(card, TechOperationKind.control).text,
        isNot(contains(formatMm(spec.filmCutWidthWithAllowance))),
      );
      final weldCard = TechCard.forWindow(
        withAllowance.copyWith(weldedSides: const [EdgeSide.right]),
      );
      final weldBase = TechCard.forWindow(
        plain.copyWith(weldedSides: const [EdgeSide.right]),
      );
      expect(
        _op(weldCard, TechOperationKind.weldNeighbor).text,
        _op(weldBase, TechOperationKind.weldNeighbor).text,
      );
    });
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

  group('карта скрина', () {
    final card = TechCard.forWindow(_screen);

    test('есть раскрой и подворот, нет напайки и окантовки', () {
      final kinds = [for (final operation in card.operations) operation.kind];
      expect(kinds, contains(TechOperationKind.cutting));
      expect(kinds, contains(TechOperationKind.hem));
      expect(kinds, contains(TechOperationKind.eyelets));
      expect(kinds, isNot(contains(TechOperationKind.welding)));
      expect(kinds, isNot(contains(TechOperationKind.edging)));
      expect(kinds, isNot(contains(TechOperationKind.straps)));
      expect(kinds, isNot(contains(TechOperationKind.drain)));
      // Ни одна операция не упоминает тент или напайку скрина.
      expect(card.operations.map((op) => op.text).join(' '),
          isNot(contains('напайка')));
    });

    test('заготовка 2100 × 2120 и подворот по сторонам', () {
      final cutting = _op(card, TechOperationKind.cutting);
      expect(cutting.title, 'Раскрой скрина');
      // Прибавка по оси — удвоенный больший подворот этой оси:
      // ширина 2000 + 2 × max(лево 40, право 50) = 2100;
      // высота 2000 + 2 × max(низ 40, верх 60) = 2120.
      expect(cutting.text, contains(formatMm(2100)));
      expect(cutting.text, contains(formatMm(2120)));
      expect(cutting.text, isNot(contains('усадка 1,5')));

      final hem = _op(card, TechOperationKind.hem);
      expect(hem.text, contains('Подворот'));
      expect(hem.text, contains(formatMm(screenSeamMm)));
      expect(hem.text, contains('низ ${formatMm(_screen.hemBottomMm)}'));
      expect(hem.text, contains('право ${formatMm(_screen.hemRightMm)}'));
      expect(hem.text, contains('верх ${formatMm(_screen.hemTopMm)}'));
      expect(hem.text, contains('лево ${formatMm(_screen.hemLeftMm)}'));
      // Материалы операции — по одной строке на каждую сторону.
      final sides = hem.materials.where((m) => m.side != null).toList();
      expect(sides, hasLength(4));
      expect(hem.materials.first.side, 'Низ');
      expect(hem.materials.first.size, '${formatMm(_screen.hemBottomMm)} мм');
      expect(
        hem.materials.any((m) => m.name.contains('периметру')),
        isTrue,
      );
      expect(hem.source, contains('hemBottomMm'));
    });

    test('люверсы ставятся по подвороту, крепёж — по низу и бокам', () {
      final eyelets = _op(card, TechOperationKind.eyelets);
      expect(eyelets.text, contains('по подвороту'));
      expect(eyelets.text, contains('поворотные скобы'));
      expect(eyelets.text, contains('Сверху саморезы'));
      expect(eyelets.text, isNot(contains('только люверсы')));
      // Верх остаётся на саморезах, низ и бока — на выбранном крепеже.
      expect(
        eyelets.materials
            .any((material) => material.name.contains('Саморезы по верхнему ряду')),
        isTrue,
      );
      final fastener = eyelets.materials.firstWhere(
        (material) => material.name.contains('Крепёж низа и боков'),
      );
      expect(fastener.name, contains('поворотные скобы'));
      expect(fastener.name, contains('по подвороту'));
      expect(fastener.note, contains('подворот'));
      expect(
        fastener.quantity,
        closeTo(card.spec.layers.movableSideEyelets.length.toDouble(), 1e-9),
      );
    });

    test('крепёж скрина: замки, ремни и «только люверсы»', () {
      TechOperation eyeletsFor(FastenerType type) => _op(
            TechCard.forWindow(_screen.copyWith(fastenerType: type)),
            TechOperationKind.eyelets,
          );

      final locks = eyeletsFor(FastenerType.frenchLocks);
      expect(locks.text, contains('французский замок'));
      expect(
        locks.materials
            .any((material) => material.name.contains('французский замок')),
        isTrue,
      );

      final straps = eyeletsFor(FastenerType.straps);
      expect(straps.text, contains('силиконовые ремни'));
      expect(
        straps.materials
            .any((material) => material.name.contains('силиконовые ремни')),
        isTrue,
      );

      final onlyEyelets = eyeletsFor(FastenerType.eyeletsOnly);
      expect(onlyEyelets.text, contains('Только люверсы'));
      expect(onlyEyelets.text, contains('по подвороту'));
      // Отдельной строки крепежа нет: люверсы уже посчитаны выше.
      expect(
        onlyEyelets.materials
            .any((material) => material.name.contains('Крепёж низа и боков')),
        isFalse,
      );
      // Верх всё равно на саморезах.
      expect(
        onlyEyelets.materials
            .any((material) => material.name.contains('Саморезы по верхнему ряду')),
        isTrue,
      );
    });

    test('верхний фартук считается и подписан', () {
      final pocket = _op(card, TechOperationKind.pocket);
      expect(pocket.title, contains('сверху'));
      expect(pocket.text, contains(formatMm(_screen.pocketWidth)));
      expect(pocket.materials.first.quantity,
          closeTo(_screen.topWidth, 1e-9));
    });

    test('молния скрина — полоса из скрина со швом 3 мм', () {
      final zipperCard = TechCard.forWindow(_screenZipper);
      final zipper = _op(zipperCard, TechOperationKind.zipper);

      expect(zipper.text, contains('Вшить'));
      expect(zipper.text, contains('скрина'));
      expect(zipper.text, contains('швом ${formatMm(screenSeamMm)} мм'));
      expect(zipper.text, contains(formatMm(minScreenZipperHemMm)));
      expect(zipper.text, isNot(contains('напайк')));
      expect(
        zipper.materials.any(
          (material) => material.name.contains('Полоса скрина под молнию №1'),
        ),
        isTrue,
      );
      final band = zipper.materials.firstWhere(
        (material) => material.name.contains('Полоса скрина под молнию'),
      );
      expect(band.size, '${formatMm(50)} × ${formatMm(2000)} мм');
      expect(band.note, contains('шов ${formatMm(screenSeamMm)} мм'));
    });

    test('сторона без люверсов честно указана в операции', () {
      final params = _screen.copyWith(
        noEyeletsTop: true,
        noEyeletsBottom: true,
      );
      final eyelets = _op(
        TechCard.forWindow(params),
        TechOperationKind.eyelets,
      );

      expect(eyelets.text, contains('Люверсы не ставятся на сторонах'));
      expect(eyelets.text, contains('низ и верх'));
      expect(eyelets.text, contains('сторона остаётся без крепежа'));
    });
  });

  group('люверс любого типа на любом окне', () {
    const fixedOval = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      eyeletType: EyeletType.oval42x22,
    );

    test('глухое окно: овальные по сторонам, круглые в углах', () {
      final eyelets =
          _op(TechCard.forWindow(fixedOval), TechOperationKind.eyelets);

      expect(eyelets.text, contains(EyeletType.oval42x22.label.toLowerCase()));
      expect(eyelets.text, contains('углах только круглые'));
      final oval = eyelets.materials.firstWhere(
        (material) => material.name.contains(EyeletType.oval42x22.label),
      );
      final round = eyelets.materials.firstWhere(
        (material) => material.name.contains(EyeletType.round10.label),
      );
      // 24 люверса: 4 угла круглые, 20 по сторонам — овальные.
      expect(oval.quantity, 20);
      expect(round.quantity, 4);
      expect(round.name, contains('в углах'));
    });
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
    const OrderProject(windows: [_rich, _window, _mesh, _screen]);
