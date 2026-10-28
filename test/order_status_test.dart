import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/services/order_storage.dart';

void main() {
  test('статус заказа по умолчанию — новый', () {
    const project = OrderProject();
    expect(project.status, OrderStatus.newOrder);
    expect(project.statusChangedAt, isNull);
  });

  test('статус сохраняется и читается из JSON', () {
    final changed = DateTime.utc(2026, 10, 29, 12, 30);
    final project = const OrderProject().copyWith(
      status: OrderStatus.production,
      statusChangedAt: changed,
    );
    final restored = orderFromJson(orderToJson(project));
    expect(restored.status, OrderStatus.production);
    expect(restored.statusChangedAt, changed);
  });

  test('сводка сохранённого заказа содержит статус', () {
    final project = const OrderProject().copyWith(
      status: OrderStatus.ready,
      statusChangedAt: DateTime.utc(2026, 10, 29),
    );
    final summary = orderSummaryToJson(project);
    expect(summary['status'], 'ready');
    expect(summary['statusChangedAt'], isA<String>());
  });
}
