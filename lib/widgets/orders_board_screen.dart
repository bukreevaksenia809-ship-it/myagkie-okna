import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/order_storage.dart';

/// Доска заказов в стиле Jira: колонки по статусам, карточки, drag-and-drop.
Future<void> showOrdersBoardScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const OrdersBoardScreen()),
  );
}

class OrdersBoardScreen extends StatefulWidget {
  const OrdersBoardScreen({super.key});

  @override
  State<OrdersBoardScreen> createState() => _OrdersBoardScreenState();
}

class _OrdersBoardScreenState extends State<OrdersBoardScreen> {
  List<SavedOrder> _orders = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final orders = await listSavedOrders();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  List<SavedOrder> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _orders;
    return _orders
        .where(
          (order) =>
              order.title.toLowerCase().contains(query) ||
              order.customer.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _move(SavedOrder order, OrderStatus status) async {
    if (order.status == status) return;
    await updateSavedOrderStatus(order, status);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказы · доска'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('board-search'),
                          decoration: const InputDecoration(
                            hintText: 'Поиск по заказу или клиенту',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_orders.length} заказов',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6F746F),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final status in OrderStatus.values)
                          _column(status),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _column(OrderStatus status) {
    final items = _filtered
        .where((order) => order.status == status)
        .toList();
    return DragTarget<SavedOrder>(
      onAcceptWithDetails: (details) => _move(details.data, status),
      builder: (context, candidate, rejected) => Container(
        width: 290,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidate.isEmpty
              ? const Color(0xFFF7F2EA)
              : const Color(0xFFF1E2D2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3D9CC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Перетащи заказ сюда',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8A938D)),
                ),
              )
            else
              for (final order in items) _card(order),
          ],
        ),
      ),
    );
  }

  Widget _card(SavedOrder order) {
    return Draggable<SavedOrder>(
      data: order,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 270, child: _cardBody(order, dragging: true)),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _cardBody(order)),
      child: _cardBody(order),
    );
  }

  Widget _cardBody(SavedOrder order, {bool dragging = false}) {
    final deadline = order.deadline;
    final overdue = deadline != null &&
        DateUtils.dateOnly(deadline).isBefore(
          DateUtils.dateOnly(DateTime.now()),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dragging ? const Color(0xFFB86B3D) : const Color(0xFFE3D9CC),
        ),
        boxShadow: dragging
            ? const [BoxShadow(color: Color(0x22000000), blurRadius: 12)]
            : null,
      ),
      child: InkWell(
        onTap: () => _details(order),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${order.windowCount} окон · ${formatMeters(order.filmAreaM2)} м²',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6F746F)),
            ),
            if (deadline != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(
                    overdue
                        ? Icons.warning_amber_rounded
                        : Icons.schedule,
                    size: 14,
                    color: overdue
                        ? const Color(0xFFB03A3A)
                        : const Color(0xFFB86B3D),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${deadline.day.toString().padLeft(2, '0')}.${deadline.month.toString().padLeft(2, '0')}.${deadline.year}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: overdue
                          ? const Color(0xFFB03A3A)
                          : const Color(0xFF6F746F),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _details(SavedOrder order) async {
    final next = await showDialog<OrderStatus>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(order.title),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Клиент: ${order.customer.isEmpty ? '—' : order.customer}\n'
              'Окон: ${order.windowCount}\n'
              'Площадь плёнки: ${order.filmAreaM2.toStringAsFixed(2)} м²\n'
              'Статус: ${order.status.label}',
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Перенести в статус:', style: TextStyle(fontSize: 11)),
          ),
          for (final status in OrderStatus.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(status),
              child: Text(status.label),
            ),
        ],
      ),
    );
    if (next != null && next != order.status) await _move(order, next);
  }
}
