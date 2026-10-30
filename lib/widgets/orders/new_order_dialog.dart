import 'package:flutter/material.dart';

import '../../models/order_project.dart';
import '../../models/order_record.dart';
import '../design/app_kit.dart';

/// Данные формы нового заказа.
class NewOrderInput {
  const NewOrderInput({
    required this.title,
    required this.customer,
    required this.phone,
    required this.address,
    required this.priority,
    required this.assignee,
    required this.labels,
    required this.comment,
    this.deadline,
    this.status,
  });

  final String title;
  final String customer;
  final String phone;
  final String address;
  final OrderPriority priority;
  final String assignee;
  final List<String> labels;
  final String comment;
  final DateTime? deadline;
  final OrderStatus? status;
}

/// Форма нового заказа.
Future<NewOrderInput?> showNewOrderDialog(
  BuildContext context, {
  List<String> assignees = const [],
  List<String> labels = const [],
  OrderStatus? initialStatus,
}) {
  return showDialog<NewOrderInput>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NewOrderDialog(
      assignees: assignees,
      labels: labels,
      initialStatus: initialStatus,
    ),
  );
}

class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog({
    required this.assignees,
    required this.labels,
    this.initialStatus,
  });

  final List<String> assignees;
  final List<String> labels;
  final OrderStatus? initialStatus;

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  final _title = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _assignee = TextEditingController();
  final _labels = TextEditingController();
  final _comment = TextEditingController();
  OrderPriority _priority = OrderPriority.normal;
  DateTime? _deadline;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _title,
      _customer,
      _phone,
      _address,
      _assignee,
      _labels,
      _comment,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _submit() {
    if (_title.text.trim().isEmpty && _customer.text.trim().isEmpty) {
      setState(() => _error = 'Укажите название заказа или клиента');
      return;
    }
    Navigator.of(context).pop(
      NewOrderInput(
        title: _title.text.trim(),
        customer: _customer.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        priority: _priority,
        assignee: _assignee.text.trim(),
        labels: _labels.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        comment: _comment.text.trim(),
        deadline: _deadline,
        status: widget.initialStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 720;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 32,
        vertical: narrow ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppTokens.copperGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Новый заказ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Карточка появится на доске. Дизайн окон — в конструкторе.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppField(
                      label: 'Название заказа',
                      controller: _title,
                      hint: 'Например: Беседка на даче, ул. Лесная 12',
                      autofocus: true,
                    ),
                    const SizedBox(height: 10),
                    _two(
                      narrow,
                      AppField(
                        label: 'Клиент',
                        controller: _customer,
                        hint: 'Фамилия или компания',
                      ),
                      AppField(
                        label: 'Телефон',
                        controller: _phone,
                        hint: '+7 …',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppField(
                      label: 'Адрес',
                      controller: _address,
                      hint: 'Город, улица, дом, объект',
                    ),
                    const SizedBox(height: 10),
                    _two(
                      narrow,
                      _priorityField(),
                      _deadlineField(),
                    ),
                    const SizedBox(height: 10),
                    _two(
                      narrow,
                      _assigneeField(),
                      AppField(
                        label: 'Метки',
                        controller: _labels,
                        hint: 'через запятую: монтаж, срочно',
                      ),
                    ),
                    if (widget.labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in widget.labels)
                            ActionChip(
                              label: Text(label),
                              onPressed: () {
                                final current = _labels.text
                                    .split(',')
                                    .map((value) => value.trim())
                                    .where((value) => value.isNotEmpty)
                                    .toList();
                                if (!current.contains(label)) current.add(label);
                                _labels.text = current.join(', ');
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    AppField(
                      label: 'Комментарий',
                      controller: _comment,
                      maxLines: 3,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      AppBanner(
                        message: _error!,
                        tone: AppTokens.red,
                        icon: Icons.error_outline,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Номер заказа присвоится автоматически.',
                      style: TextStyle(fontSize: 10.5, color: AppTokens.faint),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('order-create-save'),
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Создать и открыть'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Приоритет',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<OrderPriority>(
          initialValue: _priority,
          items: [
            for (final priority in OrderPriority.values)
              DropdownMenuItem(
                value: priority,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: priority.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(priority.label),
                  ],
                ),
              ),
          ],
          onChanged: (value) =>
              setState(() => _priority = value ?? _priority),
        ),
      ],
    );
  }

  Widget _deadlineField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Срок сдачи',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickDeadline,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTokens.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTokens.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_outlined, size: 18, color: AppTokens.copper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _deadline == null
                        ? 'Без срока'
                        : appDate(_deadline),
                    style: TextStyle(
                      fontSize: 13,
                      color: _deadline == null
                          ? AppTokens.faint
                          : AppTokens.ink,
                    ),
                  ),
                ),
                if (_deadline != null)
                  IconButton(
                    tooltip: 'Убрать срок',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _deadline = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _assigneeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ответственный',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: _assignee,
          decoration: const InputDecoration(hintText: 'Кто ведёт заказ'),
        ),
        if (widget.assignees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final assignee in widget.assignees.take(6))
                  ActionChip(
                    label: Text(assignee, style: const TextStyle(fontSize: 10)),
                    onPressed: () => setState(() => _assignee.text = assignee),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _two(bool narrow, Widget left, Widget right) {
    if (narrow) {
      return Column(children: [left, const SizedBox(height: 10), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}
