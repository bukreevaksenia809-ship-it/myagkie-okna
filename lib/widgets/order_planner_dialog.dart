import 'package:flutter/material.dart';

import '../services/order_storage.dart';

/// Ежедневник по сохранённым заказам: сроки, статусы и предупреждения.
Future<void> showOrderPlannerDialog(
  BuildContext context,
  List<SavedOrder> orders,
) {
  final planned = orders.where((order) => order.deadline != null).toList()
    ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.event_note_outlined, size: 22),
          SizedBox(width: 8),
          Text('Ежедневник'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: planned.isEmpty
            ? const Text(
                'У сохранённых заказов пока нет сроков. Укажи срок в карточке '
                'заказа — он появится здесь с предупреждением за 2 дня.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final order in planned) _PlannerRow(order: order),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

class _PlannerRow extends StatelessWidget {
  const _PlannerRow({required this.order});

  final SavedOrder order;

  @override
  Widget build(BuildContext context) {
    final deadline = DateUtils.dateOnly(order.deadline!);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = deadline.difference(today).inDays;
    final color = days < 0
        ? const Color(0xFFB03A3A)
        : days <= 2
        ? const Color(0xFFB86B3D)
        : const Color(0xFF52708C);
    final date =
        '${deadline.day.toString().padLeft(2, '0')}.'
        '${deadline.month.toString().padLeft(2, '0')}.${deadline.year}';
    final when = days < 0
        ? 'просрочен на ${-days} дн.'
        : days == 0
        ? 'сдать сегодня'
        : days <= 2
        ? 'осталось $days дн.'
        : 'осталось $days дн.';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '$date · $when · ${order.status.label}',
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
              ],
            ),
          ),
          Icon(
            days <= 2 ? Icons.warning_amber_rounded : Icons.schedule,
            color: color,
            size: 20,
          ),
        ],
      ),
    );
  }
}
