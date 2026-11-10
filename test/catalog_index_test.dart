import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/services/catalog_index.dart';

WarehouseProduct _product({
  String id = 'p',
  String name = 'Окантовка тент 100 мм — Серый',
  String category = 'Окантовка',
  String material = 'Тент',
  String color = 'Серый',
  double width = 100,
  String priceKey = 'edge100:grey',
}) => WarehouseProduct(
  id: id,
  name: name,
  category: category,
  material: material,
  color: color,
  widthMm: width,
  priceKey: priceKey,
  unit: StockUnit.meter,
  purchasePrice: 0,
  salePrice: 140,
);

void main() {
  test('базовый ключ отбрасывает цветовой суффикс', () {
    expect(catalogBasePriceKey('edge100:brown'), 'edge100');
    expect(catalogBasePriceKey('eyeletRound:grey'), 'eyeletRound');
    expect(catalogBasePriceKey('custom:доставка'), 'custom');
    expect(catalogBasePriceKey('filmClear'), 'filmClear');
  });

  test('тип убирает цвет и ширину из названия', () {
    expect(catalogTypeOf(_product()), 'Тент');
    expect(
      catalogTypeOf(
        _product(
          name: 'Люверс круглый Ø10 — Серый',
          category: 'Люверсы',
          material: 'Металл',
          width: 0,
          priceKey: 'eyeletRound:grey',
        ),
      ),
      'Люверс круглый Ø10',
    );
    expect(
      catalogTypeOf(
        _product(
          name: 'Скоба поворотная — Чёрный',
          category: 'Фурнитура',
          material: 'Металл',
          color: 'Чёрный',
          width: 0,
          priceKey: 'turnBuckle:black',
        ),
      ),
      'Скоба поворотная',
    );
  });

  test('ширина и цвет', () {
    final product = _product();
    expect(catalogWidthLabelOf(product), '100 мм');
    expect(catalogColorOf(product), 'Серый');
    expect(catalogColorOf(_product(color: '')), 'Без цвета');
  });

  test('цвет сравнивается без регистра и разницы «ё/е»', () {
    expect(normalizeCatalogColor('Чёрный'), normalizeCatalogColor('черный'));
    expect(normalizeCatalogColor(' Серый '), 'серый');
  });

  test('ключ дедупликации уникален для цвета', () {
    expect(catalogDedupeKey(_product()), 'edge100:grey');
    expect(
      catalogDedupeKey(_product(color: 'Белый', priceKey: 'edge100:white')),
      'edge100:white',
    );
    final withoutKey = _product(
      color: 'Белый',
      priceKey: '',
      name: 'Без ключа',
    );
    expect(catalogDedupeKey(withoutKey), catalogDedupeKey(withoutKey));
    expect(catalogDedupeKey(withoutKey), contains('без ключа'));
  });

  test('поиск видит название, цвет и ширину', () {
    final text = catalogSearchTextOf(_product()).toLowerCase();
    expect(text, contains('серый'));
    expect(text, contains('100 мм'));
    expect(text, contains('окантовка'));
  });
}
