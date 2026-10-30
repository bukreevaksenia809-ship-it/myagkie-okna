import 'package:flutter/material.dart';

import '../models/warehouse.dart';
import '../models/window_params.dart';
import '../models/price_list.dart';
import '../services/order_storage.dart';
import '../services/warehouse_consumption.dart';
import '../services/warehouse_store.dart';

/// Полноценный экран склада: товары, движения, остатки и стоимость.
Future<void> showWarehouseScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const WarehouseScreen()),
  );
}

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  WarehouseData _data = WarehouseData();
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final data = await WarehouseStore.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  List<WarehouseProduct> get _visible {
    final query = _query.trim().toLowerCase();
    final items = [..._data.products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (query.isEmpty) return items;
    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) ||
              item.supplier.toLowerCase().contains(query) ||
              item.location.toLowerCase().contains(query),
        )
        .toList();
  }

  double get _stockValue => _data.stockValue;
  int get _lowCount => _data.lowStock.length;

  Future<void> _editProduct([WarehouseProduct? product]) async {
    final result = await showDialog<WarehouseProduct>(
      context: context,
      builder: (context) => _ProductDialog(product: product),
    );
    if (result == null) return;
    final data = await WarehouseStore.upsertProduct(result);
    if (!mounted) return;
    setState(() => _data = data);
  }

  Future<void> _deleteProduct(WarehouseProduct product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
          '«${product.name}» и все его движения будут удалены. Это действие '
          'нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final data = await WarehouseStore.deleteProduct(product.id);
    if (!mounted) return;
    setState(() => _data = data);
  }

  Future<void> _consumeOrder() async {
    final orders = await listSavedOrders();
    if (!mounted) return;
    if (orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала сохраните заказ')),
      );
      return;
    }
    final order = await showDialog<SavedOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Списать материалы по заказу'),
        children: [
          for (final item in orders)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(item),
              child: Text(item.title),
            ),
        ],
      ),
    );
    if (order == null) return;
    final project = await loadOrder(order);
    final message = await consumeOrderMaterials(
      project,
      orderTitle: order.title,
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Списание по заказу'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMove([WarehouseProduct? product]) async {
    if (_data.products.isEmpty) {
      await _editProduct();
      if (!mounted || _data.products.isEmpty) return;
    }
    final result = await showDialog<StockMove>(
      context: context,
      builder: (context) => _MoveDialog(
        products: _data.products,
        initial: product,
        data: _data,
      ),
    );
    if (result == null) return;
    final data = await WarehouseStore.addMove(result);
    if (!mounted) return;
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Склад материалов'),
        actions: [
          IconButton(
            key: const Key('warehouse-add-product'),
            tooltip: 'Новый товар',
            onPressed: () => _editProduct(),
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            key: const Key('warehouse-add-move'),
            tooltip: 'Приход / продажа / списание',
            onPressed: () => _addMove(),
            icon: const Icon(Icons.swap_vert),
          ),
          IconButton(
            key: const Key('warehouse-consume-order'),
            tooltip: 'Списать материалы по заказу',
            onPressed: _consumeOrder,
            icon: const Icon(Icons.assignment_turned_in_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(),
                const SizedBox(height: 14),
                _search(),
                const SizedBox(height: 12),
                if (_data.products.isEmpty)
                  _empty()
                else ...[
                  _sectionTitle('Товары', '${_visible.length}'),
                  const SizedBox(height: 8),
                  for (final product in _visible)
                    _productCard(product),
                  const SizedBox(height: 18),
                  _sectionTitle('Последние движения', '${_data.moves.length}'),
                  const SizedBox(height: 8),
                  _movesList(),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('warehouse-fab'),
        onPressed: () => _addMove(),
        icon: const Icon(Icons.add),
        label: const Text('Операция'),
      ),
    );
  }

  Widget _summary() {
    Widget card(String value, String label, IconData icon, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3D9CC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6F746F)),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        card('${_data.products.length}', 'позиций', Icons.inventory_2_outlined, const Color(0xFF52708C)),
        const SizedBox(width: 8),
        card(formatRubles(_stockValue), 'стоимость склада', Icons.payments_outlined, const Color(0xFF2E7D5B)),
        const SizedBox(width: 8),
        card('$_lowCount', 'ниже минимума', Icons.warning_amber_outlined, const Color(0xFFB86B3D)),
      ],
    );
  }

  Widget _search() => TextField(
    key: const Key('warehouse-search'),
    decoration: const InputDecoration(
      hintText: 'Поиск по названию, поставщику, месту',
      prefixIcon: Icon(Icons.search),
      isDense: true,
    ),
    onChanged: (value) => setState(() => _query = value),
  );

  Widget _empty() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE3D9CC)),
    ),
    child: Column(
      children: [
        const Icon(Icons.inventory_2_outlined, size: 42, color: Color(0xFFB86B3D)),
        const SizedBox(height: 10),
        const Text('Склад пока пуст', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Добавь материал, плёнку, фурнитуру или крепёж. Дальше — приход, '
          'продажа, списание в заказ и история.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF6F746F)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _editProduct(),
          icon: const Icon(Icons.add),
          label: const Text('Добавить товар'),
        ),
      ],
    ),
  );

  Widget _productCard(WarehouseProduct product) {
    final balance = _data.balanceOf(product.id);
    final low = balance <= product.minQuantity;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _addMove(product),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (low) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB86B3D)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatDecimal(balance)} ${product.unit.label} · закупка ${formatRubles(product.purchasePrice)} · продажа ${formatRubles(product.salePrice)}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF6F746F)),
                    ),
                    if (product.supplier.isNotEmpty || product.location.isNotEmpty)
                      Text(
                        [product.supplier, product.location].where((value) => value.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A938D)),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Движение',
                onPressed: () => _addMove(product),
                icon: const Icon(Icons.swap_vert),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editProduct(product);
                  if (value == 'delete') _deleteProduct(product);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _movesList() {
    final moves = [..._data.moves]..sort((a, b) => b.at.compareTo(a.at));
    if (moves.isEmpty) {
      return const Text('Движений пока нет.');
    }
    return Column(
      children: [
        for (final move in moves.take(30)) _moveTile(move),
      ],
    );
  }

  Widget _moveTile(StockMove move) {
    final product = _data.products.where((item) => item.id == move.productId).firstOrNull;
    return ListTile(
      dense: true,
      leading: Icon(
        move.type.increases ? Icons.south_west : Icons.north_east,
        color: move.type.increases ? const Color(0xFF2E7D5B) : const Color(0xFFB86B3D),
      ),
      title: Text('${move.type.label} · ${product?.name ?? 'товар удалён'}'),
      subtitle: Text(
        '${formatDecimal(move.quantity)} ${product?.unit.label ?? ''} · ${formatRubles(move.price)}'
        '${move.orderId.isEmpty ? '' : ' · заказ ${move.orderId}'}'
        '${move.note.isEmpty ? '' : ' · ${move.note}'}',
      ),
      trailing: Text(
        '${move.at.day.toString().padLeft(2, '0')}.${move.at.month.toString().padLeft(2, '0')}.${move.at.year}',
        style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A938D)),
      ),
    );
  }

  Widget _sectionTitle(String title, String trailing) => Row(
    children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
      Text(trailing, style: const TextStyle(fontSize: 11, color: Color(0xFF8A938D))),
    ],
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.product});
  final WarehouseProduct? product;
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _purchase;
  late final TextEditingController _sale;
  late final TextEditingController _width;
  late final TextEditingController _length;
  late final TextEditingController _min;
  late final TextEditingController _supplier;
  late final TextEditingController _location;
  late final TextEditingController _note;
  StockUnit _unit = StockUnit.piece;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _purchase = TextEditingController(text: p == null ? '' : formatDecimal(p.purchasePrice));
    _sale = TextEditingController(text: p == null ? '' : formatDecimal(p.salePrice));
    _width = TextEditingController(text: p == null ? '' : p.widthMm.toStringAsFixed(0));
    _length = TextEditingController(text: p == null ? '' : p.lengthMm.toStringAsFixed(0));
    _min = TextEditingController(text: p == null ? '' : formatDecimal(p.minQuantity));
    _supplier = TextEditingController(text: p?.supplier ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _note = TextEditingController(text: p?.note ?? '');
    _unit = p?.unit ?? StockUnit.piece;
  }

  @override
  void dispose() {
    for (final c in [_name, _purchase, _sale, _width, _length, _min, _supplier, _location, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Новый товар' : 'Товар склада'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 8),
              DropdownButtonFormField<StockUnit>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Единица'),
                items: [for (final unit in StockUnit.values) DropdownMenuItem(value: unit, child: Text(unit.label))],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _purchase, decoration: const InputDecoration(labelText: 'Закупка, ₽'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _sale, decoration: const InputDecoration(labelText: 'Продажа, ₽'))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _width, decoration: const InputDecoration(labelText: 'Ширина, мм'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _length, decoration: const InputDecoration(labelText: 'Длина, мм'))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _min, decoration: const InputDecoration(labelText: 'Минимальный остаток')),
              const SizedBox(height: 8),
              TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Поставщик')),
              const SizedBox(height: 8),
              TextField(controller: _location, decoration: const InputDecoration(labelText: 'Место хранения')),
              const SizedBox(height: 8),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Примечание')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          key: const Key('warehouse-product-save'),
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              WarehouseProduct(
                id: widget.product?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                name: _name.text.trim(),
                unit: _unit,
                purchasePrice: _n(_purchase),
                salePrice: _n(_sale),
                widthMm: _n(_width),
                lengthMm: _n(_length),
                minQuantity: _n(_min),
                supplier: _supplier.text.trim(),
                location: _location.text.trim(),
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.products, required this.data, this.initial});
  final List<WarehouseProduct> products;
  final WarehouseData data;
  final WarehouseProduct? initial;
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late WarehouseProduct _product;
  StockMoveType _type = StockMoveType.receipt;
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _price;
  final _order = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _product = widget.initial ?? widget.products.first;
    _price = TextEditingController(text: formatDecimal(_product.purchasePrice));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _order.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.data.balanceOf(_product.id);
    return AlertDialog(
      title: const Text('Движение по складу'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<WarehouseProduct>(
              initialValue: _product,
              decoration: const InputDecoration(labelText: 'Товар'),
              items: [
                for (final p in widget.products)
                  DropdownMenuItem(value: p, child: Text('${p.name} · ${formatDecimal(widget.data.balanceOf(p.id))} ${p.unit.label}')),
              ],
              onChanged: (p) => setState(() => _product = p ?? _product),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<StockMoveType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Операция'),
              items: [for (final t in StockMoveType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _quantity, decoration: InputDecoration(labelText: 'Количество, ${_product.unit.label}'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _price, decoration: const InputDecoration(labelText: 'Цена, ₽'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _order, decoration: const InputDecoration(labelText: 'Номер заказа (если списание)')),
            const SizedBox(height: 8),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Примечание')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Сейчас на складе: ${formatDecimal(balance)} ${_product.unit.label}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6F746F))),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          key: const Key('warehouse-move-save'),
          onPressed: () {
            final qty = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0;
            if (qty <= 0) return;
            if (!_type.increases && qty > balance) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Недостаточно остатка для этой операции')),
              );
              return;
            }
            Navigator.of(context).pop(
              StockMove(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                productId: _product.id,
                type: _type,
                quantity: qty,
                price: double.tryParse(_price.text.replaceAll(',', '.')) ?? _product.purchasePrice,
                at: DateTime.now(),
                orderId: _order.text.trim(),
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Провести'),
        ),
      ],
    );
  }
}
