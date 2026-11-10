import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

const _fixed = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
  noEyeletsAll: true,
  screwType: ScrewType.roofing,
  edgeColor: EdgeColor.brown,
);

void main() {
  test('саморезы появляются только у глухого окна без люверсов', () {
    final spec = WindowSpec.of(_fixed);
    expect(spec.screwPointCount, greaterThan(0));
    expect(spec.screwPoints, isNotEmpty);
    // Без «Убрать все люверсы» саморезов по периметру нет.
    final withEyelets = WindowSpec.of(
      _fixed.copyWith(noEyeletsAll: false),
    );
    expect(withEyelets.screwPointCount, 0);
    expect(withEyelets.screwPoints, isEmpty);
  });

  test('кровельный саморез берёт цвет канта', () {
    expect(_fixed.screwColorLabel, 'Коричневый');
    expect(
      _fixed.copyWith(edgeColor: EdgeColor.graphite).screwColorLabel,
      'Графит',
    );
  });

  test('саморез по дереву — золотой или чёрный', () {
    final gold = _fixed.copyWith(
      screwType: ScrewType.wood,
      screwWoodGold: true,
    );
    final black = _fixed.copyWith(
      screwType: ScrewType.wood,
      screwWoodGold: false,
    );
    expect(gold.screwColorLabel, 'Золотой');
    expect(black.screwColorLabel, 'Чёрный');
  });

  test('саморез по металлу — серебристый', () {
    expect(
      _fixed.copyWith(screwType: ScrewType.metal).screwColorLabel,
      'Серебристый',
    );
  });

  test('смета: строка саморезов по типу и цена из прайса', () {
    final prices = const PriceList.defaults().copyWith(
      screwRoofingPrice: 33,
    );
    final estimate = Estimate.of(OrderProject(windows: [_fixed]), prices);
    final spec = WindowSpec.of(_fixed);
    final line = estimate.lines.firstWhere(
      (item) => item.title == 'Саморез кровельный',
    );
    expect(line.quantity, closeTo(spec.screwPointCount, 1e-9));
    expect(line.unitPrice, 33);
    expect(line.unit, 'шт');
    expect(line.itemKey, PriceItemKeys.screwRoofing);
  });

  test('выключенная позиция убирает строку саморезов', () {
    final prices = const PriceList.defaults().withItem(
      PriceItemKeys.screwRoofing,
      enabled: false,
    );
    final estimate = Estimate.of(OrderProject(windows: [_fixed]), prices);
    expect(
      estimate.lines.where((line) => line.title == 'Саморез кровельный'),
      isEmpty,
    );
  });

  test('цены саморезов сохраняются в JSON прайса', () {
    final prices = const PriceList.defaults().copyWith(
      screwRoofingPrice: 31,
      screwWoodPrice: 17,
      screwMetalPrice: 23,
    );
    final restored = PriceList.fromJson(prices.toJson());
    expect(restored.screwRoofingPrice, 31);
    expect(restored.screwWoodPrice, 17);
    expect(restored.screwMetalPrice, 23);
  });

  test('тип и цвет самореза переживают JSON заказа', () {
    final params = _fixed.copyWith(
      screwType: ScrewType.wood,
      screwWoodGold: false,
    );
    final json = orderToJson(OrderProject(windows: [params]));
    final windows = json['windows'] as List;
    final first = windows.first as Map;
    expect(first['screwType'], 'wood');
    expect(first['screwWoodGold'], false);

    final restored = orderFromJson(json).selected;
    expect(restored.screwType, ScrewType.wood);
    expect(restored.screwWoodGold, false);
    expect(restored.screwColorLabel, 'Чёрный');
  });
}
