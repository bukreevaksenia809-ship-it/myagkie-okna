import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/order_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../models/order_project.dart';
import '../../models/order_record.dart';
import '../../models/price_list.dart';
import '../../models/warehouse.dart';
import '../../services/app_bootstrap.dart';
import '../../services/file_saver.dart';
import '../../services/price_warehouse_sync.dart';
import 'design/app_kit.dart';
import 'warehouse/inventory_dialog.dart';
import 'warehouse/operation_dialog.dart';
import 'warehouse/bulk_materials_dialog.dart';
import 'warehouse/order_materials_dialog.dart';
import 'warehouse/product_editor.dart';

/// Открывает склад как отдельный экран (для старых точек входа).
Future<void> showWarehouseScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const WarehouseScreen(),
    ),
  );
}

enum WarehouseTab {
  stock('Номенклатура', Icons.inventory_2_outlined),
  journal('Журнал', Icons.receipt_long_outlined),
  batches('Партии', Icons.layers_outlined),
  reports('Отчёты', Icons.analytics_outlined);

  const WarehouseTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Профессиональный склад: номенклатура, журнал, партии, отчёты и связь с
/// заказами. Экран встраивается в общую оболочку приложения.
class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({
    super.key,
    this.embedded = false,
    this.currentProject,
    this.currentOrderTitle = '',
    this.onOpenOrders,
    this.prices = const PriceList.defaults(),
  });

  final bool embedded;
  final OrderProject? currentProject;
  final String currentOrderTitle;
  final VoidCallback? onOpenOrders;

  /// Прайс, из которого заполняется номенклатура.
  final PriceList prices;

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  final _warehouse = WarehouseRepository.instance;
  final _orders = OrderRepository.instance;

