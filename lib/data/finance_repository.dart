import 'dart:math' as math;

import '../models/finance.dart';
import '../models/order_project.dart';
import '../models/order_record.dart';
import '../models/warehouse.dart';
import 'app_database.dart';
import 'order_repository.dart';

/// Оплаты, расходы и себестоимость заказов.
class FinanceRepository {
  FinanceRepository({AppDatabase? database, OrderRepository? orders})
    : _database = database ?? AppDatabase.instance,
      _orders = orders ?? OrderRepository.instance;

  static final FinanceRepository instance = FinanceRepository();

  final AppDatabase _database;
  final OrderRepository _orders;

  Future<List<OrderPayment>> payments(String orderId) async {
    final db = await _database.database;
    final rows = await db.query(
      'order_payments',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'at DESC, id DESC',
    );
    return [for (final row in rows) OrderPayment.fromDb(row)];
  }

  Future<List<OrderExpense>> expenses(String orderId) async {
    final db = await _database.database;
    final rows = await db.query(
      'order_expenses',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'at DESC, id DESC',
    );
    return [for (final row in rows) OrderExpense.fromDb(row)];
  }

  /// Себестоимость материалов, фактически списанных по заказу, по FIFO.
  Future<double> materialCost(String orderId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(CASE '
      'WHEN type = ? THEN quantity * unit_cost '
      'WHEN type = ? THEN -quantity * unit_cost '
      'ELSE 0 END), 0) AS cost '
      'FROM stock_moves WHERE order_id = ?',
      [StockMoveType.issue.name, StockMoveType.returnIn.name, orderId],
    );
    final value = rows.isEmpty
        ? 0.0
        : ((rows.first['cost'] as num?)?.toDouble() ?? 0.0);
    return math.max(0.0, value);
  }

  Future<OrderFinance> orderFinance(OrderRecord order) async {
    final results = await Future.wait<Object>([
      payments(order.id),
      expenses(order.id),
      materialCost(order.id),
    ]);
    return OrderFinance(
      orderId: order.id,
      amount: order.amount,
      materialCost: results[2] as double,
      payments: results[0] as List<OrderPayment>,
      expenses: results[1] as List<OrderExpense>,
    );
  }

  /// Добавляет оплату. Возвращает текст ошибки или null.
  Future<String?> addPayment({
    required OrderRecord order,
    required double amount,
    required PaymentKind kind,
    required PaymentMethod method,
    required DateTime at,
    String note = '',
    String author = '',
  }) async {
    if (!amount.isFinite || amount <= 0.005) {
      return 'Сумма оплаты должна быть больше нуля';
    }
    if (kind == PaymentKind.refund) {
      final finance = await orderFinance(order);
      if (amount > finance.paid + 0.005) {
        return 'Возврат больше, чем клиент уже оплатил '
            '(${_money(finance.paid)})';
      }
    }
    final db = await _database.database;
    await db.insert('order_payments', {
      'order_id': order.id,
      'amount': amount,
      'kind': kind.name,
      'method': method.name,
      'at': at.toIso8601String(),
      'note': note.trim(),
      'author': author,
      'created_at': DateTime.now().toIso8601String(),
    });
    return null;
  }

  Future<bool> deletePayment(String orderId, int id) async {
    final db = await _database.database;
    final count = await db.delete(
      'order_payments',
      where: 'id = ? AND order_id = ?',
      whereArgs: [id, orderId],
    );
    return count > 0;
  }

  /// Добавляет расход. Возвращает текст ошибки или null.
  Future<String?> addExpense({
    required OrderRecord order,
    required ExpenseCategory category,
    required double amount,
    required DateTime at,
    String note = '',
    String author = '',
  }) async {
    if (!amount.isFinite || amount <= 0.005) {
      return 'Сумма расхода должна быть больше нуля';
    }
    final db = await _database.database;
    await db.insert('order_expenses', {
      'order_id': order.id,
      'category': category.name,
      'amount': amount,
      'at': at.toIso8601String(),
      'note': note.trim(),
      'author': author,
      'created_at': DateTime.now().toIso8601String(),
    });
    return null;
  }

