// Тесты расхода и сметы по крепежу подвижных сторон (Шаг 3).
//
// Люверсы считались и раньше, а сам крепёж — нет. Здесь проверяем:
// количество по типам в ведомости расхода, строки в смете (скоба, замок,
// ремень, саморез), отражение в листах «Смета» и «Расходы» и в техкарте,
// а также выключение строки крепежа тумблером прайса.
//
// Запуск: flutter test test/fastener_estimate_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/costs_sheet.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';

/// Скрин 2000 × 2000 с французским замком по подвороту: замок ставится по
/// низу и бокам, сверху — саморезы, в углах — круглые люверсы.
const _lockScreen = WindowParams(
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
  windowType: WindowType.lifting,
  fastenerType: FastenerType.frenchLocks,
  eyeletType: EyeletType.oval42x22,
);

/// Подъёмное ПВХ-окно 1500 × 2520 — база для скоб и ремней.
const _lifting = WindowParams(
  windowType: WindowType.lifting,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);


/// Французские замки: сумма левой и правой высот ÷ шаг, вверх до чётного,
/// +2 на заказ (см. CostsSummary).
int _frenchLocks(WindowParams params) {
  final raw = (params.leftHeight + params.rightHeight) / params.eyeletStep;
  var count = raw.ceil();
  if (count.isOdd) count += 1;
  return count + 2;
}

