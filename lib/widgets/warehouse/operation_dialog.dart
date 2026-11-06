import 'package:flutter/material.dart';

import '../../models/order_record.dart';
import '../../models/warehouse.dart';
import '../design/app_kit.dart';

/// Виды операций в интерфейсе. Перемещение в модели — две записи журнала.
enum StockOperationMode {
  receipt('Приход', Icons.south_west, StockMoveType.receipt),
  purchase('Закупка', Icons.shopping_cart_outlined, StockMoveType.purchase),
  sale('Продажа', Icons.point_of_sale, StockMoveType.sale),
  issue('Списание в заказ', Icons.assignment_turned_in_outlined,
      StockMoveType.issue),
  writeOff('Списание брака', Icons.delete_outline, StockMoveType.writeOff),
  returnIn('Возврат', Icons.undo, StockMoveType.returnIn),
  transfer('Перемещение', Icons.swap_horiz, StockMoveType.transferOut),
  inventory('Инвентаризация', Icons.fact_check_outlined,
      StockMoveType.inventory);

  const StockOperationMode(this.label, this.icon, this.type);

  final String label;
  final IconData icon;
  final StockMoveType type;

  bool get isIncome =>
      this == StockOperationMode.receipt ||
      this == StockOperationMode.purchase ||
      this == StockOperationMode.returnIn;

  bool get needsPrice =>
      this == StockOperationMode.purchase ||
      this == StockOperationMode.sale ||
      this == StockOperationMode.receipt;

  bool get needsOrder =>
      this == StockOperationMode.issue ||
      this == StockOperationMode.sale ||
      this == StockOperationMode.returnIn;
}

/// Диалог проведения складской операции.
Future<StockOperation?> showStockOperationDialog(
  BuildContext context, {
  required WarehouseSnapshot snapshot,
  required List<OrderRecord> orders,
  WarehouseStock? initial,
  StockOperationMode? mode,
}) {
  return showDialog<StockOperation>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StockOperationDialog(
      snapshot: snapshot,
      orders: orders,
      initial: initial,
      initialMode: mode,
    ),
  );
}

class _StockOperationDialog extends StatefulWidget {
  const _StockOperationDialog({
    required this.snapshot,
    required this.orders,
    this.initial,
    this.initialMode,
  });

  final WarehouseSnapshot snapshot;
  final List<OrderRecord> orders;
  final WarehouseStock? initial;
  final StockOperationMode? initialMode;

  @override
  State<_StockOperationDialog> createState() => _StockOperationDialogState();
}