  Future<bool> deleteExpense(String orderId, int id) async {
    final db = await _database.database;
    final count = await db.delete(
      'order_expenses',
      where: 'id = ? AND order_id = ?',
      whereArgs: [id, orderId],
    );
    return count > 0;
  }

  /// Финансы всех незаархивированных заказов — для отчёта по марже.
  Future<List<(OrderRecord, OrderFinance)>> orderFinances() async {
    final orders = await _orders.list(includeArchived: false);
    final result = <(OrderRecord, OrderFinance)>[];
    for (final order in orders) {
      if (order.status == OrderStatus.cancelled) continue;
      result.add((order, await orderFinance(order)));
    }
    return result;
  }

  /// Заказы с непогашенным долгом, сначала самые крупные.
  Future<List<(OrderRecord, OrderFinance)>> debtors() async {
    final orders = await _orders.list(includeArchived: false);
    final result = <(OrderRecord, OrderFinance)>[];
    for (final order in orders) {
      if (order.status == OrderStatus.cancelled) continue;
      final finance = await orderFinance(order);
      if (finance.hasDebt) result.add((order, finance));
    }
    result.sort((a, b) => b.$2.due.compareTo(a.$2.due));
    return result;
  }

  /// Итоги по заказам и кассе за период [from]…[to].
  Future<FinanceSummary> summary({DateTime? from, DateTime? to}) async {
    final orders = await _orders.list(includeArchived: false);
    final selected = [
      for (final order in orders)
        if (_inRange(order.createdAt, from, to) &&
            order.status != OrderStatus.cancelled)
          order,
    ];
    final allFinances = <(OrderRecord, OrderFinance)>[];
    var debt = 0.0;
    var debtors = 0;
    for (final order in orders) {
      final finance = await orderFinance(order);
      allFinances.add((order, finance));
      if (order.status != OrderStatus.cancelled && finance.hasDebt) {
        debt += finance.due;
        debtors++;
      }
    }
    var revenue = 0.0;
    var materialCost = 0.0;
    var expenses = 0.0;
    for (final order in selected) {
      final finance = allFinances
          .firstWhere((item) => item.$1.id == order.id)
          .$2;
      revenue += order.amount;
      materialCost += finance.materialCost;
      expenses += finance.manualCost;
    }
    final cash = await _cashTotals(from: from, to: to);
    return FinanceSummary(
      ordersCount: selected.length,
      revenue: revenue,
      received: cash.received,
      debt: debt,
      materialCost: materialCost,
      expenses: expenses,
      profit: revenue - materialCost - expenses,
      cashIn: cash.cashIn,
      cashOut: cash.cashOut,
      debtorsCount: debtors,
      byMethod: cash.byMethod,
      byCategory: {
        ...cash.byCategory,
        ExpenseCategory.materials:
            (cash.byCategory[ExpenseCategory.materials] ?? 0) + materialCost,
      },
    );
  }

  Future<_CashTotals> _cashTotals({DateTime? from, DateTime? to}) async {
    final db = await _database.database;
    final payments = await db.query(
      'order_payments',
      where: _rangeSql('at', from, to),
      whereArgs: _rangeArgs(from, to),
    );
    final expenses = await db.query(
      'order_expenses',
      where: _rangeSql('at', from, to),
      whereArgs: _rangeArgs(from, to),
    );
    var received = 0.0;
    var cashIn = 0.0;
    var cashOut = 0.0;
    final byMethod = <PaymentMethod, double>{};
    for (final row in payments) {
      final payment = OrderPayment.fromDb(row);
      if (payment.kind == PaymentKind.refund) {
        cashOut += payment.amount;
        received -= payment.amount;
        byMethod[payment.method] =
            (byMethod[payment.method] ?? 0) - payment.amount;
      } else {
        cashIn += payment.amount;
        received += payment.amount;
        byMethod[payment.method] =
            (byMethod[payment.method] ?? 0) + payment.amount;
      }
    }
    final byCategory = <ExpenseCategory, double>{};
    for (final row in expenses) {
      final expense = OrderExpense.fromDb(row);
      cashOut += expense.amount;
      byCategory[expense.category] =
          (byCategory[expense.category] ?? 0) + expense.amount;
    }
    return _CashTotals(
      received: received,
      cashIn: cashIn,
      cashOut: cashOut,
      byMethod: byMethod,
      byCategory: byCategory,
    );
  }