  WarehouseSnapshot? _snapshot;
  List<OrderRecord> _orderList = const [];
  WarehouseReport? _report;
  WarehouseTab _tab = WarehouseTab.stock;
  bool _loading = true;
  bool _busy = false;
  String _query = '';
  String _category = '';
  StockUnit? _unit;
  bool _archived = false;
  bool _onlyLow = false;
  String _message = '';
  bool _messageError = false;
  WarehouseReportKind _reportKind = WarehouseReportKind.stock;
  DateTime? _reportFrom;
  DateTime? _reportTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snapshot = await _warehouse.snapshot(includeArchived: true);
      final orders = await _orders.list();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _orderList = orders;
        _loading = false;
      });
      if (_tab == WarehouseTab.reports) await _loadReport();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Не удалось прочитать склад: $error';
        _messageError = true;
      });
    }
  }

  Future<void> _loadReport() async {
    final report = await _warehouse.report(
      _reportKind,
      from: _reportFrom,
      to: _reportTo,
    );
    if (!mounted) return;
    setState(() => _report = report);
  }

  List<WarehouseStock> get _stocks {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    final query = _query.trim().toLowerCase();
    final result = [
      for (final stock in snapshot.stocks)
        if ((_archived || !stock.product.archived) &&
            (!_onlyLow || stock.isLow) &&
            (_category.isEmpty || stock.product.category == _category) &&
            (_unit == null || stock.product.unit == _unit) &&
            (query.isEmpty ||
                '${stock.product.name} ${stock.product.category} '
                        '${stock.product.material} ${stock.product.color} '
                        '${stock.product.supplier} ${stock.product.location} '
                        '${stock.product.barcode}'
                    .toLowerCase()
                    .contains(query)))
          stock,
    ];
    result.sort((a, b) {
      if (a.product.archived != b.product.archived) {
        return a.product.archived ? 1 : -1;
      }
      if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
      return a.product.name.toLowerCase().compareTo(
        b.product.name.toLowerCase(),
      );
    });
    return result;
  }

  List<String> get _categories {
    final set = <String>{};
    for (final stock in _snapshot?.stocks ?? const <WarehouseStock>[]) {
      if (stock.product.category.trim().isNotEmpty) {
        set.add(stock.product.category.trim());
      }
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _toast(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageError = error;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTokens.red : AppTokens.ink,
      ),
    );
  }

  Future<void> _editProduct([WarehouseProduct? product]) async {
    final value = await showProductEditor(context, product: product);
    if (value == null) return;
    final result = await _warehouse.saveProduct(value);
    _toast(result.message, error: !result.ok);
    await _load();
  }

  Future<void> _operate({
    WarehouseStock? initial,
    StockOperationMode? mode,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final operation = await showStockOperationDialog(
      context,
      snapshot: snapshot,
      orders: _orderList,
      initial: initial,
      mode: mode,
    );
    if (operation == null) return;
    setState(() => _busy = true);
    final result = await _warehouse.perform(operation);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      [
        result.message,
        if (result.shortages.isNotEmpty) ...result.shortages,
      ].join('\n'),
      error: !result.ok,
    );
    await _load();
  }

  Future<void> _inventory() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final values = await showInventoryDialog(context, snapshot: snapshot);
    if (values == null) return;
    setState(() => _busy = true);
    final result = await _warehouse.inventoryAll(
      values,
      note: 'Инвентаризация из раздела «Склад»',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message, error: !result.ok);
    await _load();
  }

  Future<void> _syncFromPrice() async {
    setState(() => _busy = true);
    final count = await PriceWarehouseSync(warehouse: _warehouse).sync(
      widget.prices,
      updatePrices: true,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      count == 0
          ? 'Все позиции прайса уже есть на складе'
          : 'Добавлено позиций из прайса: $count',
    );
    await _load();
  }

  Future<void> _archive(WarehouseProduct product, bool archived) async {
    final result = await _warehouse.archiveProduct(product.id, archived);
    _toast(result.message, error: !result.ok);
    await _load();
  }

  Future<void> _delete(WarehouseProduct product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
          '«${product.name}» будет удалён. Если у него есть движения или '
          'связи с заказами, удаление будет запрещено — используйте архив.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTokens.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await _warehouse.deleteProduct(product.id);
    _toast(result.message, error: !result.ok);
    await _load();
  }

  Future<void> _details(WarehouseStock stock) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ProductDetailsDialog(
        stock: stock,
        onEdit: () => _editProduct(stock.product),
        onOperate: () => _operate(initial: stock),
        onArchive: () => _archive(stock.product, !stock.product.archived),
      ),
    );
    await _load();
  }

  Future<void> _openBulkMaterials() async {
    await showBulkMaterialsDialog(
      context,
      orders: _orderList,
      prices: widget.prices,
    );
    await _load();
  }

  Future<void> _openOrderMaterials() async {
    if (_orderList.isEmpty) {
      _toast('Сначала создайте заказ на доске', error: true);
      return;
    }
    final order = await showDialog<OrderRecord>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Материалы заказа'),
        children: [
          for (final item in _orderList)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.number} · ${item.displayTitle}')),
                    AppPill(
                      label: item.status.label,
                      color: item.isOverdue ? AppTokens.red : AppTokens.muted,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (order == null) return;
    if (!mounted) return;
    await showOrderMaterialsDialog(context, order);
    await _load();
  }

  Future<void> _exportReport() async {
    final report = _report;
    if (report == null) return;
    final buffer = StringBuffer();
    buffer.writeln(report.title);
    buffer.writeln(';${report.columns.join(';')}');
    for (final row in report.rows) {
      buffer.writeln(';${row.map(_csv).join(';')}');
    }
    buffer.writeln();
    for (final entry in report.totals.entries) {
      buffer.writeln('${_csv(entry.key)};${_csv(entry.value)}');
    }
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$buffer'));
    final saved = await saveBytes(
      bytes,
      'Склад-${report.kind.name}-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
    );
    if (!mounted) return;
    _toast('Отчёт сохранён: ${saved.destination}');
  }

  String _csv(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final body = SafeArea(
      child: _loading && snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: AppPageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (AppBootstrap.databaseError != null) ...[
                        AppBanner(
                          title: 'Локальная база не открылась',
                          message:
                              '${AppBootstrap.databaseError}\n'
                              'Склад и доска работают только при доступной базе. '
                              'Перезапустите приложение.',
                          tone: AppTokens.red,
                          icon: Icons.storage_outlined,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _header(),
                      const SizedBox(height: 18),
                      if (_message.isNotEmpty) ...[
                        AppBanner(
                          message: _message,
                          tone: _messageError ? AppTokens.red : AppTokens.green,
                          icon: _messageError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          action: IconButton(
                            tooltip: 'Скрыть',
                            onPressed: () => setState(() => _message = ''),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (snapshot != null) _metrics(snapshot),
                      const SizedBox(height: 18),
                      _tabs(),
                      const SizedBox(height: 14),
                      if (_tab == WarehouseTab.stock)
                        _stockTab()
                      else if (_tab == WarehouseTab.journal)
                        _journalTab()
                      else if (_tab == WarehouseTab.batches)
                        _batchesTab()
                      else
                        _reportsTab(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTokens.cream,
      appBar: AppBar(
        title: const Text('Склад материалов'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _header() {
    return AppPageHeader(
      eyebrow: 'Производство · склад',
      title: 'Склад',
      subtitle:
          'Номенклатура, партии по FIFO, движение, резервы под заказы и отчёты. '
          'Остаток всегда считается по журналу — его нельзя «потерять» правкой карточки.',
      actions: [
        OutlinedButton.icon(
          key: const Key('warehouse-bulk-materials'),
          onPressed: _busy ? null : _openBulkMaterials,
          icon: const Icon(Icons.calculate_outlined, size: 18),
          label: const Text('Потребность'),
        ),
        OutlinedButton.icon(
          key: const Key('warehouse-sync-price'),
          onPressed: _busy ? null : _syncFromPrice,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Из прайса'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openOrderMaterials,
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Материалы заказа'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _inventory,
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Инвентаризация'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _operate(),
          icon: const Icon(Icons.swap_vert, size: 18),
          label: const Text('Операция'),
        ),
        FilledButton.icon(
          key: const Key('warehouse-add-product'),
          onPressed: _busy ? null : () => _editProduct(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Новый товар'),
        ),
      ],
    );
  }

  Widget _metrics(WarehouseSnapshot snapshot) {
    return AppResponsiveGrid(
      minItemWidth: 190,
      maxColumns: 4,
      children: [
        AppMetricCard(
          label: 'Позиций в работе',
          value: '${snapshot.stocks.where((s) => !s.product.archived).length}',
          hint: '${_snapshot!.stocks.where((s) => s.product.archived).length} в архиве',
          icon: Icons.inventory_2_outlined,
          tone: AppTokens.blue,
        ),
        AppMetricCard(
          label: 'Стоимость склада',
          value: appMoneyShort(snapshot.totalValue),
          hint: 'по средней себестоимости',
          icon: Icons.account_balance_wallet_outlined,
          tone: AppTokens.copper,
        ),
        AppMetricCard(
          label: 'В резерве',
          value: appMoneyShort(snapshot.reservedValue),
          hint: 'закреплено за заказами',
          icon: Icons.lock_outline,
          tone: AppTokens.green,
        ),
        AppMetricCard(
          label: 'Ниже минимума',
          value: '${snapshot.lowCount}',
          hint: snapshot.lowCount == 0 ? 'все позиции в норме' : 'нужно докупить',
          icon: Icons.warning_amber_outlined,
          tone: snapshot.lowCount == 0 ? AppTokens.green : AppTokens.red,
          onTap: () => setState(() {
            _tab = WarehouseTab.stock;
            _onlyLow = true;
          }),
        ),
      ],
    );
  }

  Widget _tabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in WarehouseTab.values) ...[
            _TabButton(
              label: tab.label,
              icon: tab.icon,
              selected: _tab == tab,
              badge: tab == WarehouseTab.stock
                  ? '${_stocks.length}'
                  : tab == WarehouseTab.journal
                  ? '${_snapshot?.moves.length ?? 0}'
                  : tab == WarehouseTab.batches
                  ? '${_snapshot?.stocks.fold<int>(0, (s, e) => s + e.batches.length) ?? 0}'
                  : null,
              onTap: () async {
                setState(() => _tab = tab);
                if (tab == WarehouseTab.reports) await _loadReport();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _stockTab() {
    final stocks = _stocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filters(),
        const SizedBox(height: 12),
        if (stocks.isEmpty)
          AppSurface(
            child: AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Ничего не найдено',
              message: _archived
                  ? 'В архиве нет позиций по этому фильтру.'
                  : 'Добавьте первый товар — плёнку, окантовку, люверсы или фурнитуру. '
                        'Дальше приход, продажа, списание в заказ и история.',
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _editProduct(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить товар'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _syncFromPrice,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Заполнить из прайса'),
                  ),
                ],
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [
                    for (final stock in stocks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _stockCard(stock),
                      ),
                  ],
                );
              }
              return _stockTable(stocks);
            },
          ),
      ],
    );
  }

  Widget _filters() {
    return AppSurface(
      padding: const EdgeInsets.all(12),
      shadow: false,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: AppSearchField(
              hint: 'Название, материал, поставщик, штрихкод',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          _FilterDropdown<String>(
            label: 'Категория',
            value: _category,
            items: [
              const DropdownMenuItem(value: '', child: Text('Все категории')),
              for (final category in _categories)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) => setState(() => _category = value ?? ''),
          ),
          _FilterDropdown<StockUnit?>(
            label: 'Единица',
            value: _unit,
            items: [
              const DropdownMenuItem(value: null, child: Text('Все единицы')),
              for (final unit in StockUnit.values)
                DropdownMenuItem(value: unit, child: Text(unit.label)),
            ],
            onChanged: (value) => setState(() => _unit = value),
          ),
          FilterChip(
            label: const Text('Только низкие'),
            selected: _onlyLow,
            onSelected: (value) => setState(() => _onlyLow = value),
          ),
          FilterChip(
            label: const Text('Архив'),
            selected: _archived,
            onSelected: (value) => setState(() => _archived = value),
          ),
          if (_query.isNotEmpty ||
              _category.isNotEmpty ||
              _unit != null ||
              _onlyLow ||
              _archived)
            TextButton.icon(
              onPressed: () => setState(() {
                _query = '';
                _category = '';
                _unit = null;
                _onlyLow = false;
                _archived = false;
              }),
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Сбросить'),
            ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _stockTable(List<WarehouseStock> stocks) {
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: true,
      child: Column(
        children: [
          const AppTableHeader(
            cells: [
              'Товар',
              'Категория',
              'Остаток',
              'Резерв',
              'Доступно',
              'Закупка / продажа',
              'Место',
              '',
            ],
            flex: [4, 2, 2, 1, 1, 2, 2, 1],
          ),
          for (final stock in stocks) _stockRow(stock),
        ],
      ),
    );
  }

  Widget _stockRow(WarehouseStock stock) {
    final product = stock.product;
    return _HoverRow(
      onTap: () => _details(stock),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _ProductAvatar(product: product, low: stock.isLow),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: product.archived
                              ? AppTokens.faint
                              : AppTokens.ink,
                          decoration: product.archived
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        [
                          if (product.material.isNotEmpty) product.material,
                          if (product.color.isNotEmpty) product.color,
                          if (product.thicknessMm > 0)
                            '${appQty(product.thicknessMm)} мм',
                          if (product.barcode.isNotEmpty) product.barcode,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTokens.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _tableCell(product.category.isEmpty ? '—' : product.category, flex: 2),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  '${appQty(stock.balance)} ${product.unit.shortLabel}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: stock.isOut
                        ? AppTokens.red
                        : stock.isLow
                        ? AppTokens.amber
                        : AppTokens.ink,
                  ),
                ),
                if (stock.isLow) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppTokens.amber,
                  ),
                ],
              ],
            ),
          ),
          _tableCell(appQty(stock.reserved), flex: 1),
          _tableCell(
            appQty(stock.available),
            flex: 1,
            color: stock.available <= 0 ? AppTokens.red : AppTokens.green,
            bold: true,
          ),
          _tableCell(
            '${appMoney(stock.product.purchasePrice)}\n${appMoney(stock.product.salePrice)}',
            flex: 2,
            small: true,
          ),
          _tableCell(product.location.isEmpty ? '—' : product.location, flex: 2),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Действия',
                onSelected: (value) {
                  switch (value) {
                    case 'operate':
                      _operate(initial: stock);
                    case 'edit':
                      _editProduct(product);
                    case 'archive':
                      _archive(product, !product.archived);
                    case 'delete':
                      _delete(product);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'operate',
                    child: Text('Операция'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Редактировать'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      product.archived ? 'Вернуть из архива' : 'В архив',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(
    String text, {
    int flex = 1,
    Color? color,
    bool bold = false,
    bool small = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: small ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: small ? 10.5 : 12,
          height: small ? 1.35 : null,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color ?? AppTokens.inkSoft,
        ),
      ),
    );
  }

  Widget _stockCard(WarehouseStock stock) {
    final product = stock.product;
    return AppSurface(
      padding: const EdgeInsets.all(14),
      onTap: () => _details(stock),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProductAvatar(product: product, low: stock.isLow),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      product.subtitle.isEmpty ? 'Без категории' : product.subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTokens.faint,
                      ),
                    ),
                  ],
                ),
              ),
              if (stock.isLow)
                const AppPill(
                  label: 'докупить',
                  color: AppTokens.amber,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat('Остаток', '${appQty(stock.balance)} ${product.unit.shortLabel}'),
              _miniStat('Резерв', appQty(stock.reserved)),
              _miniStat(
                'Доступно',
                appQty(stock.available),
                color: stock.available <= 0 ? AppTokens.red : AppTokens.green,
              ),
              _miniStat('Средняя', appMoney(stock.averageCost)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${product.location.isEmpty ? 'Место не указано' : product.location}'
                  '${product.supplier.isEmpty ? '' : ' · ${product.supplier}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppTokens.muted),
                ),
              ),
              Text(
                '${appMoney(product.purchasePrice)} / ${appMoney(product.salePrice)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppTokens.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9.5, color: AppTokens.faint),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color ?? AppTokens.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _journalTab() {
    final moves = _snapshot?.moves ?? const <StockMove>[];
    if (moves.isEmpty) {
      return const AppSurface(
        child: AppEmptyState(
          compact: true,
          icon: Icons.receipt_long_outlined,
          title: 'Журнал пуст',
          message: 'Проведите приход или другую операцию — каждая запись '
              'навсегда останется в журнале.',
        ),
      );
    }
    final names = {
      for (final stock in _snapshot?.stocks ?? const <WarehouseStock>[])
        stock.product.id: stock.product,
    };
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          const AppTableHeader(
            cells: [
              'Дата',
              'Операция',
              'Товар',
              'Кол-во',
              'Цена',
              'Сумма',
              'Заказ',
              'Примечание',
            ],
            flex: [2, 2, 3, 1, 1, 1, 2, 3],
          ),
          for (final move in moves.take(200))
            _journalRow(move, names[move.productId]),
        ],
      ),
    );
  }

  Widget _journalRow(StockMove move, WarehouseProduct? product) {
    final isIncome = move.direction > 0;
    return _HoverRow(
      child: Row(
        children: [
          _tableCell(appDateTime(move.at), flex: 2, small: true),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppPill(
                label: move.type.label,
                color: isIncome ? AppTokens.green : AppTokens.copper,
                dense: true,
                icon: isIncome ? Icons.south_west : Icons.north_east,
              ),
            ),
          ),
          _tableCell(
            product?.name ?? 'Товар удалён',
            flex: 3,
            bold: true,
          ),
          _tableCell(
            '${isIncome ? '+' : '−'}${appQty(move.quantity)} '
            '${product?.unit.shortLabel ?? ''}',
            flex: 1,
            color: isIncome ? AppTokens.green : AppTokens.red,
            bold: true,
          ),
          _tableCell(appMoney(move.unitPrice), flex: 1, small: true),
          _tableCell(appMoney(move.priceAmount), flex: 1, small: true),
          _tableCell(move.orderId.isEmpty ? '—' : move.orderId, flex: 2, small: true),
          _tableCell(move.note.isEmpty ? '—' : move.note, flex: 3, small: true),
        ],
      ),
    );
  }

  Widget _batchesTab() {
    final rows = <(WarehouseStock, StockBatch)>[];
    for (final stock in _snapshot?.stocks ?? const <WarehouseStock>[]) {
      for (final batch in stock.batches) {
        rows.add((stock, batch));
      }
    }
    rows.sort((a, b) => b.$2.receivedAt.compareTo(a.$2.receivedAt));
    if (rows.isEmpty) {
      return const AppSurface(
        child: AppEmptyState(
          compact: true,
          icon: Icons.layers_outlined,
          title: 'Партий пока нет',
          message: 'Партия создаётся автоматически при приходе, закупке, '
              'возврате и инвентаризации. Списание идёт по FIFO.',
        ),
      );
    }
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          const AppTableHeader(
            cells: [
              'Партия',
              'Товар',
              'Приход',
              'Кол-во',
              'Остаток',
              'Себестоимость',
              'Стоимость',
              'Поставщик',
            ],
            flex: [2, 3, 2, 1, 1, 2, 2, 2],
          ),
          for (final row in rows)
            _HoverRow(
              child: Row(
                children: [
                  _tableCell(row.$2.id, flex: 2, small: true),
                  _tableCell(row.$1.product.name, flex: 3, bold: true),
                  _tableCell(appDate(row.$2.receivedAt), flex: 2, small: true),
                  _tableCell(
                    '${appQty(row.$2.quantity)} ${row.$1.product.unit.shortLabel}',
                    flex: 1,
                  ),
                  _tableCell(
                    appQty(row.$2.remaining),
                    flex: 1,
                    bold: true,
                    color: row.$2.remaining <= 0
                        ? AppTokens.faint
                        : AppTokens.green,
                  ),
                  _tableCell(appMoney(row.$2.unitCost), flex: 2, small: true),
                  _tableCell(appMoney(row.$2.value), flex: 2, small: true),
                  _tableCell(
                    row.$2.supplier.isEmpty ? '—' : row.$2.supplier,
                    flex: 2,
                    small: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSurface(
          padding: const EdgeInsets.all(12),
          shadow: false,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final kind in WarehouseReportKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _reportKind == kind,
                  onSelected: (_) async {
                    setState(() => _reportKind = kind);
                    await _loadReport();
                  },
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: _reportFrom == null || _reportTo == null
                        ? null
                        : DateTimeRange(
                            start: _reportFrom!,
                            end: _reportTo!,
                          ),
                  );
                  if (range == null) return;
                  setState(() {
                    _reportFrom = range.start;
                    _reportTo = range.end;
                  });
                  await _loadReport();
                },
                icon: const Icon(Icons.date_range, size: 17),
                label: Text(
                  _reportFrom == null
                      ? 'Период: всё время'
                      : '${appDate(_reportFrom)} — ${appDate(_reportTo)}',
                ),
              ),
              if (_reportFrom != null)
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _reportFrom = null;
                      _reportTo = null;
                    });
                    await _loadReport();
                  },
                  child: const Text('Сбросить период'),
                ),
              IconButton(
                tooltip: 'Обновить отчёт',
                onPressed: _loadReport,
                icon: const Icon(Icons.refresh),
              ),
              OutlinedButton.icon(
                onPressed: _report == null ? null : _exportReport,
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('CSV'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_report == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          AppSurface(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTokens.gapM),
                  child: AppSectionTitle(
                    title: _report!.title,
                    subtitle: _report!.note,
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final entry in _report!.totals.entries)
                          AppPill(
                            label: '${entry.key}: ${entry.value}',
                            color: AppTokens.inkSoft,
                            dense: true,
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (_report!.rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'За выбранный период данных нет.',
                      style: TextStyle(color: AppTokens.muted),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 720),
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width < 1000
                            ? 1000
                            : null,
                        child: Column(
                          children: [
                            AppTableHeader(cells: _report!.columns),
                            for (final row in _report!.rows)
                              _HoverRow(
                                child: Row(
                                  children: [
                                    for (final cell in row)
                                      Expanded(
                                        child: Text(
                                          cell,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppTokens.inkSoft,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.paper : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTokens.line : Colors.transparent,
            ),
            boxShadow: selected ? AppTokens.shadowSoft : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppTokens.copper : AppTokens.faint,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTokens.ink : AppTokens.muted,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? AppTokens.copperSoft : AppTokens.graphiteSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppTokens.copper : AppTokens.faint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _ProductAvatar extends StatelessWidget {
  const _ProductAvatar({required this.product, required this.low});

  final WarehouseProduct product;
  final bool low;

  @override
  Widget build(BuildContext context) {
    final icon = switch (product.category.toLowerCase()) {
      final value when value.contains('полотно') => Icons.blinds,
      final value when value.contains('окант') => Icons.line_weight,
      final value when value.contains('люверс') => Icons.circle_outlined,
      final value when value.contains('фурнитур') => Icons.handyman_outlined,
      _ => Icons.inventory_2_outlined,
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: low ? AppTokens.amberSoft : AppTokens.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 18,
        color: low ? AppTokens.amber : AppTokens.copper,
      ),
    );
  }
}

/// Строка таблицы с подсветкой при наведении.
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? const Color(0xFFFAF5ED) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gapM,
              vertical: 11,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsDialog extends StatefulWidget {
  const _ProductDetailsDialog({
    required this.stock,
    required this.onEdit,
    required this.onOperate,
    required this.onArchive,
  });

  final WarehouseStock stock;
  final VoidCallback onEdit;
  final VoidCallback onOperate;
  final VoidCallback onArchive;

  @override
  State<_ProductDetailsDialog> createState() => _ProductDetailsDialogState();
}

class _ProductDetailsDialogState extends State<_ProductDetailsDialog> {
  final _warehouse = WarehouseRepository.instance;
  List<StockMove> _moves = const [];
  List<PricePoint> _prices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final moves = await _warehouse.moves(
      productId: widget.stock.product.id,
      limit: 100,
    );
    final prices = await _warehouse.priceHistory(widget.stock.product.id);
    if (!mounted) return;
    setState(() {
      _moves = moves;
      _prices = prices;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.stock.product;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 32,
        vertical: narrow ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  _ProductAvatar(product: product, low: widget.stock.isLow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          '${product.subtitle.isEmpty ? 'Без категории' : product.subtitle}'
                          '${product.barcode.isEmpty ? '' : ' · ${product.barcode}'}',
                          style: const TextStyle(
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppResponsiveGrid(
                      minItemWidth: 140,
                      maxColumns: 4,
                      children: [
                        AppMetricCard(
                          label: 'Остаток',
                          value:
                              '${appQty(widget.stock.balance)} ${product.unit.shortLabel}',
                          icon: Icons.inventory_outlined,
                          tone: AppTokens.blue,
                        ),
                        AppMetricCard(
                          label: 'Резерв',
                          value: appQty(widget.stock.reserved),
                          icon: Icons.lock_outline,
                          tone: AppTokens.copper,
                        ),
                        AppMetricCard(
                          label: 'Доступно',
                          value: appQty(widget.stock.available),
                          icon: Icons.check_circle_outline,
                          tone: widget.stock.available <= 0
                              ? AppTokens.red
                              : AppTokens.green,
                        ),
                        AppMetricCard(
                          label: 'Средняя себестоимость',
                          value: appMoney(widget.stock.averageCost),
                          icon: Icons.calculate_outlined,
                          tone: AppTokens.inkSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _facts(product),
                    const SizedBox(height: 16),
                    const AppSectionTitle(
                      title: 'Партии по FIFO',
                      subtitle: 'Списание всегда идёт с самой ранней партии',
                    ),
                    const SizedBox(height: 8),
                    if (widget.stock.batches.isEmpty)
                      const Text(
                        'Партий нет.',
                        style: TextStyle(fontSize: 12, color: AppTokens.muted),
                      )
                    else
                      AppSurface(
                        padding: EdgeInsets.zero,
                        shadow: false,
                        clip: true,
                        child: Column(
                          children: [
                            const AppTableHeader(
                              cells: [
                                'Приход',
                                'Кол-во',
                                'Остаток',
                                'Себест.',
                                'Стоимость',
                              ],
                            ),
                            for (final batch in widget.stock.batches)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.gapM,
                                  vertical: 9,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppTokens.lineSoft,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(appDate(batch.receivedAt))),
                                    Expanded(child: Text(appQty(batch.quantity))),
                                    Expanded(
                                      child: Text(
                                        appQty(batch.remaining),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: batch.remaining <= 0
                                              ? AppTokens.faint
                                              : AppTokens.green,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Text(appMoney(batch.unitCost))),
                                    Expanded(child: Text(appMoney(batch.value))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    const AppSectionTitle(
                      title: 'История цен',
                      subtitle: 'Закупочные и продажные цены меняются отдельно',
                    ),
                    const SizedBox(height: 8),
                    if (_prices.isEmpty)
                      const Text(
                        'История цен появится после изменения карточки или операции.',
                        style: TextStyle(fontSize: 12, color: AppTokens.muted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final point in _prices.take(12))
                            AppPill(
                              label:
                                  '${point.isPurchase ? 'закупка' : 'продажа'} '
                                  '${appMoney(point.price)} · ${appDate(point.at)}',
                              color: point.isPurchase
                                  ? AppTokens.blue
                                  : AppTokens.green,
                              dense: true,
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    const AppSectionTitle(
                      title: 'Последние движения',
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_moves.isEmpty)
                      const Text(
                        'Движений пока нет.',
                        style: TextStyle(fontSize: 12, color: AppTokens.muted),
                      )
                    else
                      for (final move in _moves.take(20))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              AppPill(
                                label: move.type.label,
                                color: move.direction > 0
                                    ? AppTokens.green
                                    : AppTokens.copper,
                                dense: true,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${move.direction > 0 ? '+' : '−'}${appQty(move.quantity)} '
                                  '${product.unit.label} · ${appDateTime(move.at)}'
                                  '${move.note.isEmpty ? '' : ' · ${move.note}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTokens.inkSoft,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onArchive();
                    },
                    icon: Icon(
                      product.archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      size: 17,
                    ),
                    label: Text(product.archived ? 'Из архива' : 'В архив'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onEdit();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Редактировать'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOperate();
                    },
                    icon: const Icon(Icons.swap_vert, size: 17),
                    label: const Text('Операция'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _facts(WarehouseProduct product) {
    final facts = <(String, String)>[
      ('Категория', product.category.isEmpty ? '—' : product.category),
      ('Материал', product.material.isEmpty ? '—' : product.material),
      ('Цвет', product.color.isEmpty ? '—' : product.color),
      ('Толщина', product.thicknessMm <= 0 ? '—' : '${appQty(product.thicknessMm)} мм'),
      ('Размер', product.dimensionsLabel),
      ('Вес', product.weightKg <= 0 ? '—' : '${appQty(product.weightKg)} кг'),
      ('Мин. остаток', appQty(product.minQuantity)),
      ('Единица', product.unit.label),
      ('Закупка', appMoney(product.purchasePrice)),
      ('Продажа', appMoney(product.salePrice)),
      ('Наценка', '${appQty(product.markupPercent)} %'),
      ('Поставщик', product.supplier.isEmpty ? '—' : product.supplier),
      ('Место', product.location.isEmpty ? '—' : product.location),
      ('Штрихкод', product.barcode.isEmpty ? '—' : product.barcode),
    ];
    return AppSurface(
      padding: const EdgeInsets.all(14),
      shadow: false,
      child: Wrap(
        spacing: 26,
        runSpacing: 12,
        children: [
          for (final fact in facts)
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fact.$1,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTokens.faint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fact.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
