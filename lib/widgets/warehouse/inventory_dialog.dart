import 'package:flutter/material.dart';

import '../../models/warehouse.dart';
import '../../services/catalog_index.dart';
import '../catalog/grouped_catalog_picker.dart';
import '../design/app_kit.dart';

/// Ведомость инвентаризации: фактический остаток по каждой позиции.
Future<Map<String, double>?> showInventoryDialog(
  BuildContext context, {
  required WarehouseSnapshot snapshot,
}) {
  return showDialog<Map<String, double>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _InventoryDialog(snapshot: snapshot),
  );
}

class _InventoryDialog extends StatefulWidget {
  const _InventoryDialog({required this.snapshot});

  final WarehouseSnapshot snapshot;

  @override
  State<_InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<_InventoryDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final _note = TextEditingController(text: 'Плановая инвентаризация');
  final _search = TextEditingController();
  String _query = '';
  final Set<String> _expandedGroups = {};
  String? _selectedProductId;
  CatalogItem? _pickedCatalog;

  @override
  void initState() {
    super.initState();
    for (final stock in widget.snapshot.stocks) {
      if (stock.product.archived) continue;
      _controllers[stock.product.id] = TextEditingController(
        text: appQty(stock.balance),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  double _actual(String id) =>
      double.tryParse(_controllers[id]?.text.replaceAll(',', '.') ?? '') ?? 0;

  int get _differences => widget.snapshot.stocks.where((stock) {
    if (stock.product.archived) return false;
    return (_actual(stock.product.id) - stock.balance).abs() > 0.000001;
  }).length;

  List<WarehouseStock> get _visible {
    final query = _query.trim().toLowerCase();
    return [
      for (final stock in widget.snapshot.stocks)
        if (!stock.product.archived &&
            (_selectedProductId == null ||
                stock.product.id == _selectedProductId) &&
            (query.isEmpty ||
                '${stock.product.name} ${stock.product.category} '
                        '${stock.product.location}'
                    .toLowerCase()
                    .contains(query)))
          stock,
    ];
  }

  /// Фильтр по цветной позиции: выбор через общее дерево номенклатуры.
  Widget _catalogBar() {
    final picked = _pickedCatalog;
    return Row(
      children: [
        OutlinedButton.icon(
          key: const Key('inventory-catalog-pick'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _pickCatalog,
          icon: const Icon(Icons.category_outlined, size: 17),
          label: const Text(
            'Выбрать из номенклатуры',
            style: TextStyle(fontSize: 11.5),
          ),
        ),
        if (picked != null) ...[
          const SizedBox(width: 10),
          CatalogSwatch(color: picked.swatch),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              picked.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          TextButton(
            key: const Key('inventory-catalog-clear'),
            onPressed: () => setState(() {
              _selectedProductId = null;
              _pickedCatalog = null;
            }),
            child: const Text('Показать все'),
          ),
        ] else
          const Spacer(),
      ],
    );
  }

  Future<void> _pickCatalog() async {
    final items = CatalogItem.fromStocks(widget.snapshot.stocks);
    if (items.isEmpty) return;
    final picked = await GroupedCatalogPicker.show(
      context,
      items: items,
      title: 'Фильтр по номенклатуре',
      selectedId: _selectedProductId,
      priceMode: CatalogPriceMode.none,
      showStock: true,
      showProductName: true,
      pickerKey: 'inventory-catalog',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedProductId = picked.id;
      _pickedCatalog = picked;
      _expandedGroups.add(catalogCategoryOf(picked.product));
    });
  }

  Widget _buildGroupedList() {
    if (_visible.isEmpty) {
      return const AppEmptyState(
        compact: true,
        icon: Icons.inventory_2_outlined,
        title: 'Нечего инвентаризировать',
        message: 'На складе нет активных товаров.',
      );
    }
    final groups = <String, List<WarehouseStock>>{};
    for (final stock in _visible) {
      final category = stock.product.category.trim().isEmpty
          ? 'Без категории'
          : stock.product.category;
      groups.putIfAbsent(category, () => []).add(stock);
    }
    final names = groups.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      children: [
        for (final name in names) ...[
          InkWell(
            onTap: () => setState(() {
              if (!_expandedGroups.add(name)) _expandedGroups.remove(name);
            }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    _expandedGroups.contains(name)
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppTokens.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  AppPill(
                    label: '${groups[name]!.length} поз.',
                    color: AppTokens.blue,
                  ),
                ],
              ),
            ),
          ),
          if (_expandedGroups.contains(name))
            for (final stock in groups[name]!) ...[
              _stockRow(stock),
              const SizedBox(height: 7),
            ],
          const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _stockRow(WarehouseStock stock) {
    final actual = _actual(stock.product.id);
    final delta = actual - stock.balance;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: delta.abs() > 0.000001
            ? AppTokens.copperSoft.withValues(alpha: 0.45)
            : AppTokens.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: delta.abs() > 0.000001
              ? const Color(0xFFE8CBB8)
              : AppTokens.lineSoft,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stock.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${stock.product.location.isEmpty ? 'без места' : stock.product.location} · '
                  'учёт ${appQty(stock.balance)} '
                  '${stock.product.unit.label}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTokens.faint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _controllers[stock.product.id],
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText: stock.product.unit.shortLabel,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              delta.abs() < 0.000001
                  ? '—'
                  : '${delta > 0 ? '+' : '−'}${appQty(delta.abs())}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: delta > 0 ? AppTokens.green : AppTokens.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final values = <String, double>{};
    for (final stock in widget.snapshot.stocks) {
      if (stock.product.archived) continue;
      values[stock.product.id] = _actual(stock.product.id);
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 32,
        vertical: narrow ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
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
                      color: AppTokens.greenSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: AppTokens.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Инвентаризация',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Введите фактический остаток. Разница попадёт в журнал.',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      hint: 'Найти товар по названию, категории, месту',
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppPill(
                    label: 'Расхождений: $_differences',
                    color: _differences == 0
                        ? AppTokens.green
                        : AppTokens.copper,
                    icon: Icons.compare_arrows,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: _catalogBar(),
            ),
            Flexible(child: _buildGroupedList()),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: 'Основание',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text('Провести ($_differences)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
