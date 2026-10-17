// Тесты цен на крепёж (Шаг 2): скоба, французский замок, саморез верхнего ряда.
//
// Проверяем значения по умолчанию, JSON (включая старый прайс без полей),
// строки панели «Прайс-лист» и блок «Цены прайса» листа «Смета».
//
// Запуск: flutter test test/fastener_price_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

/// Подъёмное окно 1500 × 2520 — на нём крепёж подвижных сторон.
const _window = WindowParams(
  windowType: WindowType.lifting,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

/// То же окно, но подвижные стороны крепятся французским замком: в смете
/// появляется строка PriceItemKeys.frenchLock.
const _frenchWindow = WindowParams(
  windowType: WindowType.lifting,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  fastenerType: FastenerType.frenchLocks,
);

void main() {
  test('цены крепежа по умолчанию осмысленны и упорядочены', () {
    const prices = PriceList.defaults();

    expect(prices.turnBucklePrice, defaultTurnBucklePrice);
    expect(prices.frenchLockPrice, defaultFrenchLockPrice);
    expect(prices.screwPrice, defaultScrewPrice);
    // Ремень уже был в прайсе — цена та же, одна позиция на оба вида.
    expect(prices.strapPrice, defaultStrapPrice);
    expect(prices.strapPrice, 190);

    // Значения — как в комментариях-обоснованиях у констант.
    expect(prices.turnBucklePrice, 220);
    expect(prices.frenchLockPrice, 400);
    expect(prices.screwPrice, 20);

    // Порядок цен: расходник-саморез дешевле люверса, скоба дороже овального
    // люверса, замок дороже скобы.
    expect(prices.screwPrice, lessThan(prices.eyeletPrice));
    expect(prices.turnBucklePrice, greaterThan(prices.eyeletOvalPrice));
    expect(prices.frenchLockPrice, greaterThan(prices.turnBucklePrice));
  });

  test('JSON: цены крепежа сохраняются и читаются', () {
    final source = PriceList.defaults().copyWith(
      turnBucklePrice: 245.5,
      frenchLockPrice: 430,
      screwPrice: 18.25,
      strapPrice: 205,
    );
    final restored = PriceList.fromJson(source.toJson());

    expect(restored.turnBucklePrice, 245.5);
    expect(restored.frenchLockPrice, 430);
    expect(restored.screwPrice, 18.25);
    expect(restored.strapPrice, 205);
    expect(restored.toJson(), equals(source.toJson()));

    // Старый прайс без цен крепежа читается дефолтами, а не нулями.
    final json = PriceList.defaults().toJson()
      ..remove('turnBucklePrice')
      ..remove('frenchLockPrice')
      ..remove('screwPrice');
    final old = PriceList.fromJson(json);
    expect(old.turnBucklePrice, defaultTurnBucklePrice);
    expect(old.frenchLockPrice, defaultFrenchLockPrice);
    expect(old.screwPrice, defaultScrewPrice);

    // Битые значения — тоже дефолты (цена не бывает отрицательной).
    final broken = PriceList.fromJson({
      'turnBucklePrice': 'дорого',
      'frenchLockPrice': -1,
      'screwPrice': null,
    });
    expect(broken.turnBucklePrice, defaultTurnBucklePrice);
    expect(broken.frenchLockPrice, defaultFrenchLockPrice);
    expect(broken.screwPrice, defaultScrewPrice);
  });

  test('цена французского замка меняет смету и выключается тумблером', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_frenchWindow, prices);
    final lock = full.lines.singleWhere(
      (line) => line.itemKey == PriceItemKeys.frenchLock,
    );

    // Замок посчитан по количеству крепежа подвижных сторон.
    expect(lock.quantity, greaterThan(0));
    expect(lock.unitPrice, defaultFrenchLockPrice);
    expect(lock.amount, closeTo(lock.quantity * defaultFrenchLockPrice, 0.011));

    // Правка строки прайса меняет сумму строки и весь итог.
    final raised = Estimate.ofWindow(
      _frenchWindow,
      prices.copyWith(frenchLockPrice: 500),
    );
    final raisedLine = raised.lines.singleWhere(
      (line) => line.itemKey == PriceItemKeys.frenchLock,
    );
    expect(raisedLine.unitPrice, 500);
    expect(
      raisedLine.amount - lock.amount,
      closeTo(lock.quantity * 100, 0.011),
    );
    expect(raised.total, greaterThan(full.total));

    // Тумблер «учитывать в смете» убирает и строку, и её сумму.
    final without = Estimate.ofWindow(
      _frenchWindow,
      prices.withItem(PriceItemKeys.frenchLock, enabled: false),
    );
    expect(
      without.lines.any((line) => line.itemKey == PriceItemKeys.frenchLock),
      isFalse,
    );
    expect(without.subtotal, closeTo(full.subtotal - lock.amount, 0.011));
    expect(without.total, lessThan(full.total));
  });

  test('тумблеры скобы и самореза работают как у остальных строк', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_window, prices);

    for (final key in const [PriceItemKeys.turnBuckle, PriceItemKeys.screw]) {
      final line = full.lines.singleWhere((line) => line.itemKey == key);
      expect(line.amount, greaterThan(0), reason: 'строка $key не пустая');

      final without = Estimate.ofWindow(
        _window,
        prices.withItem(key, enabled: false),
      );
      expect(
        without.lines.any((line) => line.itemKey == key),
        isFalse,
        reason: 'выключенная позиция $key уходит из сметы',
      );
      expect(
        without.subtotal,
        closeTo(full.subtotal - line.amount, 0.011),
        reason: 'уходит ровно сумма $key',
      );
    }
  });

  testWidgets('панель прайса: строки крепежа есть, правятся и выключаются', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 4800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PriceHostState>();
    await tester.pumpWidget(_PriceHost(key: hostKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pumpAndSettle();

    // Строки на месте и с ценами по умолчанию.
    expect(find.text('Поворотная скоба, ₽/шт'), findsOneWidget);
    expect(find.text('Французский замок, ₽/шт'), findsOneWidget);
    expect(find.text('Саморез верхнего ряда, ₽/шт'), findsOneWidget);
    expect(find.text('Ремень, ₽/шт'), findsOneWidget);
    final prices = hostKey.currentState!.prices;
    expect(prices.turnBucklePrice, 220);
    expect(prices.frenchLockPrice, 400);
    expect(prices.screwPrice, 20);

    // Тумблеры у новых позиций тоже есть.
    for (final key in const [
      PriceItemKeys.turnBuckle,
      PriceItemKeys.frenchLock,
      PriceItemKeys.screw,
    ]) {
      expect(find.byKey(ValueKey('price-toggle-$key')), findsOneWidget);
    }

    // Правка цены уходит в модель.
    Future<void> setRow(String label, String value) async {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      await tester.enterText(
        find.descendant(of: row, matching: find.byType(TextField)),
        value,
      );
      await tester.pumpAndSettle();
    }

    await setRow('Поворотная скоба, ₽/шт', '245');
    await setRow('Французский замок, ₽/шт', '430');
    await setRow('Саморез верхнего ряда, ₽/шт', '18');
    final edited = hostKey.currentState!.prices;
    expect(edited.turnBucklePrice, 245);
    expect(edited.frenchLockPrice, 430);
    expect(edited.screwPrice, 18);

    // Правка строки панели сразу меняет смету окна с французским замком.
    final lockLine = Estimate.ofWindow(_frenchWindow, edited).lines.singleWhere(
      (line) => line.itemKey == PriceItemKeys.frenchLock,
    );
    expect(lockLine.unitPrice, 430);

    // Выключение позиции крепежа видно в модели и убирает строку из сметы.
    final toggle = find.byKey(const ValueKey('price-toggle-frenchLock'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      hostKey.currentState!.prices.isEnabled(PriceItemKeys.frenchLock),
      isFalse,
    );
    expect(
      Estimate.ofWindow(_frenchWindow, hostKey.currentState!.prices)
          .lines
          .any((line) => line.itemKey == PriceItemKeys.frenchLock),
      isFalse,
    );
    // Панель 420 px: переполнений нет.
    expect(tester.takeException(), isNull);
  });

  testWidgets('лист «Смета»: цены крепежа в блоке «Цены прайса»', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpSheet(PriceList prices) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: EstimateSheet(
              project: const OrderProject(windows: [_window]),
              prices: prices,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpSheet(PriceList.defaults());
    expect(find.textContaining('Поворотная скоба — 220,00 ₽/шт'), findsOneWidget);
    expect(
      find.textContaining('Французский замок — 400,00 ₽/шт'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Саморез верхнего ряда — 20,00 ₽/шт'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ремень: подъёмный и силиконовый — 190,00 ₽/шт'),
      findsOneWidget,
    );

    // Цены — из прайса: меняются вместе с моделью.
    await pumpSheet(
      PriceList.defaults().copyWith(
        turnBucklePrice: 260,
        frenchLockPrice: 450,
        screwPrice: 25,
      ),
    );
    expect(find.textContaining('Поворотная скоба — 260,00 ₽/шт'), findsOneWidget);
    expect(
      find.textContaining('Французский замок — 450,00 ₽/шт'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Саморез верхнего ряда — 25,00 ₽/шт'),
      findsOneWidget,
    );

    // Выключенная позиция помечена на листе.
    await pumpSheet(
      PriceList.defaults().withItem(PriceItemKeys.frenchLock, enabled: false),
    );
    expect(
      find.textContaining('Французский замок — 400,00 ₽/шт · выключено'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Панель прайса с живым состоянием: правки уходят в модель.
class _PriceHost extends StatefulWidget {
  const _PriceHost({super.key});

  @override
  State<_PriceHost> createState() => _PriceHostState();
}

class _PriceHostState extends State<_PriceHost> {
  PriceList prices = PriceList.defaults();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: PricePanel(
              prices: prices,
              onChanged: (value) => setState(() => prices = value),
            ),
          ),
        ),
      ),
    );
  }
}
