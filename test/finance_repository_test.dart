import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/finance_repository.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/finance.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late OrderRepository orders;
  late WarehouseRepository warehouse;
  late FinanceRepository finance;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase.instance;
    database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
    await database.open();
    orders = OrderRepository(database: database);
    warehouse = WarehouseRepository(database: database);
    finance = FinanceRepository(database: database, orders: orders);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> stockAndIssue(String orderId) async {
    await warehouse.saveProduct(
      const WarehouseProduct(
        id: 'film',
        name: 'Плёнка',
        category: 'Полотно',
        material: 'ПВХ',
        unit: StockUnit.squareMeter,
        purchasePrice: 500,
        salePrice: 900,
      ),
    );
    await warehouse.perform(
      const StockOperation(
        type: StockMoveType.receipt,
        productId: 'film',
        quantity: 10,
        unitCost: 500,
      ),
    );
    final result = await warehouse.perform(
      StockOperation(
        type: StockMoveType.issue,
        productId: 'film',
        quantity: 2,
        orderId: orderId,
      ),
    );
    expect(result.ok, isTrue, reason: result.message);
  }

  test('оплаты, расходы, долг и маржа заказа', () async {
    final order = await orders.create(
      title: 'Беседка',
      customer: 'Иванов',
      amount: 5000,
    );
    await stockAndIssue(order.id);

    expect(
      await finance.addPayment(
        order: order,
        amount: 2000,
        kind: PaymentKind.advance,
        method: PaymentMethod.cash,
        at: DateTime(2026, 11, 1),
      ),
      isNull,
    );
    expect(
      await finance.addExpense(
        order: order,
        category: ExpenseCategory.labor,
        amount: 500,
        at: DateTime(2026, 11, 1),
      ),
      isNull,
    );
    expect(
      await finance.addExpense(
        order: order,
        category: ExpenseCategory.delivery,
        amount: 300,
        at: DateTime(2026, 11, 2),
      ),
      isNull,
    );

    var result = await finance.orderFinance(order);
    expect(result.amount, 5000);
    expect(result.materialCost, 1000);
    expect(result.paid, 2000);
    expect(result.due, 3000);
    expect(result.manualCost, 800);
    expect(result.totalCost, 1800);
    expect(result.margin, 3200);
    expect(result.marginPercent, closeTo(64, 0.001));
    expect(result.hasDebt, isTrue);

    expect(
      await finance.addPayment(
        order: order,
        amount: 500,
        kind: PaymentKind.refund,
        method: PaymentMethod.cash,
        at: DateTime(2026, 11, 3),
      ),
      isNull,
    );
    result = await finance.orderFinance(order);
    expect(result.paid, 1500);
    expect(result.due, 3500);

    final tooMuch = await finance.addPayment(
      order: order,
      amount: 2000,
      kind: PaymentKind.refund,
      method: PaymentMethod.cash,
      at: DateTime(2026, 11, 3),
    );
    expect(tooMuch, contains('Возврат больше'));
  });

  test('карточка заказа получает оплачено и долг', () async {
    final order = await orders.create(title: 'Карточка', amount: 1000);
    await finance.addPayment(
      order: order,
      amount: 300,
      kind: PaymentKind.advance,
      method: PaymentMethod.cash,
      at: DateTime(2026, 11, 1),
    );
    final stats = (await orders.stats())[order.id]!;
    expect(stats.paid, 300);
    expect(stats.due, 700);
  });

  test('касса, долги и период', () async {
    final first = await orders.create(
      title: 'Первый',
      amount: 5000,
      createdAt: DateTime(2026, 11, 1),
    );
    final second = await orders.create(
      title: 'Второй',
      amount: 3000,
      createdAt: DateTime(2026, 10, 1),
    );
    await stockAndIssue(first.id);
    await finance.addPayment(
      order: first,
      amount: 2000,
      kind: PaymentKind.advance,
      method: PaymentMethod.card,
      at: DateTime(2026, 11, 1),
    );
    await finance.addExpense(
      order: first,
      category: ExpenseCategory.labor,
      amount: 500,
      at: DateTime(2026, 11, 1),
    );
    await finance.addPayment(
      order: second,
      amount: 3000,
      kind: PaymentKind.payment,
      method: PaymentMethod.transfer,
      at: DateTime(2026, 10, 2),
    );

    final all = await finance.summary();
    expect(all.revenue, 8000);
    expect(all.debt, 3000);
    expect(all.debtorsCount, 1);
    expect(all.cashIn, 5000);
    expect(all.cashOut, 500);
    expect(all.netCash, 4500);
    expect(all.materialCost, 1000);
    expect(all.expenses, 500);
    expect(all.profit, 6500);

    final november = await finance.summary(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(november.revenue, 5000);
    expect(november.received, 2000);
    expect(november.cashIn, 2000);
    expect(november.cashOut, 500);
    expect(november.profit, 3500);

    final debtors = await finance.debtors();
    expect(debtors, hasLength(1));
    expect(debtors.first.$1.id, first.id);
    expect(debtors.first.$2.due, 3000);

    final cash = await finance.cashEntries(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(cash.where((entry) => entry.isIncome), hasLength(1));
    expect(cash.where((entry) => !entry.isIncome), hasLength(1));
  });

  test('удаление оплаты и расхода пересчитывает итоги', () async {
    final order = await orders.create(title: 'Заказ', amount: 1000);
    await finance.addPayment(
      order: order,
      amount: 400,
      kind: PaymentKind.advance,
      method: PaymentMethod.cash,
      at: DateTime(2026, 11, 1),
    );
    await finance.addExpense(
      order: order,
      category: ExpenseCategory.other,
      amount: 100,
      at: DateTime(2026, 11, 1),
    );
    var result = await finance.orderFinance(order);
    expect(result.paid, 400);
    expect(result.totalCost, 100);
    expect(
      await finance.deletePayment(order.id, result.payments.first.id),
      isTrue,
    );
    expect(
      await finance.deleteExpense(order.id, result.expenses.first.id),
      isTrue,
    );
    result = await finance.orderFinance(order);
    expect(result.paid, 0);
    expect(result.totalCost, 0);
  });

  test('миграция создаёт таблицы финансов', () async {
    final db = await database.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('order_payments','order_expenses')",
    );
    expect(rows, hasLength(2));
  });
}