  /// Движение денег: оплаты и расходы одной лентой.
  Future<List<CashEntry>> cashEntries({
    DateTime? from,
    DateTime? to,
    int limit = 800,
  }) async {
    final db = await _database.database;
    final payments = await db.rawQuery(
      'SELECT p.*, o.number AS order_number FROM order_payments p '
      'LEFT JOIN orders o ON o.id = p.order_id '
      'WHERE ${_rangeSql('p.at', from, to)} '
      'ORDER BY p.at DESC LIMIT ?',
      [..._rangeArgs(from, to), limit],
    );
    final expenses = await db.rawQuery(
      'SELECT e.*, o.number AS order_number FROM order_expenses e '
      'LEFT JOIN orders o ON o.id = e.order_id '
      'WHERE ${_rangeSql('e.at', from, to)} '
      'ORDER BY e.at DESC LIMIT ?',
      [..._rangeArgs(from, to), limit],
    );
    final result = <CashEntry>[
      for (final row in payments)
        CashEntry(
          id: _int(row['id']),
          orderId: '${row['order_id'] ?? ''}',
          orderNumber: '${row['order_number'] ?? ''}',
          at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
          amount: _double(row['amount']),
          label:
              '${PaymentKind.fromName('${row['kind'] ?? ''}').label} · '
              '${PaymentMethod.fromName('${row['method'] ?? ''}').label}',
          note: '${row['note'] ?? ''}',
          isIncome:
              PaymentKind.fromName('${row['kind'] ?? ''}') !=
              PaymentKind.refund,
        ),
      for (final row in expenses)
        CashEntry(
          id: _int(row['id']),
          orderId: '${row['order_id'] ?? ''}',
          orderNumber: '${row['order_number'] ?? ''}',
          at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
          amount: _double(row['amount']),
          label: ExpenseCategory.fromName('${row['category'] ?? ''}').label,
          note: '${row['note'] ?? ''}',
          isIncome: false,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return result.take(limit).toList();
  }

  String _rangeSql(String column, DateTime? from, DateTime? to) {
    if (from == null && to == null) return '1 = 1';
    if (from != null && to != null) return '$column >= ? AND $column <= ?';
    if (from != null) return '$column >= ?';
    return '$column <= ?';
  }

  List<Object?> _rangeArgs(DateTime? from, DateTime? to) {
    final args = <Object?>[];
    if (from != null) args.add(from.toIso8601String());
    if (to != null) {
      // Верхняя граница включительно: конец выбранного дня.
      args.add(
        DateTime(to.year, to.month, to.day, 23, 59, 59, 999).toIso8601String(),
      );
    }
    return args;
  }

  bool _inRange(DateTime? value, DateTime? from, DateTime? to) {
    if (value == null) return from == null && to == null;
    if (from != null &&
        value.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    if (to != null &&
        value.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59, 999))) {
      return false;
    }
    return true;
  }

  String _money(double value) {
    final text = value.toStringAsFixed(2).replaceAll('.', ',');
    return '$text ₽';
  }
}

class _CashTotals {
  const _CashTotals({
    required this.received,
    required this.cashIn,
    required this.cashOut,
    required this.byMethod,
    required this.byCategory,
  });

  final double received;
  final double cashIn;
  final double cashOut;
  final Map<PaymentMethod, double> byMethod;
  final Map<ExpenseCategory, double> byCategory;
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
