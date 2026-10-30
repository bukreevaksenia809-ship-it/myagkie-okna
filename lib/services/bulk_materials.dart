import '../data/order_repository.dart';
import '../data/warehouse_repository.dart';
import '../models/order_record.dart';
import '../models/price_list.dart';
import '../models/warehouse.dart';
import 'order_materials.dart';

/// Одна строка суммарной потребности по выборке заказов.
class BulkMaterialLine {
  const BulkMaterialLine({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.available,
    required this.reserved,
    required this.orders,
    this.source = '',
  });

  final String productId;
  final String name;
  final StockUnit unit;
  final double quantity;
  final double available;
  final double reserved;
  final int orders;
  final String source;

  double get shortage => quantity <= available ? 0 : quantity - available;

  bool get enough => shortage <= 0.0001;
}

/// Итог расчёта материалов по нескольким заказам.
class BulkMaterialsResult {
  const BulkMaterialsResult({
    required this.lines,
    required this.unmatched,
    required this.orderCount,
    required this.windowCount,
    required this.amount,
  });

  final List<BulkMaterialLine> lines;
  final List<String> unmatched;
  final int orderCount;
  final int windowCount;
  final double amount;

  int get shortageCount => lines.where((line) => line.shortage > 0).length;

  List<BulkMaterialLine> get shortages =>
      lines.where((line) => line.shortage > 0).toList();
}

/// Складывает потребность в материалах по сметам и раскрою для выборки
/// заказов — в том числе от разных клиентов и за разные даты.
class BulkMaterialsCalculator {
  BulkMaterialsCalculator({
    OrderRepository? orders,
    WarehouseRepository? warehouse,
  }) : _orders = orders ?? OrderRepository.instance,
       _warehouse = warehouse ?? WarehouseRepository.instance;

  final OrderRepository _orders;
  final WarehouseRepository _warehouse;

  Future<BulkMaterialsResult> calculate(
    List<OrderRecord> selected, {
    PriceList prices = const PriceList.defaults(),
  }) async {
    final totals = <String, BulkMaterialLine>{};
    final unmatched = <String>[];
    var windows = 0;
    var amount = 0.0;
    final service = OrderMaterialsService(warehouse: _warehouse);
    for (final order in selected) {
      final project = _orders.projectOf(order);
      windows += project.windowCount;
      final plan = await service.plan(project, prices: prices);
      amount += plan.estimateTotal;
      for (final need in plan.needs) {
        final previous = totals[need.productId];
        totals[need.productId] = BulkMaterialLine(
          productId: need.productId,
          name: need.name,
          unit: need.unit,
          quantity: (previous?.quantity ?? 0) + need.quantity,
          available: need.available,
          reserved: need.reserved,
          orders: previous?.orders ?? 1,
          source: previous?.source ?? need.source,
        );
      }
      for (final line in plan.unmatched) {
        unmatched.add('${order.number}: $line');
      }
    }
    final checked = await _warehouse.checkNeeds([
      for (final line in totals.values)
        OrderMaterialNeed(
          productId: line.productId,
          name: line.name,
          unit: line.unit,
          quantity: line.quantity,
          available: line.available,
          reserved: line.reserved,
          source: line.source,
        ),
    ]);
    final lines = [
      for (final need in checked)
        BulkMaterialLine(
          productId: need.productId,
          name: need.name,
          unit: need.unit,
          quantity: need.quantity,
          available: need.available,
          reserved: need.reserved,
          orders: totals[need.productId]?.orders ?? 1,
          source: totals[need.productId]?.source ?? need.source,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return BulkMaterialsResult(
      lines: lines,
      unmatched: unmatched,
      orderCount: selected.length,
      windowCount: windows,
      amount: amount,
    );
  }
}
