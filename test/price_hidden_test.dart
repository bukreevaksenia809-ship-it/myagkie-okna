// Удаление позиций прайса и склада: скрытие, восстановление и синхронизация.
//
// Проверяем:
//   • скрытая позиция не попадает в смету и не восстанавливается синком;
//   • своё название видно в смете;
//   • удалённый товар склада запоминается и не возвращается синком;
//   • «Восстановить» возвращает позицию.
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/catalog_index.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/price_warehouse_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _window = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('модель прайса', () {
    test('скрытая позиция выключена, JSON её сохраняет', () {
      final hidden = const PriceList.defaults().withHidden(
        PriceItemKeys.labor,
        hidden: true,
      );
      expect(hidden.isHidden(PriceItemKeys.labor), isTrue);
      expect(hidden.isEnabled(PriceItemKeys.labor), isFalse);

      final restored = PriceList.fromJson(hidden.toJson());
      expect(restored.isHidden(PriceItemKeys.labor), isTrue);
      expect(
        restored.withHidden(PriceItemKeys.labor, hidden: false).isEnabled(
          PriceItemKeys.labor,
        ),
        isTrue,
      );
    });

    test('своё название переживает JSON и подставляется с fallback', () {
      final renamed = const PriceList.defaults()
          .withTitle(PriceItemKeys.filmClear, '  Мой ПВХ  ')
          .withTitle(PriceItemKeys.filmTinted, '   ');
      expect(
        renamed.titleFor(PriceItemKeys.filmClear, 'Обычный ПВХ'),
        'Мой ПВХ',
      );
      expect(
        renamed.titleFor(PriceItemKeys.filmTinted, 'Тонированный'),
        'Тонированный',
        reason: 'пустое название возвращает стандартную подпись',
      );

      final restored = PriceList.fromJson(renamed.toJson());
      expect(restored.customTitles[PriceItemKeys.filmClear], 'Мой ПВХ');
      expect(restored.customTitles.containsKey(PriceItemKeys.filmTinted), isFalse);
    });

    test('скрытая позиция исчезает из сметы, восстановление возвращает', () {
      final prices = PriceList.defaults();
      final full = Estimate.ofWindow(_window, prices);
      final labor = full.lines.firstWhere(
        (line) => line.itemKey == PriceItemKeys.labor,
      );
      expect(labor.amount, greaterThan(0));

      final without = Estimate.ofWindow(
        _window,
        prices.withHidden(PriceItemKeys.labor, hidden: true),
      );
      expect(
        without.lines.any((line) => line.itemKey == PriceItemKeys.labor),
        isFalse,
      );
      expect(without.subtotal, closeTo(full.subtotal - labor.amount, 0.011));

      final back = Estimate.ofWindow(
        _window,
        prices.withHidden(PriceItemKeys.labor, hidden: false),
      );
      expect(back.subtotal, closeTo(full.subtotal, 1e-9));
    });

    test('переименование видно в смете', () {
      final renamed = const PriceList.defaults().withTitle(
        PriceItemKeys.filmClear,
        'Плёнка «Премиум»',
      );
      final estimate = Estimate.ofWindow(_window, renamed);
      final line = estimate.lines.firstWhere(
        (line) => line.itemKey == PriceItemKeys.filmClear,
      );
      expect(line.title, 'Плёнка «Премиум»');
    });
  });

  group('склад и синхронизация', () {
    late AppDatabase database;
    late WarehouseRepository warehouse;

    setUp(() async {
      sqfliteFfiInit();
      database = AppDatabase.instance;
      database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
      await database.open();
      warehouse = WarehouseRepository(database: database);
    });

    tearDown(() async {
      await database.close();
    });

    test('скрытая в прайсе позиция не заводится, восстановление создаёт', () async {
      final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
      final hidden = const PriceList.defaults().withHidden(
        PriceItemKeys.filmClear,
        hidden: true,
      );
      await sync.sync(hidden);
      var products = await warehouse.products(includeArchived: true);
      expect(
        products.any(
          (product) => product.priceKey == PriceItemKeys.filmClear,
        ),
        isFalse,
      );

      final restored = hidden.withHidden(
        PriceItemKeys.filmClear,
        hidden: false,
      );
      final created = await sync.sync(restored);
      expect(created, greaterThanOrEqualTo(1));
      products = await warehouse.products(includeArchived: true);
      expect(
        products.any(
          (product) => product.priceKey == PriceItemKeys.filmClear,
        ),
        isTrue,
      );
    });

    test('удалённый товар склада не возвращается синком, восстановление — да',
        () async {
      final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
      await sync.sync(const PriceList.defaults());
      final product = (await warehouse.products()).firstWhere(
        (product) => product.priceKey == PriceItemKeys.filmClear,
      );

      final deleted = await warehouse.deleteProduct(product.id);
      expect(deleted.ok, isTrue);
      expect(
        await warehouse.hiddenPriceKeys(),
        contains(PriceItemKeys.filmClear),
      );

      final created = await sync.sync(const PriceList.defaults());
      expect(created, 0);
      expect(
        (await warehouse.products(includeArchived: true)).any(
          (product) => product.priceKey == PriceItemKeys.filmClear,
        ),
        isFalse,
        reason: 'синхронизация не должна возвращать удалённый товар',
      );

      await warehouse.restorePriceKey(PriceItemKeys.filmClear);
      final restored = await sync.sync(const PriceList.defaults());
      expect(restored, 1);
      expect(
        (await warehouse.products()).any(
          (product) => product.priceKey == PriceItemKeys.filmClear,
        ),
        isTrue,
      );
    });

    test('удаление скрывает все цвета одной позиции', () async {
      final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
      await sync.sync(const PriceList.defaults());
      final colored = (await warehouse.products()).firstWhere(
        (product) =>
            catalogBasePriceKey(product.priceKey) == PriceItemKeys.edge100,
      );
      final before = await warehouse.products(includeArchived: true);
      await warehouse.deleteProduct(colored.id);
      // Скрывается базовый ключ: синхронизация не должна вернуть ни один
      // цвет этой позиции, включая удалённый.
      expect(
        await warehouse.hiddenPriceKeys(),
        contains(PriceItemKeys.edge100),
      );
      final created = await sync.sync(const PriceList.defaults());
      expect(created, 0);
      final after = await warehouse.products(includeArchived: true);
      expect(after, hasLength(before.length - 1));
      expect(after.any((product) => product.id == colored.id), isFalse);
    });

    test('restoreAllPriceKeys возвращает все скрытые ключи', () async {
      await warehouse.hidePriceKey(PriceItemKeys.filmClear);
      await warehouse.hidePriceKey(PriceItemKeys.labor);
      expect(await warehouse.hiddenPriceKeys(), hasLength(2));
      await warehouse.restoreAllPriceKeys();
      expect(await warehouse.hiddenPriceKeys(), isEmpty);
    });
  });
}
