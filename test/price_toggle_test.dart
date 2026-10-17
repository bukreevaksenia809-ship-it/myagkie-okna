// Тесты включения/выключения позиций прайса (Шаг 1).
//
// Выключенная позиция остаётся в прайсе с ценой, но в смету не идёт:
// строка не создаётся вовсе. Проверяем модель, JSON, смету и тумблеры панели
// шириной 420 px.
//
// Запуск: flutter test test/price_toggle_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

/// Типовое окно 1500 × 2520 (глухое, всё по умолчанию).
const _window = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

/// Скрин 1500 × 1500 — второй материал в заказе для проверки, что тумблер
/// полотна убирает только свою строку.
const _screen = WindowParams(
  material: FilmMaterial.screen,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 1500,
  rightHeight: 1500,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
);

void main() {
  test('выключение позиции убирает сумму из сметы, включение возвращает', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_window, prices);

    final labor = full.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.labor,
    );
    expect(labor.amount, greaterThan(0));

    final without = prices.withItem(PriceItemKeys.labor, enabled: false);
    final reduced = Estimate.ofWindow(_window, without);

    // Строки нет вовсе — нулевая строка не засоряет лист.
    expect(
      reduced.lines.any((line) => line.itemKey == PriceItemKeys.labor),
      isFalse,
    );
    expect(reduced.subtotal, closeTo(full.subtotal - labor.amount, 0.011));
    expect(reduced.total, lessThan(full.total));
    // Остальные позиции на месте: выключили ровно одну.
    expect(reduced.lines.length, full.lines.length - 1);

    // Включение возвращает позицию и прежнюю сумму.
    final back = Estimate.ofWindow(
      _window,
      without.withItem(PriceItemKeys.labor, enabled: true),
    );
    expect(back.subtotal, closeTo(full.subtotal, 1e-9));
    expect(back.total, closeTo(full.total, 1e-9));
  });

  test('выключенный материал полотна убирает только свою строку', () {
    const project = OrderProject(windows: [_window, _screen]);
    final prices = PriceList.defaults();
    final full = Estimate.of(project, prices);
    final clearLine = full.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.filmClear,
    );
    final screenLine = full.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.filmScreen,
    );

    final reduced = Estimate.of(
      project,
      prices.withItem(PriceItemKeys.filmClear, enabled: false),
    );
    expect(
      reduced.lines.any((line) => line.itemKey == PriceItemKeys.filmClear),
      isFalse,
    );
    // Скрин считается: выключен только прозрачный ПВХ.
    expect(
      reduced.lines.any((line) => line.itemKey == PriceItemKeys.filmScreen),
      isTrue,
    );
    expect(
      reduced.subtotal,
      closeTo(full.subtotal - clearLine.amount, 0.011),
      reason: 'уходит ровно стоимость полотна ПВХ',
    );
    expect(screenLine.amount, greaterThan(0));
  });

  test('выключенная окантовка: строка рулона не считается', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_window, prices);
    final edgeLines =
        full.lines.where((line) => line.itemKey == PriceItemKeys.edge100);
    expect(edgeLines, isNotEmpty, reason: 'по умолчанию окантовка 100 мм');

    final reduced = Estimate.ofWindow(
      _window,
      prices.withItem(PriceItemKeys.edge100, enabled: false),
    );
    expect(
      reduced.lines.any((line) => line.itemKey == PriceItemKeys.edge100),
      isFalse,
    );
  });

  test('выключенный крепёж-позиция: люверсы и установка', () {
    final prices = PriceList.defaults();
    final full = Estimate.ofWindow(_window, prices);
    final roundLine = full.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.eyeletRound,
    );
    expect(roundLine.unitPrice, prices.eyeletPrice + prices.eyeletInstall);

    // Выключение установки убирает из цены люверса только надбавку.
    final noInstall = Estimate.ofWindow(
      _window,
      prices.withItem(PriceItemKeys.eyeletInstall, enabled: false),
    );
    final noInstallLine = noInstall.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.eyeletRound,
    );
    expect(noInstallLine.unitPrice, prices.eyeletPrice);
    expect(noInstallLine.note, contains('без установки'));
    expect(noInstall.subtotal, lessThan(full.subtotal));

    // Выключение самого люверса убирает строку целиком.
    final noRound = Estimate.ofWindow(
      _window,
      prices.withItem(PriceItemKeys.eyeletRound, enabled: false),
    );
    expect(
      noRound.lines.any((line) => line.itemKey == PriceItemKeys.eyeletRound),
      isFalse,
    );
  });

  test('JSON: выключенные позиции сохраняются и читаются', () {
    final source = PriceList.defaults()
        .withItem(PriceItemKeys.labor, enabled: false)
        .withItem(PriceItemKeys.edge100, enabled: false);
    expect(source.disabledItems,
        {PriceItemKeys.labor, PriceItemKeys.edge100});
    expect(source.toJson()['disabledItems'], isA<List<dynamic>>());

    final restored = PriceList.fromJson(source.toJson());
    expect(restored.disabledItems,
        {PriceItemKeys.labor, PriceItemKeys.edge100});
    expect(restored.toJson(), equals(source.toJson()));
    expect(restored.isEnabled(PriceItemKeys.labor), isFalse);
    expect(restored.isEnabled(PriceItemKeys.filmClear), isTrue);

    // Повторное включение чистит набор.
    final again = restored.withItem(PriceItemKeys.labor, enabled: true);
    expect(again.disabledItems, {PriceItemKeys.edge100});
  });

  test('старый прайс без поля — всё включено, мусор игнорируется', () {
    final json = PriceList.defaults().toJson();
    // Пустой набор не пишется: формат старого прайса не меняется.
    expect(json.containsKey('disabledItems'), isFalse);

    final restored = PriceList.fromJson(json);
    expect(restored.disabledItems, isEmpty);
    for (final key in PriceItemKeys.all) {
      expect(restored.isEnabled(key), isTrue, reason: key);
    }

    // Из чужого JSON берём только известные строковые ключи.
    final junk = PriceList.fromJson({
      'disabledItems': [PriceItemKeys.labor, 42, 'unknownKey', null],
    });
    expect(junk.disabledItems, {PriceItemKeys.labor});
    // Не-список в поле — тоже «всё включено».
    expect(PriceList.fromJson({'disabledItems': 'labor'}).disabledItems,
        isEmpty);
  });

  test('ключи позиций: у каждой строки прайса свой ключ', () {
    // Ключи плёнки и окантовки совпадают с именами полей панели цен —
    // по ним лист «Смета» помечает выключенные позиции.
    for (final field in PriceField.values) {
      expect(PriceItemKeys.all, contains(field.itemKey));
    }
    // Ключи уникальны (набор) и покрывают работы и фурнитуру шага 1.
    expect(
      PriceItemKeys.all,
      containsAll(<String>[
        PriceItemKeys.eyeletRound,
        PriceItemKeys.eyeletOval,
        PriceItemKeys.eyeletInstall,
        PriceItemKeys.labor,
        PriceItemKeys.cutting,
        PriceItemKeys.screenHem,
        PriceItemKeys.zipper,
        PriceItemKeys.weld,
        PriceItemKeys.pocket,
        PriceItemKeys.strap,
        PriceItemKeys.drain,
        PriceItemKeys.cutout,
      ]),
    );
  });

  testWidgets('панель прайса: тумблер меняет модель и смету, строки не тесно', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PriceHostState>();
    await tester.pumpWidget(_PriceHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Панель раскрыта.
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pumpAndSettle();

    // У каждой позиции есть компактный тумблер.
    for (final key in <String>[
      PriceItemKeys.filmClear,
      PriceItemKeys.edge100,
      PriceItemKeys.eyeletRound,
      PriceItemKeys.zipper,
      PriceItemKeys.labor,
      PriceItemKeys.cutting,
      PriceItemKeys.screenHem,
    ]) {
      expect(
        find.byKey(ValueKey('price-toggle-$key')),
        findsOneWidget,
        reason: 'тумблер позиции $key',
      );
    }
    // У процентов расчёта тумблера нет — это условия, а не позиции.
    expect(find.byKey(const ValueKey('price-toggle-vatPercent')), findsNothing);

    // По умолчанию всё включено и смета полная.
    final before =
        Estimate.ofWindow(_window, hostKey.currentState!.prices);
    expect(
      before.lines.any((line) => line.itemKey == PriceItemKeys.labor),
      isTrue,
    );

    // Тумблер выключает позицию в модели…
    final toggle = find.byKey(const ValueKey('price-toggle-labor'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prices = hostKey.currentState!.prices;
    expect(prices.isEnabled(PriceItemKeys.labor), isFalse);
    expect(prices.disabledItems, contains(PriceItemKeys.labor));

    // …и она уходит из сметы.
    final after = Estimate.ofWindow(_window, prices);
    expect(
      after.lines.any((line) => line.itemKey == PriceItemKeys.labor),
      isFalse,
    );

    // Повторный тап возвращает позицию.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.prices.isEnabled(PriceItemKeys.labor), isTrue);
    final back = Estimate.ofWindow(_window, hostKey.currentState!.prices);
    expect(
      back.lines.any((line) => line.itemKey == PriceItemKeys.labor),
      isTrue,
    );
    // Панель 420 px: переполнений за все тапы не было.
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
