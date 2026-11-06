import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late WarehouseRepository warehouse;
  late OrderRepository orders;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase.instance;
    database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
    await database.open();
    warehouse = WarehouseRepository(database: database);
    orders = OrderRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<WarehouseProduct> product({
    String id = 'p1',
    String name = 'Плёнка ПВХ 500 мкм',
    StockUnit unit = StockUnit.roll,
    double width = 2000,
    double length = 50000,
    double purchase = 500,
    double sale = 900,
    double min = 1,
  }) async {
    final value = WarehouseProduct(
      id: id,
      name: name,
      category: 'Полотно',
      material: 'ПВХ',
      unit: unit,
      widthMm: width,
      lengthMm: length,
      purchasePrice: purchase,
      salePrice: sale,
      minQuantity: min,
      supplier: 'Поставщик',
      location: 'Склад А',
    );
    final result = await warehouse.saveProduct(value);
    expect(result.ok, isTrue, reason: result.message);
    return value;
  }

  test('приход создаёт партию, остаток считается по журналу', () async {
    final p = await product();
    final result = await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 3,
        unitCost: 500,
        note: 'первый приход',
      ),
    );
    expect(result.ok, isTrue, reason: result.message);

    final stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 3);
    expect(stock.available, 3);
    expect(stock.averageCost, 500);
    expect(stock.batches, hasLength(1));
    expect(stock.batches.first.remaining, 3);
  });

  test('FIFO: продажа списывает самую старую партию, средняя цена верна', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.purchase,
        productId: p.id,
        quantity: 3,
        unitPrice: 500,
      ),
    );
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.purchase,
        productId: p.id,
        quantity: 2,
        unitPrice: 600,
      ),
    );

    var stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 5);
    expect(stock.averageCost, 540);

    final sale = await warehouse.perform(
      StockOperation(
        type: StockMoveType.sale,
        productId: p.id,
        quantity: 1,
        unitPrice: 900,
      ),
    );
    expect(sale.ok, isTrue, reason: sale.message);

    stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 4);
    // Первая партия 3 шт по 500: одна ушла, осталось 2 по 500 и 2 по 600.
    final first = stock.batches.first;
    expect(first.unitCost, 500);
    expect(first.remaining, 2);
    final moves = await warehouse.moves(productId: p.id);
    final saleMove = moves.firstWhere((m) => m.type == StockMoveType.sale);
    expect(saleMove.unitCost, 500);
    expect(saleMove.unitPrice, 900);
  });

  test('нельзя продать больше свободного остатка — склад не уходит в минус', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 2,
        unitCost: 500,
      ),
    );
    final result = await warehouse.perform(
      StockOperation(
        type: StockMoveType.sale,
        productId: p.id,
        quantity: 5,
        unitPrice: 900,
      ),
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('Недостаточно'));
    final stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 2);
  });

  test('резерв → списание в заказ → возврат', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 5,
        unitCost: 500,
      ),
    );
    final order = await orders.create(title: 'Тестовый заказ');
    final need = OrderMaterialNeed(
      productId: p.id,
      name: p.name,
      unit: p.unit,
      quantity: 3,
      available: 5,
      reserved: 0,
      source: 'Полотно',
    );
    final reserved = await warehouse.reserveOrder(order.id, [need]);
    expect(reserved.ok, isTrue, reason: reserved.message);

    var stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 5);
    expect(stock.reserved, 3);
    expect(stock.available, 2);

    final tooMuch = await warehouse.perform(
      StockOperation(
        type: StockMoveType.sale,
        productId: p.id,
        quantity: 3,
        unitPrice: 900,
      ),
    );
    expect(tooMuch.ok, isFalse, reason: 'резерв нельзя продать');

    final issued = await warehouse.issueOrder(order.id);
    expect(issued.ok, isTrue, reason: issued.message);
    stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 2);
    expect(stock.reserved, 0);
    final links = await warehouse.orderMaterials(order.id);
    expect(links.single.issuedQty, 3);
    expect(links.single.state, OrderMaterialState.issued);

    final returned = await warehouse.returnOrder(order.id);
    expect(returned.ok, isTrue, reason: returned.message);
    stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 5);
  });

  test('резерв не создаётся, если материалов не хватает', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 1,
        unitCost: 500,
      ),
    );
    final order = await orders.create(title: 'Дефицит');
    final result = await warehouse.reserveOrder(order.id, [
      OrderMaterialNeed(
        productId: p.id,
        name: p.name,
        unit: p.unit,
        quantity: 2,
        available: 1,
        reserved: 0,
      ),
    ]);
    expect(result.ok, isFalse);
    expect(result.shortages.single, contains('доступно'));
    final stock = await warehouse.stockFor(p.id);
    expect(stock!.reserved, 0);
  });

  test('перемещение не меняет общий остаток, инвентаризация корректирует', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 4,
        unitCost: 500,
      ),
    );
    final moved = await warehouse.perform(
      StockOperation(
        type: StockMoveType.transferOut,
        productId: p.id,
        quantity: 2,
        locationFrom: 'Склад А',
        locationTo: 'Склад Б',
      ),
    );
    expect(moved.ok, isTrue, reason: moved.message);
    var stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 4);
    final moves = await warehouse.moves(productId: p.id);
    expect(
      moves.where((m) => m.type.isTransfer).length,
      2,
    );

    final inventory = await warehouse.perform(
      StockOperation(
        type: StockMoveType.inventory,
        productId: p.id,
        quantity: 3,
        unitCost: 500,
      ),
    );
    expect(inventory.ok, isTrue, reason: inventory.message);
    stock = await warehouse.stockFor(p.id);
    expect(stock!.balance, 3);
  });

  test('отчёты склада считают остатки, продажи и прибыль', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.purchase,
        productId: p.id,
        quantity: 3,
        unitPrice: 500,
      ),
    );
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.sale,
        productId: p.id,
        quantity: 1,
        unitPrice: 900,
      ),
    );
    final stock = await warehouse.report(WarehouseReportKind.stock);
    expect(stock.rows, hasLength(1));
    expect(stock.totals['Стоимость'], contains('₽'));

    final sales = await warehouse.report(WarehouseReportKind.sales);
    expect(sales.totals['Выручка'], contains('900'));
    expect(sales.totals['Прибыль'], contains('400'));

    final profit = await warehouse.report(WarehouseReportKind.profit);
    expect(profit.rows.single[4], contains('400'));
  });

  test('архив скрывает товар из рабочего списка, история остаётся', () async {
    final p = await product();
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: p.id,
        quantity: 1,
        unitCost: 500,
      ),
    );
    await warehouse.archiveProduct(p.id, true);
    expect(await warehouse.products(), isEmpty);
    expect(await warehouse.products(includeArchived: true), hasLength(1));
    expect(await warehouse.moves(productId: p.id), hasLength(1));
  });
}
