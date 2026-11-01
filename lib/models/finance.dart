import 'dart:math' as math;

/// Назначение платежа по заказу.
enum PaymentKind {
  advance('Аванс'),
  payment('Доплата'),
  refund('Возврат');

  const PaymentKind(this.label);

  final String label;

  static PaymentKind fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => PaymentKind.payment,
  );
}

/// Способ оплаты — для кассового отчёта.
enum PaymentMethod {
  cash('Наличные'),
  card('Карта'),
  transfer('Перевод'),
  other('Другое');

  const PaymentMethod(this.label);

  final String label;

  static PaymentMethod fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => PaymentMethod.other,
  );
}

/// Статья расхода заказа.
enum ExpenseCategory {
  materials('Материалы'),
  labor('Работа'),
  delivery('Доставка'),
  installation('Монтаж'),
  other('Прочее');

  const ExpenseCategory(this.label);

  final String label;

  static ExpenseCategory fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => ExpenseCategory.other,
  );
}

/// Платёж клиента по заказу. Сумма хранится положительной; возврат
/// учитывается со знаком минус через [signedAmount].
class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.kind,
    required this.method,
    required this.at,
    this.note = '',
    this.author = '',
  });

  final int id;
  final String orderId;
  final double amount;
  final PaymentKind kind;
  final PaymentMethod method;
  final DateTime at;
  final String note;
  final String author;

  double get signedAmount => kind == PaymentKind.refund ? -amount : amount;

  Map<String, Object?> toDb() => {
    'id': id == 0 ? null : id,
    'order_id': orderId,
    'amount': amount,
    'kind': kind.name,
    'method': method.name,
    'at': at.toIso8601String(),
    'note': note,
    'author': author,
    'created_at': DateTime.now().toIso8601String(),
  };

  factory OrderPayment.fromDb(Map<String, Object?> row) => OrderPayment(
    id: _int(row['id']),
    orderId: '${row['order_id'] ?? ''}',
    amount: _double(row['amount']),
    kind: PaymentKind.fromName('${row['kind'] ?? ''}'),
    method: PaymentMethod.fromName('${row['method'] ?? ''}'),
    at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
    note: '${row['note'] ?? ''}',
    author: '${row['author'] ?? ''}',
  );
}

/// Расход по заказу: материалы, работа, доставка, монтаж, прочее.
class OrderExpense {
  const OrderExpense({
    required this.id,
    required this.orderId,
    required this.category,
    required this.amount,
    required this.at,
    this.note = '',
    this.author = '',
  });

  final int id;
  final String orderId;
  final ExpenseCategory category;
  final double amount;
  final DateTime at;
  final String note;
  final String author;

  Map<String, Object?> toDb() => {
    'id': id == 0 ? null : id,
    'order_id': orderId,
    'category': category.name,
    'amount': amount,
    'at': at.toIso8601String(),
    'note': note,
    'author': author,
    'created_at': DateTime.now().toIso8601String(),
  };

  factory OrderExpense.fromDb(Map<String, Object?> row) => OrderExpense(
    id: _int(row['id']),
    orderId: '${row['order_id'] ?? ''}',
    category: ExpenseCategory.fromName('${row['category'] ?? ''}'),
    amount: _double(row['amount']),
    at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
    note: '${row['note'] ?? ''}',
    author: '${row['author'] ?? ''}',
  );
}

/// Финансы одного заказа: сумма, оплаты, расходы, долг и маржа.
class OrderFinance {
  const OrderFinance({
    required this.orderId,
    required this.amount,
    required this.materialCost,
    this.payments = const [],
    this.expenses = const [],
  });

  final String orderId;

  /// Сумма заказа по прайсу.
  final double amount;

  /// Себестоимость материалов, списанных со склада по FIFO.
  final double materialCost;

  final List<OrderPayment> payments;
  final List<OrderExpense> expenses;

  double get received => payments
      .where((payment) => payment.kind != PaymentKind.refund)
      .fold<double>(0, (sum, payment) => sum + payment.amount);

  double get refunded => payments
      .where((payment) => payment.kind == PaymentKind.refund)
      .fold<double>(0, (sum, payment) => sum + payment.amount);

  /// Чистое поступление: оплаты минус возвраты.
  double get paid => received - refunded;

  double get due => math.max(0, amount - paid);

  double get overpaid => math.max(0, paid - amount);

  double get manualCost =>
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  double get materialTotal =>
      materialCost + costByCategory[ExpenseCategory.materials]!;

  double get totalCost => materialCost + manualCost;

  double get margin => amount - totalCost;

  double? get marginPercent => amount > 0 ? margin / amount * 100 : null;

  Map<ExpenseCategory, double> get costByCategory {
    final result = <ExpenseCategory, double>{
      for (final category in ExpenseCategory.values) category: 0,
    };
    for (final expense in expenses) {
      result[expense.category] =
          (result[expense.category] ?? 0) + expense.amount;
    }
    return result;
  }

  bool get hasDebt => due > 0.005;

  bool get isProfitable => margin >= 0;
}

/// Строка кассового отчёта — оплата или расход.
class CashEntry {
  const CashEntry({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.at,
    required this.amount,
    required this.label,
    this.note = '',
    this.isIncome = true,
  });

  final int id;
  final String orderId;
  final String orderNumber;
  final DateTime at;
  final double amount;
  final String label;
  final String note;
  final bool isIncome;

  double get signedAmount => isIncome ? amount : -amount;
}

/// Итоги по всем заказам и движению денег за период.
class FinanceSummary {
  const FinanceSummary({
    required this.ordersCount,
    required this.revenue,
    required this.received,
    required this.debt,
    required this.materialCost,
    required this.expenses,
    required this.profit,
    required this.cashIn,
    required this.cashOut,
    required this.debtorsCount,
    this.byMethod = const {},
    this.byCategory = const {},
  });

  final int ordersCount;
  final double revenue;
  final double received;
  final double debt;
  final double materialCost;
  final double expenses;
  final double profit;
  final double cashIn;
  final double cashOut;
  final int debtorsCount;
  final Map<PaymentMethod, double> byMethod;
  final Map<ExpenseCategory, double> byCategory;

  double get netCash => cashIn - cashOut;

  double? get marginPercent => revenue > 0 ? profit / revenue * 100 : null;
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