void main() {
  test('французский замок: счёт по вертикали и строка в смете', () {
    const project = OrderProject(windows: [_lockScreen]);
    final summary = CostsSummary(project);
    final spec = summary.specs.first;
    final prices = PriceList.defaults();
    final estimate = Estimate.of(project, prices);

    // Замок считается по вертикали: обе высоты ÷ шаг, вверх до чётного, +2.
    final expected = _frenchLocks(_lockScreen);
    expect(expected, greaterThan(0));
    expect(spec.layers.movableSideEyelets, isNotEmpty);
    expect(summary.fastenerCount[FastenerType.frenchLocks], expected);
    expect(summary.fastenerTotal, expected);

    final line = estimate.lines.firstWhere(
      (candidate) => candidate.title == 'Французский замок',
    );
    expect(line.quantity, expected);
    expect(line.unit, 'шт');
    expect(line.unitPrice, prices.frenchLockPrice);
    expect(line.unitPrice, 400);
    expect(line.amount, closeTo(expected * 400.0, 0.011));
    expect(line.group, EstimateGroup.hardware);
    expect(line.itemKey, PriceItemKeys.frenchLock);
    expect(line.note, contains('по вертикали'));

    // Люверс под замок остаётся отдельной строкой — это другая позиция.
    expect(
      estimate.lines.any(
        (candidate) => candidate.itemKey == PriceItemKeys.eyeletOval,
      ),
      isTrue,
    );
  });

  test('скобы: количество и сумма по цене прайса', () {
    const project = OrderProject(windows: [_lifting]);
    final summary = CostsSummary(project);
    final spec = summary.specs.first;
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(
      _lifting.copyWith(fastenerType: FastenerType.turnBuckles),
      prices,
    );

    final expected = spec.layers.movableSideEyelets.length;
    expect(expected, greaterThan(0));
    expect(summary.specs.first.params.fastenerType, FastenerType.turnBuckles);
    // Скоб ровно по числу точек низа и боков.
    expect(summary.fastenerCount[FastenerType.turnBuckles], expected);

    final line = estimate.lines.firstWhere(
      (candidate) => candidate.title == 'Поворотная скоба',
    );
    expect(line.quantity, expected);
    expect(line.unitPrice, prices.turnBucklePrice);
    expect(line.unitPrice, 220);
    expect(line.amount, closeTo(expected * 220.0, 0.011));
    expect(line.itemKey, PriceItemKeys.turnBuckle);
  });

  test('ремни-крепёж: отдельная строка от подъёмных ремней', () {
    final prices = PriceList.defaults();
    final params = _lifting.copyWith(fastenerType: FastenerType.straps);
    final summary = CostsSummary(OrderProject(windows: [params]));
    final estimate = Estimate.ofWindow(params, prices);

    final expected = WindowSpec.of(params).layers.movableSideEyelets.length;
    expect(summary.fastenerCount[FastenerType.straps], expected);
    expect(
      summary.strapCount,
      params.liftStrapCount,
      reason: 'подъёмные ремни — отдельно',
    );
    expect(summary.strapCount, 2, reason: 'окно 1500 мм — два ремня');

    final line = estimate.lines.firstWhere(
      (candidate) => candidate.title == 'Силиконовый ремень',
    );
    expect(line.quantity, expected);
    expect(line.unitPrice, prices.strapPrice);
    expect(line.unitPrice, 190);
    expect(line.amount, closeTo(expected * 190.0, 0.011));
    expect(line.itemKey, PriceItemKeys.strap);

    // Подъёмные ремни никуда не делись: это вторая строка того же материала.
    final liftLine = estimate.lines.firstWhere(
      (candidate) => candidate.title == 'Подъёмные ремни',
    );
    expect(liftLine.quantity, 2);
    expect(liftLine.itemKey, PriceItemKeys.strap);
  });

  test('«только люверсы»: строк крепежа нет ни в расходе, ни в смете', () {
    final prices = PriceList.defaults();
    // Подъёмные ремни у окна остаются (это другая позиция), поэтому ищем
    // именно строки крепежа подвижных сторон.
    final params = _lifting.copyWith(fastenerType: FastenerType.eyeletsOnly);
    final summary = CostsSummary(OrderProject(windows: [params]));
    final estimate = Estimate.ofWindow(params, prices);

    expect(summary.fastenerCount, isEmpty);
    expect(summary.fastenerTotal, 0);

    final titles = estimate.lines.map((line) => line.title).join(' | ');
    expect(titles, isNot(contains('Поворотная скоба')));
    expect(titles, isNot(contains('Французский замок')));
    expect(titles, isNot(contains('Силиконовый ремень')));
    // Люверсы при этом считаются как обычно.
    expect(
      estimate.lines.any((line) => line.title.startsWith('Люверсы')),
      isTrue,
    );
  });

  test('саморезы верхнего ряда: только у подъёмного окна и скрина', () {
    final prices = PriceList.defaults();
    final lifting = Estimate.ofWindow(
      _lifting.copyWith(fastenerType: FastenerType.turnBuckles),
      prices,
    );
    final topCount = WindowSpec.of(_lifting).layers.topEyelets.length;
    expect(topCount, greaterThan(0));

    final screw = lifting.lines.firstWhere(
      (candidate) => candidate.title == 'Саморезы верхнего ряда',
    );
    expect(screw.quantity, topCount);
    expect(screw.unitPrice, prices.screwPrice);
    expect(screw.unitPrice, 20);
    expect(screw.amount, closeTo(topCount * 20.0, 0.011));
    expect(screw.itemKey, PriceItemKeys.screw);

    // У глухого ПВХ верхнего ряда нет — саморезов в смете тоже нет.
    const fixed = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2520,
      rightHeight: 2520,
    );
    final fixedEstimate = Estimate.ofWindow(fixed, prices);
    expect(
      fixedEstimate.lines.any((line) => line.title == 'Саморезы верхнего ряда'),
      isFalse,
    );
    expect(CostsSummary(const OrderProject(windows: [fixed])).screwCount, 0);

    // Скрин — верх тоже на саморезах.
    expect(
      CostsSummary(const OrderProject(windows: [_lockScreen])).screwCount,
      WindowSpec.of(_lockScreen).layers.topEyelets.length,
    );
    final screenEstimate = Estimate.ofWindow(_lockScreen, prices);
    expect(
      screenEstimate.lines.any(
        (line) => line.title == 'Саморезы верхнего ряда',
      ),
      isTrue,
    );
  });

  test('выключение строки крепежа в прайсе убирает её из сметы', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_lockScreen, prices);
    final lockLine = full.lines.firstWhere(
      (line) => line.title == 'Французский замок',
    );
    expect(lockLine.amount, greaterThan(0));

    final off = Estimate.ofWindow(
      _lockScreen,
      prices.withItem(PriceItemKeys.frenchLock, enabled: false),
    );
    expect(off.lines.any((line) => line.title == 'Французский замок'), isFalse);
    expect(off.subtotal, closeTo(full.subtotal - lockLine.amount, 0.011));

    // Включение возвращает строку и сумму.
    final back = Estimate.ofWindow(
      _lockScreen,
      prices
          .withItem(PriceItemKeys.frenchLock, enabled: false)
          .withItem(PriceItemKeys.frenchLock, enabled: true),
    );
    expect(back.subtotal, closeTo(full.subtotal, 1e-9));

    // Тумблер ремня убирает строку силиконового ремня (та же позиция прайса).
    final straps = Estimate.ofWindow(
      _lifting.copyWith(fastenerType: FastenerType.straps),
      prices.withItem(PriceItemKeys.strap, enabled: false),
    );
    expect(
      straps.lines.any((line) => line.title == 'Силиконовый ремень'),
      isFalse,
    );
  });

  test('скрин с замком: строка замка есть и в смете, и в расходе', () {
    final summary = CostsSummary(const OrderProject(windows: [_lockScreen]));
    final estimate = Estimate.ofWindow(_lockScreen, PriceList.defaults());

    expect(summary.fastenerLabels, isNotEmpty);
    expect(
      summary.fastenerLabels.first,
      contains('Французский замок — ${summary.fastenerTotal} шт'),
    );
    final line = estimate.lines.firstWhere(
      (candidate) => candidate.title == 'Французский замок',
    );
    expect(line.amount, greaterThan(0));
    // Строка скрина: без окантовки и тента, как и раньше.
    final titles = estimate.lines.map((item) => item.title).join(' | ');
    expect(titles, isNot(contains('Окантовка')));
    expect(titles, isNot(contains('Тент')));
  });

  test('техкарта: материал крепежа совпадает с расходом по типу', () {
    final summary = CostsSummary(const OrderProject(windows: [_lockScreen]));
    final card = TechCard.forWindow(_lockScreen);
    final eyelets = card.operations.firstWhere(
      (operation) => operation.kind == TechOperationKind.eyelets,
    );
    final fastener = eyelets.materials.firstWhere(
      (material) => material.name.contains('французский замок'),
    );

    // В техкарте окна — счёт на окно; +2 шт идёт на заказ.
    final orderCount = summary.fastenerCount[FastenerType.frenchLocks]!;
    final perWindow = orderCount - 2;
    expect(fastener.quantity, closeTo(perWindow.toDouble(), 1e-9));
    expect(fastener.size, '$perWindow шт');
    expect(fastener.name, contains('французский замок'));
    // Верхний ряд — саморезы, их тоже столько же, сколько в расходе.
    expect(
      eyelets.materials.any(
        (material) =>
            material.name.contains('Саморезы по верхнему ряду') &&
            material.size == '${summary.screwCount} шт',
      ),
      isTrue,
    );
    expect(eyelets.description, contains('французский замок'));

    // «Только люверсы»: строки крепежа нет — техкарта сходится с расходом.
    final onlyEyelets =
        TechCard.forWindow(
          _lockScreen.copyWith(fastenerType: FastenerType.eyeletsOnly),
        ).operations.firstWhere(
          (operation) => operation.kind == TechOperationKind.eyelets,
        );
    expect(
      onlyEyelets.materials.any(
        (material) => material.name.contains('Крепёж низа и боков'),
      ),
      isFalse,
    );
    expect(
      onlyEyelets.description,
      contains('Отдельного крепежа низа и боков'),
    );
  });

  test('размер листа сметы — всегда один A4', () {
    for (final project in const [
      OrderProject(
        windows: [
          WindowParams(
            bottomWidth: 1500,
            topWidth: 1500,
            leftHeight: 2520,
            rightHeight: 2520,
          ),
        ],
      ),
      OrderProject(windows: [_lockScreen]),
    ]) {
      final size = EstimateSheet.sheetSize(project, const Size(1720, 1080));
      expect(size.width, EstimateSheet.a4Width + 40);
      expect(size.height, EstimateSheet.a4Height + 40);
    }
  });

  testWidgets('лист «Смета»: строка замка с суммой', (tester) async {
    tester.view.physicalSize = const Size(1720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prices = PriceList.defaults();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_lockScreen]),
            prices: prices,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Французский замок'), findsOneWidget);
    expect(find.textContaining('по вертикали'), findsOneWidget);
    expect(find.textContaining('Саморезы верхнего ряда'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('лист «Расходы»: крепёж в спецэлементах и итогах', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = CostsSummary(const OrderProject(windows: [_lockScreen]));
    final count = summary.fastenerTotal;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: CostsSheet(project: const OrderProject(windows: [_lockScreen])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // В спецэлементах окна — тип крепежа.
    expect(find.textContaining('французский замок'), findsWidgets);
    // В итогах — отдельный блок с крепежом по типам.
    expect(
      find.textContaining('Французский замок — $count шт'),
      findsOneWidget,
    );
    expect(find.textContaining('Всего крепежа: $count шт'), findsOneWidget);
    expect(
      find.textContaining('Саморезы верхнего ряда: ${summary.screwCount} шт'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
