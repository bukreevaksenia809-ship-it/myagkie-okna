import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/services/order_materials.dart';
import 'package:soft_window_drawer/services/price_warehouse_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('позиции прайса заводятся в склад без дублей', () async {
    final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
    final created = await sync.sync(const PriceList.defaults());
    expect(created, greaterThan(15));
    final products = await warehouse.products();
    expect(products, hasLength(created));
    expect(products.any((p) => p.priceKey == PriceItemKeys.filmClear), isTrue);
    expect(products.any((p) => p.priceKey == PriceItemKeys.filmScreen), isTrue);
    expect(products.any((p) => p.priceKey == PriceItemKeys.edge100), isTrue);
    expect(
      products.any((p) => p.priceKey == PriceItemKeys.eyeletRound),
      isTrue,
    );
    expect(products.any((p) => p.priceKey == 'crossbar'), isTrue);

    final again = await sync.sync(const PriceList.defaults());
    expect(again, 0);
    expect(await warehouse.products(), hasLength(created));
  });

  test('синхронизация обновляет цену продажи, но не закупку', () async {
    final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
    await sync.sync(const PriceList.defaults());
    final before = (await warehouse.products()).firstWhere(
      (p) => p.priceKey == PriceItemKeys.filmClear,
    );
    await warehouse.saveProduct(before.copyWith(purchasePrice: 300));
    final changed = const PriceList.defaults().copyWith(filmClearPerM2: 1200);
    await sync.sync(changed, updatePrices: true);
    final after = (await warehouse.products()).firstWhere(
      (p) => p.priceKey == PriceItemKeys.filmClear,
    );
    expect(after.salePrice, 1200);
    expect(after.purchasePrice, 300);
  });

  test(
    'старый товар с тем же названием привязывается, а не дублируется',
    () async {
      await warehouse.saveProduct(
        const WarehouseProduct(
          id: 'manual-film',
          name: 'Плёнка ПВХ прозрачная',
          unit: StockUnit.squareMeter,
          purchasePrice: 400,
          salePrice: 900,
        ),
      );
      final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
      await sync.sync(const PriceList.defaults());
      final products = await warehouse.products();
      final films = products
          .where((p) => p.name == 'Плёнка ПВХ прозрачная')
          .toList();
      expect(films, hasLength(1));
      expect(films.single.id, 'manual-film');
      expect(films.single.priceKey, PriceItemKeys.filmClear);
      expect(films.single.purchasePrice, 400);
    },
  );

  test('seedOnce выполняется один раз', () async {
    final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
    expect(await sync.seedOnce(), greaterThan(0));
    final count = (await warehouse.products()).length;
    expect(await sync.seedOnce(), 0);
    expect(await warehouse.products(), hasLength(count));
  });

  test('заказ находит материалы из прайса и считает потребность', () async {
    final sync = PriceWarehouseSync(database: database, warehouse: warehouse);
    await sync.sync(const PriceList.defaults());
    final plan = await OrderMaterialsService(
      warehouse: warehouse,
    ).plan(const OrderProject());
    expect(plan.needs, isNotEmpty);
    expect(plan.unmatched, isEmpty);
    final keys = {
      for (final stock in await warehouse.products()) stock.id: stock.priceKey,
    };
    expect(
      plan.needs.any((need) => keys[need.productId] == PriceItemKeys.filmClear),
      isTrue,
    );
    expect(
      plan.needs.any(
        (need) => keys[need.productId] == PriceItemKeys.eyeletRound,
      ),
      isTrue,
    );
  });

  test('миграция базы 1 → 2 добавляет price_key и сохраняет товар', () async {
    final dir = await Directory.systemTemp.createTemp('swd_v1_');
    final path = '${dir.path}/v1.sqlite';
    final factory = databaseFactoryFfi;
    try {
      final old = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE warehouse_products (
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                category TEXT NOT NULL DEFAULT '', material TEXT NOT NULL DEFAULT '',
                color TEXT NOT NULL DEFAULT '', thickness_mm REAL NOT NULL DEFAULT 0,
                unit TEXT NOT NULL DEFAULT 'piece', width_mm REAL NOT NULL DEFAULT 0,
                length_mm REAL NOT NULL DEFAULT 0, weight_kg REAL NOT NULL DEFAULT 0,
                min_quantity REAL NOT NULL DEFAULT 0,
                purchase_price REAL NOT NULL DEFAULT 0,
                sale_price REAL NOT NULL DEFAULT 0, supplier TEXT NOT NULL DEFAULT '',
                location TEXT NOT NULL DEFAULT '', barcode TEXT NOT NULL DEFAULT '',
                archived INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL
              )
            ''');
            await db.insert('warehouse_products', {
              'id': 'old',
              'name': 'Старый товар',
              'unit': 'piece',
              'purchase_price': 10,
              'sale_price': 20,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
          },
        ),
      );
      await old.close();
      database.configureForTesting(factory, path);
      await database.open();
      final rows = await (await database.database).rawQuery(
        'PRAGMA table_info(warehouse_products)',
      );
      expect(rows.any((row) => row['name'] == 'price_key'), isTrue);
      final product = await warehouse.product('old');
      expect(product, isNotNull);
      expect(product!.priceKey, '');
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