class _StockOperationDialogState extends State<_StockOperationDialog> {
  late StockOperationMode _mode;
  late WarehouseStock? _stock;
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _orderId = TextEditingController();
  final _locationTo = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? StockOperationMode.receipt;
    _stock = widget.initial ??
        (widget.snapshot.stocks.isEmpty ? null : widget.snapshot.stocks.first);
    _quantity.text = _mode == StockOperationMode.inventory
        ? appQty(_stock?.balance ?? 0)
        : '1';
    _syncPrice();
    _locationTo.text = _stock?.product.location ?? '';
  }

  @override
  void dispose() {
    for (final controller in [_quantity, _price, _orderId, _locationTo, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncPrice() {
    final stock = _stock;
    if (stock == null) return;
    if (_mode == StockOperationMode.sale) {
      _price.text = appQty(stock.product.salePrice);
    } else if (_mode == StockOperationMode.purchase ||
        _mode == StockOperationMode.receipt ||
        _mode == StockOperationMode.returnIn) {
      _price.text = appQty(
        stock.averageCost > 0 ? stock.averageCost : stock.product.purchasePrice,
      );
    } else {
      _price.text = appQty(
        stock.fifoCostFor(_quantityValue).clamp(0, double.infinity),
      );
    }
  }

  double get _quantityValue =>
      double.tryParse(_quantity.text.trim().replaceAll(',', '.')) ?? 0;

  double get _priceValue =>
      double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0;

  void _submit() {
    final stock = _stock;
    if (stock == null) {
      setState(() => _error = 'Выберите товар');
      return;
    }
    final quantity = _quantityValue;
    if (quantity <= 0) {
      setState(() => _error = 'Количество должно быть больше нуля');
      return;
    }
    if (_mode == StockOperationMode.issue && _orderId.text.isEmpty) {
      setState(() => _error = 'Выберите заказ для списания');
      return;
    }
    if (_mode == StockOperationMode.transfer && _locationTo.text.trim().isEmpty) {
      setState(() => _error = 'Укажите место, куда перемещаем');
      return;
    }
    if ((_mode == StockOperationMode.sale ||
            _mode == StockOperationMode.writeOff ||
            _mode == StockOperationMode.transfer) &&
        quantity > stock.available + 0.000001) {
      setState(() {
        _error = 'Доступно только ${appQty(stock.available)} '
            '${stock.product.unit.label} (с учётом резерва)';
      });
      return;
    }
    final type = _mode == StockOperationMode.transfer
        ? StockMoveType.transferOut
        : _mode.type;
    Navigator.of(context).pop(
      StockOperation(
        type: type,
        productId: stock.product.id,
        quantity: quantity,
        unitPrice: _mode == StockOperationMode.inventory ? null : _priceValue,
        unitCost: _mode == StockOperationMode.inventory
            ? stock.product.purchasePrice
            : _priceValue,
        orderId: _mode.needsOrder ? _orderId.text : '',
        note: _note.text.trim(),
        locationFrom: stock.product.location,
        locationTo: _mode == StockOperationMode.transfer
            ? _locationTo.text.trim()
            : stock.product.location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    final stock = _stock;
    final quantity = _quantityValue;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 32,
        vertical: narrow ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppTokens.copperGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.swap_vert, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Операция по складу',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Остаток изменится только после проведения — всё одной транзакцией',
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
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final mode in StockOperationMode.values)
                          _ModeChip(
                            mode: mode,
                            selected: _mode == mode,
                            onTap: () => setState(() {
                              _mode = mode;
                              _error = null;
                              _syncPrice();
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (widget.snapshot.stocks.isEmpty)
                      const AppBanner(
                        message:
                            'Сначала добавьте товар в номенклатуру — операции проводятся по карточке.',
                        tone: AppTokens.amber,
                        icon: Icons.warning_amber_outlined,
                      )
                    else ...[
                      _ProductField(
                        snapshot: widget.snapshot,
                        value: stock,
                        onChanged: (value) => setState(() {
                          _stock = value;
                          _syncPrice();
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (stock != null) _StockSummary(stock: stock),
                      const SizedBox(height: 14),
                      _two(
                        narrow,
                        AppField(
                          label: _mode == StockOperationMode.inventory
                              ? 'Фактический остаток, ${stock?.product.unit.label ?? ''}'
                              : 'Количество, ${stock?.product.unit.label ?? ''}',
                          controller: _quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            if (_mode == StockOperationMode.writeOff ||
                                _mode == StockOperationMode.sale) {
                              _syncPrice();
                            }
                            setState(() {});
                          },
                        ),
                        (_mode.needsPrice ||
                                _mode == StockOperationMode.inventory)
                            ? AppField(
                                label: _mode == StockOperationMode.sale
                                    ? 'Цена продажи, ₽'
                                    : _mode == StockOperationMode.inventory
                                    ? 'Себестоимость для излишка, ₽'
                                    : 'Цена закупки, ₽',
                                controller: _price,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                              )
                            : AppField(
                                label: 'Себестоимость, ₽',
                                controller: _price,
                                hint: 'FIFO',
                                enabled: false,
                              ),
                      ),
                      if (_mode.needsOrder) ...[
                        const SizedBox(height: 12),
                        _OrderField(
                          orders: widget.orders,
                          value: _orderId.text,
                          onChanged: (value) => setState(() {
                            _orderId.text = value;
                            _error = null;
                          }),
                        ),
                      ],
                      if (_mode == StockOperationMode.transfer) ...[
                        const SizedBox(height: 12),
                        _two(
                          narrow,
                          AppField(
                            label: 'Откуда',
                            controller: TextEditingController(
                              text: stock?.product.location ?? '—',
                            ),
                            enabled: false,
                          ),
                          AppField(
                            label: 'Куда *',
                            controller: _locationTo,
                            hint: 'Склад Б, стеллаж 2',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      AppField(
                        label: 'Примечание',
                        controller: _note,
                        hint: 'Партия, поставщик, причина списания',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      _Preview(
                        mode: _mode,
                        stock: stock,
                        quantity: quantity,
                        price: _priceValue,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      AppBanner(
                        message: _error!,
                        tone: AppTokens.red,
                        icon: Icons.error_outline,
                      ),
                    ],
                    const SizedBox(height: 10),
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
                      'Товар, количество и цены проверяются до записи.',
                      style: TextStyle(fontSize: 10.5, color: AppTokens.faint),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('warehouse-move-save'),
                    onPressed: widget.snapshot.stocks.isEmpty ? null : _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text('Провести · ${_mode.label.toLowerCase()}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _two(bool narrow, Widget left, Widget right) {
    if (narrow) {
      return Column(
        children: [left, const SizedBox(height: 10), right],
      );
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final StockOperationMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.ink : AppTokens.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppTokens.ink : AppTokens.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode.icon,
                size: 16,
                color: selected ? Colors.white : AppTokens.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTokens.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductField extends StatelessWidget {
  const _ProductField({
    required this.snapshot,
    required this.value,
    required this.onChanged,
  });

  final WarehouseSnapshot snapshot;
  final WarehouseStock? value;
  final ValueChanged<WarehouseStock> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Товар',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value?.product.id,
          isExpanded: true,
          items: [
            for (final stock in snapshot.stocks)
              DropdownMenuItem(
                value: stock.product.id,
                child: Text(
                  '${stock.product.name} · ${appQty(stock.available)} '
                  '${stock.product.unit.label}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            final stock = snapshot.stocks
                .where((item) => item.product.id == id)
                .firstOrNull;
            if (stock != null) onChanged(stock);
          },
        ),
      ],
    );
  }
}

class _OrderField extends StatelessWidget {
  const _OrderField({
    required this.orders,
    required this.value,
    required this.onChanged,
  });

  final List<OrderRecord> orders;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Заказ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: orders.any((order) => order.id == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: orders.isEmpty
                ? 'Нет заказов — создайте на доске'
                : 'Выберите заказ',
          ),
          items: [
            for (final order in orders)
              DropdownMenuItem(
                value: order.id,
                child: Text(
                  '${order.number} · ${order.displayTitle}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => onChanged(id ?? ''),
        ),
      ],
    );
  }
}

class _StockSummary extends StatelessWidget {
  const _StockSummary({required this.stock});

  final WarehouseStock stock;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, {Color? tone}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTokens.faint),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tone ?? AppTokens.ink,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          cell('Остаток', '${appQty(stock.balance)} ${stock.product.unit.label}'),
          cell('Резерв', appQty(stock.reserved)),
          cell(
            'Доступно',
            appQty(stock.available),
            tone: stock.available <= 0 ? AppTokens.red : AppTokens.green,
          ),
          cell('Средняя', appMoney(stock.averageCost)),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.mode,
    required this.stock,
    required this.quantity,
    required this.price,
  });

  final StockOperationMode mode;
  final WarehouseStock? stock;
  final double quantity;
  final double price;

  @override
  Widget build(BuildContext context) {
    final product = stock?.product;
    if (product == null) return const SizedBox.shrink();
    final balance = stock!.balance;
    final next = switch (mode) {
      StockOperationMode.inventory => quantity,
      StockOperationMode.transfer => balance,
      StockOperationMode.receipt ||
      StockOperationMode.purchase ||
      StockOperationMode.returnIn => balance + quantity,
      _ => balance - quantity,
    };
    final amount = mode == StockOperationMode.inventory
        ? (quantity - balance).abs() * price
        : quantity * price;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.lineSoft),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        children: [
          Text(
            'Остаток: ${appQty(balance)} → ${appQty(next)} '
            '${product.unit.label}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTokens.inkSoft,
            ),
          ),
          Text(
            mode == StockOperationMode.inventory
                ? 'Сумма корректировки: ${appMoney(amount)}'
                : 'Сумма: ${appMoney(amount)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTokens.copper,
            ),
          ),
          if (mode == StockOperationMode.sale)
            Text(
              'Прибыль: ${appMoney(quantity * (price - (stock!.fifoCostFor(quantity))))}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.green,
              ),
            ),
        ],
      ),
    );
  }
}
