import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/catalog/grouped_catalog_picker.dart';

WarehouseProduct _product({
  required String id,
  required String name,
  required String category,
  required String color,
  double width = 0,
  String priceKey = '',
  double price = 100,
}) => WarehouseProduct(
  id: id,
  name: name,
  category: category,
  color: color,
  widthMm: width,
  priceKey: priceKey,
  unit: width > 0 ? StockUnit.meter : StockUnit.piece,
  purchasePrice: price,
  salePrice: price,
);

List<CatalogItem> _items() => CatalogItem.fromProducts([
  _product(
    id: 'edge100-grey',
    name: 'Окантовка тент 100 мм — Серый',
    category: 'Окантовка',
    color: 'Серый',
    width: 100,
    priceKey: 'edge100:grey',
    price: 140,
  ),
  _product(
    id: 'edge100-white',
    name: 'Окантовка тент 100 мм — Белый',
    category: 'Окантовка',
    color: 'Белый',
    width: 100,
    priceKey: 'edge100:white',
    price: 140,
  ),
  _product(
    id: 'edge120-black',
    name: 'Окантовка тент 120 мм — Чёрный',
    category: 'Окантовка',
    color: 'Чёрный',
    width: 120,
    priceKey: 'edge120:black',
    price: 165,
  ),
  _product(
    id: 'eyelet-grey',
    name: 'Люверс круглый Ø10 — Серый',
    category: 'Люверсы',
    color: 'Серый',
    priceKey: 'eyeletRound:grey',
    price: 90,
  ),
]);

void main() {
  testWidgets('дерево: категория → тип → ширина → цвет, выбор работает', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CatalogItem? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedCatalogPicker(
            items: _items(),
            pickerKey: 'picker',
            initialCategory: 'Окантовка',
            onSelected: (item) => selected = item,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Первая категория раскрыта, тип виден, ширина — ещё нет.
    expect(find.byKey(const Key('picker-category-Окантовка')), findsOneWidget);
    expect(find.byKey(const Key('picker-type-Окантовка/Тент')), findsOneWidget);
    expect(
      find.byKey(const Key('picker-width-Окантовка/Тент/100 мм')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('picker-type-Окантовка/Тент')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('picker-width-Окантовка/Тент/100 мм')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('picker-width-Окантовка/Тент/120 мм')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('picker-width-Окантовка/Тент/100 мм')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picker-item-edge100-grey')), findsOneWidget);
    expect(find.text('Серый'), findsOneWidget);
    expect(find.text('Белый'), findsOneWidget);

    await tester.tap(find.byKey(const Key('picker-item-edge100-grey')));
    await tester.pumpAndSettle();
    expect(selected?.id, 'edge100-grey');
  });

  testWidgets('поиск по цвету показывает плоский список', (tester) async {
    tester.view.physicalSize = const Size(600, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedCatalogPicker(
            items: _items(),
            pickerKey: 'picker',
            showProductName: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'серый');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('picker-item-edge100-grey')), findsOneWidget);
    expect(find.byKey(const Key('picker-item-eyelet-grey')), findsOneWidget);
    expect(find.byKey(const Key('picker-item-edge100-white')), findsNothing);
    expect(find.byKey(const Key('picker-type-Окантовка/Тент')), findsNothing);
  });

  testWidgets('дубли по одному ключу не показываются дважды', (tester) async {
    final items = CatalogItem.fromProducts([
      _product(
        id: 'dup-1',
        name: 'Окантовка тент 100 мм — Серый',
        category: 'Окантовка',
        color: 'Серый',
        width: 100,
        priceKey: 'edge100:grey',
      ),
      _product(
        id: 'dup-2',
        name: 'Окантовка тент 100 мм — Серый (копия)',
        category: 'Окантовка',
        color: 'Серый',
        width: 100,
        priceKey: 'edge100:grey',
      ),
    ]);
    expect(items, hasLength(1));
    expect(items.single.id, 'dup-1');
  });

  test('цветной кружок совпадает с палитрой канта', () {
    expect(catalogSwatchColor('Серый'), Color(EdgeColor.grey.value));
    expect(catalogSwatchColor('Чёрный'), Color(EdgeColor.black.value));
  });
}
