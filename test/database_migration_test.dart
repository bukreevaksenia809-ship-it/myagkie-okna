import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/services/legacy_data_migrator.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late WarehouseRepository warehouse;

  setUp(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.instance;
    database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
    await database.open();
    warehouse = WarehouseRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('схема создаёт все таблицы склада и заказов', () async {
    final db = await database.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final names = rows.map((row) => '${row['name']}').toSet();
    expect(
      names,
      containsAll([
        'warehouse_products',
        'stock_moves',
        'stock_batches',
        'stock_move_allocations',
        'price_history',
        'orders',
        'order_events',
        'order_comments',
        'order_checklist',
        'order_attachments',
        'order_materials',
        'app_meta',
      ]),
    );
    expect(await db.getVersion(), AppDatabase.schemaVersion);
  });

  test('старый склад из shared_preferences переносится один раз', () async {
    final legacy = jsonEncode({
      'products': [
        {
          'id': 'legacy-1',
          'name': 'Плёнка ПВХ',
          'unit': 'roll',
          'purchasePrice': 500,
          'salePrice': 900,
          'material': 'ПВХ',
          'widthMm': 2000,
          'lengthMm': 50000,
          'minQuantity': 1,
          'supplier': 'Старый поставщик',
          'location': 'Склад А',
          'note': '',
        },
      ],
      'moves': [
        {
          'id': 'm1',
          'productId': 'legacy-1',
          'type': 'receipt',
          'quantity': 3,
          'price': 500,
          'at': '2026-01-10T10:00:00.000',
          'orderId': '',
          'note': 'старый приход',
        },
        {
          'id': 'm2',
          'productId': 'legacy-1',
          'type': 'issue',
          'quantity': 1,
          'price': 500,
          'at': '2026-01-11T10:00:00.000',
          'orderId': 'МО-01',
          'note': 'старое списание',
        },
      ],
    });
    SharedPreferences.setMockInitialValues({'warehouse_v2': legacy});

    await LegacyDataMigrator(database: database).run(orders: false);

    final products = await warehouse.products(includeArchived: true);
    expect(products, hasLength(1));
    expect(products.single.name, 'Плёнка ПВХ');
    final stock = await warehouse.stockFor('legacy-1');
    expect(stock!.balance, 2);
    expect(stock.batches.single.remaining, 2);
    expect(stock.averageCost, 500);
    final moves = await warehouse.moves(productId: 'legacy-1');
    expect(moves, hasLength(2));

    // Повторный запуск не должен удвоить товары и движения.
    await LegacyDataMigrator(database: database).run(orders: false);
    expect(await warehouse.products(includeArchived: true), hasLength(1));
    expect(await warehouse.moves(productId: 'legacy-1'), hasLength(2));
  });

  test('резервная копия содержит склад, движения и заказы', () async {
    await warehouse.saveProduct(
      const WarehouseProduct(
        id: 'p1',
        name: 'Окантовка',
        unit: StockUnit.meter,
        purchasePrice: 80,
        salePrice: 160,
      ),
    );
    await warehouse.perform(
      const StockOperation(
        type: StockMoveType.receipt,
        productId: 'p1',
        quantity: 100,
        unitCost: 80,
      ),
    );
    await OrderRepository(database: database).create(title: 'Заказ для копии');
    final raw = await exportDatabaseBackup();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['format'], 'soft_window_drawer_backup');
    expect(decoded['warehouse_products'], hasLength(1));
    expect(decoded['stock_moves'], hasLength(1));
    expect(decoded['orders'], hasLength(1));
    expect(decoded['order_events'], isNotEmpty);
  });

  test('база переживает закрытие и повторное открытие', () async {
    final directory = await Directory.systemTemp.createTemp('swd_db_test_');
    final path = '${directory.path}/test.sqlite';
    try {
      database.configureForTesting(databaseFactoryFfi, path);
      await database.open();
      final repo = WarehouseRepository(database: database);
      final result = await repo.saveProduct(
        const WarehouseProduct(
          id: 'p1',
          name: 'Люверс',
          unit: StockUnit.piece,
          purchasePrice: 5,
          salePrice: 15,
        ),
      );
      expect(result.ok, isTrue);
      await database.close();

      database.configureForTesting(databaseFactoryFfi, path);
      await database.open();
      final reopened = WarehouseRepository(database: database);
      expect(await reopened.products(), hasLength(1));
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
