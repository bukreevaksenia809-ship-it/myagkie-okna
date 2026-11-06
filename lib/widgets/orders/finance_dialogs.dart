import 'package:flutter/material.dart';

import '../../data/finance_repository.dart';
import '../../models/finance.dart';
import '../../models/order_record.dart';
import '../design/app_kit.dart';

/// Окно оплаты по заказу: аванс, доплата или возврат.
Future<bool> showOrderPaymentDialog(
  BuildContext context, {
  required OrderRecord order,
  required OrderFinance finance,
  String author = '',
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _PaymentDialog(order: order, finance: finance, author: author),
  );
  return changed == true;
}

/// Окно расхода по заказу.
Future<bool> showOrderExpenseDialog(
  BuildContext context, {
  required OrderRecord order,
  String author = '',
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ExpenseDialog(order: order, author: author),
  );
  return changed == true;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.order,
    required this.finance,
    required this.author,
  });

  final OrderRecord order;
  final OrderFinance finance;
  final String author;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.finance.due > 0.005
        ? _plain(widget.finance.due)
        : _plain(widget.order.amount),
  );
  final _note = TextEditingController();
  PaymentKind _kind = PaymentKind.payment;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _at = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value =>
      double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await FinanceRepository.instance.addPayment(
      order: widget.order,
      amount: _value,
      kind: _kind,
      method: _method,
      at: _at,
      note: _note.text,
      author: widget.author,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final finance = widget.finance;
    return AlertDialog(
      title: Text('Оплата · ${widget.order.number}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _factChip('Сумма', appMoney(finance.amount)),
                  _factChip('Оплачено', appMoney(finance.paid)),
                  _factChip(
                    'Долг',
                    appMoney(finance.due),
                    color: finance.hasDebt ? AppTokens.red : AppTokens.green,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SegmentedButton<PaymentKind>(
                showSelectedIcon: false,
                segments: [
                  for (final kind in PaymentKind.values)
                    ButtonSegment(value: kind, label: Text(kind.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Сумма, ₽',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _kind = PaymentKind.advance;
                      _amount.text = _plain(finance.amount * 0.5);
                    }),
                    child: const Text('Аванс 50%'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _kind = PaymentKind.payment;
                      _amount.text = _plain(finance.due);
                    }),
                    child: const Text('Остаток'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Способ оплаты',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final method in PaymentMethod.values)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(appDate(_at)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTokens.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving || _value <= 0 ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _at = picked);
  }

  Widget _factChip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? AppTokens.muted).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color ?? AppTokens.inkSoft,
        ),
      ),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({required this.order, required this.author});

  final OrderRecord order;
  final String author;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.materials;
  DateTime _at = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value =>
      double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await FinanceRepository.instance.addExpense(
      order: widget.order,
      category: _category,
      amount: _value,
      at: _at,
      note: _note.text,
      author: widget.author,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Расход · ${widget.order.number}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Материалы со склада учитываются автоматически по FIFO. '
                'Здесь добавьте работу, доставку, монтаж или покупку вне склада.',
                style: TextStyle(fontSize: 11, color: AppTokens.muted),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExpenseCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Статья',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in ExpenseCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Сумма, ₽',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(appDate(_at)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTokens.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving || _value <= 0 ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _at = picked);
  }
}

String _plain(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2).replaceAll('.', ',');
}
