import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../services/order_storage.dart';

/// Раздел «Заказы»: сохранение, список сохранённых заказов и их сводки.
class OrdersPanel extends StatelessWidget {
  const OrdersPanel({
    super.key,
    required this.orders,
    required this.folderPath,
    required this.busy,
    required this.onSave,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    this.onBackup,
  });

  final List<SavedOrder> orders;
  final String folderPath;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onRefresh;
  final ValueChanged<SavedOrder> onOpen;
  final ValueChanged<SavedOrder> onDelete;
  final VoidCallback? onBackup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'СОХРАНЁННЫЕ ЗАКАЗЫ (ФАЙЛЫ)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: Color(0xFF66748A),
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Сохранить заказ'),
              ),
              IconButton(
                tooltip: 'Обновить список',
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              IconButton(
                key: const Key('backup-orders'),
                tooltip: 'Резервная копия заказов',
                onPressed: busy ? null : onBackup,
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            folderPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A93A0)),
          ),
          const SizedBox(height: 10),
          if (orders.isEmpty)
            const Text(
              'Сохранённых заказов пока нет. Кнопка «Сохранить заказ» пишет '
              'JSON с параметрами и сводкой расхода — он остаётся для отчётности.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            )
          else
            for (final order in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Открыть заказ',
                            visualDensity: VisualDensity.compact,
                            onPressed: busy ? null : () => onOpen(order),
                            icon: const Icon(Icons.folder_open, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Удалить файл заказа',
                            visualDensity: VisualDensity.compact,
                            onPressed: busy ? null : () => onDelete(order),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(order.status).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.status.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _statusColor(order.status),
                              ),
                            ),
                          ),
                          Text(
                        '${_date(order.savedAt)} · окон ${order.windowCount} · '
                        'плёнка ${order.filmAreaM2.toStringAsFixed(2).replaceAll('.', ',')} м² · '
                        'люверсов ${order.eyeletTotal}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF41506A),
                            ),
                          ),
                        ],
                      ),
                      if (order.edgeSummary.isNotEmpty)
                        Text(
                          order.edgeSummary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF66748A),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Color _statusColor(OrderStatus status) => switch (status) {
    OrderStatus.newOrder => const Color(0xFF52708C),
    OrderStatus.measured => const Color(0xFF0B62C4),
    OrderStatus.production => const Color(0xFFB86B3D),
    OrderStatus.ready => const Color(0xFF2E7D5B),
    OrderStatus.installed => const Color(0xFF4E4A46),
  };

  String _date(DateTime moment) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.day)}.${two(moment.month)}.${moment.year} '
        '${two(moment.hour)}:${two(moment.minute)}';
  }
}
