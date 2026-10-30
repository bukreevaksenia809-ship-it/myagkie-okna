import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/order_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../models/order_record.dart';
import '../../models/price_list.dart';
import '../../models/warehouse.dart';
import '../../services/bulk_materials.dart';
import '../../services/order_materials.dart';
import '../../services/file_saver.dart';
import '../design/app_kit.dart';

/// Потребность в материалах сразу по нескольким заказам.
///
/// Заказы могут быть от разных клиентов и с разными датами: выбираем нужные,
/// считаем суммарную потребность по сметам и раскрою, показываем остаток,
/// дефицит и список «докупить».
Future<void> showBulkMaterialsDialog(
  BuildContext context, {
  required List<OrderRecord> orders,
  Set<String>? initialSelected,
  PriceList prices = const PriceList.defaults(),
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _BulkMaterialsDialog(
      orders: orders,
      initialSelected: initialSelected,
      prices: prices,
    ),
  );
}

class _BulkMaterialsDialog extends StatefulWidget {
  const _BulkMaterialsDialog({
    required this.orders,
    required this.prices,
    this.initialSelected,
  });

  final List<OrderRecord> orders;
  final Set<String>? initialSelected;
  final PriceList prices;

  @override
  State<_BulkMaterialsDialog> createState() => _BulkMaterialsDialogState();
}

class _BulkMaterialsDialogState extends State<_BulkMaterialsDialog> {
  final _repo = OrderRepository.instance;
  final _warehouse = WarehouseRepository.instance;
  final _search = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';
  DateTime? _from;
  DateTime? _to;
  bool _busy = false;
  bool _calculated = false;
  List<_BulkNeed> _needs = const [];
  List<String> _unmatched = const [];
  int _windowCount = 0;
  double _amount = 0;

  @override
  void initState() {
    super.initState();
    _selected.addAll(
      widget.initialSelected ??
          widget.orders.where((order) => !order.archived).map((o) => o.id),
    );
    _calculate();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OrderRecord> get _visible {
    final query = _query.trim().toLowerCase();
    return widget.orders.where((order) {
      if (order.archived) return false;
      if (query.isNotEmpty) {
        final haystack =
            '${order.number} ${order.title} ${order.customer} ${order.address}'
                .toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      final created = order.createdAt;
      if (_from != null && created != null && created.isBefore(_from!)) {
        return false;
      }
      if (_to != null &&
          created != null &&
          created.isAfter(_to!.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _calculate() async {
    if (_selected.isEmpty) {
      setState(() {
        _needs = const [];
        _unmatched = const [];
        _windowCount = 0;
        _amount = 0;
        _calculated = true;
      });
      return;
    }
    setState(() => _busy = true);
    final chosen = widget.orders
        .where((order) => _selected.contains(order.id))
        .toList();
    final result = await BulkMaterialsCalculator(
      orders: _repo,
      warehouse: _warehouse,
    ).calculate(chosen, prices: widget.prices);
    if (!mounted) return;
    setState(() {
      _needs = [
        for (final line in result.lines)
          _BulkNeed(
            need: OrderMaterialNeed(
              productId: line.productId,
              name: line.name,
              unit: line.unit,
              quantity: line.quantity,
              available: line.available,
              reserved: line.reserved,
              source: line.source,
            ),
            orders: line.orders,
          ),
      ];
      _unmatched = result.unmatched;
      _windowCount = result.windowCount;
      _amount = result.amount;
      _busy = false;
      _calculated = true;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _issueSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Списать материалы?'),
        content: Text(
          'Будет обработано заказов: ${_selected.length}. Для каждого заказа '
          'сначала создаётся резерв, затем материалы списываются со склада. '
          'Если материалов не хватает, заказ останется без списания — '
          'в отчёте будет дефицит.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Списать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final chosen = widget.orders
        .where((order) => _selected.contains(order.id))
        .toList();
    final messages = <String>[];
    var issued = 0;
    for (final order in chosen) {
      final plan = await OrderMaterialsService().plan(
        _repo.projectOf(order),
        prices: widget.prices,
      );
      final reserved = await _warehouse.reserveOrder(order.id, plan.needs);
      if (!reserved.ok) {
        messages.add('${order.number}: ${reserved.message}');
        if (reserved.shortages.isNotEmpty) {
          messages.addAll(reserved.shortages.take(3));
        }
        continue;
      }
      final result = await _warehouse.issueOrder(order.id);
      if (result.ok) {
        issued++;
      } else {
        messages.add('${order.number}: ${result.message}');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _calculate();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          issued == chosen.length
              ? 'Списано по ${chosen.length} заказам'
              : 'Списано: $issued из ${chosen.length}',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Text(
              messages.isEmpty
                  ? 'Все материалы списаны по FIFO. Остатки обновлены.'
                  : messages.join('\n'),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer();
    buffer.writeln('Потребность в материалах');
    buffer.writeln('Заказов;${_selected.length};Окон;$_windowCount');
    buffer.writeln('Товар;Единица;Нужно;Доступно;Дефицит');
    for (final item in _needs) {
      buffer.writeln(
        '${_csv(item.need.name)};${item.need.unit.label};'
        '${appQty(item.need.quantity)};${appQty(item.need.available)};'
        '${appQty(item.need.shortage)}',
      );
    }
    if (_unmatched.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Не сопоставлено');
      for (final line in _unmatched) {
        buffer.writeln(_csv(line));
      }
    }
    final saved = await saveBytes(
      Uint8List.fromList(utf8.encode('\uFEFF$buffer')),
      'Потребность-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV сохранён: ${saved.destination}')),
    );
  }

  String _csv(String value) =>
      value.contains(';') ? '"${value.replaceAll('"', '""')}"' : value;

  int get _shortageCount =>
      _needs.where((item) => item.need.shortage > 0).length;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 1000;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 8 : 28,
        vertical: narrow ? 8 : 20,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTokens.blueSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.calculate_outlined,
                        color: AppTokens.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Потребность по заказам',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Выберите заказы от разных клиентов и дат — '
                            'программа сложит материалы по сметам и раскрою.',
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
              Expanded(
                child: narrow
                    ? Column(
                        children: [
                          _ordersPanel(height: 176),
                          const Divider(height: 1),
                          Expanded(child: _resultPanel()),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 390, child: _ordersPanel()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _resultPanel()),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final info = Text(
                      'Выбрано заказов: ${_selected.length} · окон: $_windowCount',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTokens.muted,
                      ),
                    );
                    final issue = FilledButton.tonalIcon(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : _issueSelected,
                      icon: const Icon(Icons.inventory_2_outlined, size: 17),
                      label: const Text('Списать в заказы'),
                    );
                    final csv = OutlinedButton.icon(
                      onPressed: _selected.isEmpty ? null : _exportCsv,
                      icon: const Icon(Icons.download_outlined, size: 17),
                      label: const Text('CSV'),
                    );
                    final calculate = FilledButton.icon(
                      onPressed: _busy ? null : _calculate,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 17),
                      label: const Text('Рассчитать'),
                    );
                    final close = TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Закрыть'),
                    );
                    if (constraints.maxWidth < 700) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [issue, csv, calculate, close],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        info,
                        const Spacer(),
                        issue,
                        const SizedBox(width: 8),
                        csv,
                        const SizedBox(width: 8),
                        calculate,
                        const SizedBox(width: 8),
                        close,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ordersPanel({double? height}) {
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Заказы',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (visible.every((o) => _selected.contains(o.id))) {
                    _selected.removeAll(visible.map((o) => o.id));
                  } else {
                    _selected.addAll(visible.map((o) => o.id));
                  }
                }),
                child: const Text(
                  'Все / снять',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Клиент, номер, адрес',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _dateChip('Всё время', null, null),
              _dateChip(
                'Этот месяц',
                DateTime(DateTime.now().year, DateTime.now().month),
                null,
              ),
              _dateChip(
                'Прошлый месяц',
                DateTime(DateTime.now().year, DateTime.now().month - 1),
                DateTime(DateTime.now().year, DateTime.now().month, 0),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (height != null)
            SizedBox(height: height, child: _orderList(visible))
          else
            Expanded(child: _orderList(visible)),
        ],
      ),
    );
  }

  Widget _orderList(List<OrderRecord> visible) {
    if (visible.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Нет заказов по фильтру.',
            style: TextStyle(fontSize: 12, color: AppTokens.muted),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final order = visible[index];
        final selected = _selected.contains(order.id);
        return CheckboxListTile(
          value: selected,
          onChanged: (_) => _toggle(order.id),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            '${order.number} · ${order.displayTitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            '${order.customer.isEmpty ? 'без клиента' : order.customer}'
            '${order.deadline == null ? '' : ' · срок ${appDate(order.deadline)}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        );
      },
    );
  }

  Widget _dateChip(String label, DateTime? from, DateTime? to) {
    final active = _from == from && _to == to;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10.5)),
      selected: active,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() {
        _from = from;
        _to = to;
      }),
    );
  }

  Widget _resultPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppResponsiveGrid(
            minItemWidth: 135,
            maxColumns: 4,
            children: [
              AppMetricCard(
                label: 'Заказов',
                value: '${_selected.length}',
                icon: Icons.work_outline,
                tone: AppTokens.blue,
              ),
              AppMetricCard(
                label: 'Окон',
                value: '$_windowCount',
                icon: Icons.window_outlined,
                tone: AppTokens.inkSoft,
              ),
              AppMetricCard(
                label: 'Позиций',
                value: '${_needs.length}',
                icon: Icons.inventory_2_outlined,
                tone: AppTokens.copper,
              ),
              AppMetricCard(
                label: 'Дефицит',
                value: '$_shortageCount',
                icon: Icons.warning_amber_outlined,
                tone: _shortageCount == 0 ? AppTokens.green : AppTokens.red,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_calculated)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_needs.isEmpty)
            const Expanded(
              child: AppEmptyState(
                compact: true,
                icon: Icons.inventory_2_outlined,
                title: 'Нечего считать',
                message:
                    'Выберите заказы слева. Если в сметах нет материалов, '
                    'проверьте номенклатуру и прайс.',
              ),
            )
          else
            Expanded(
              child: AppSurface(
                padding: EdgeInsets.zero,
                clip: true,
                shadow: false,
                child: Column(
                  children: [
                    const AppTableHeader(
                      cells: ['Товар', 'Ед.', 'Нужно', 'Доступно', 'Дефицит'],
                      flex: [4, 1, 1, 1, 1],
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final item in _needs)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: AppTokens.lineSoft),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.need.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (item.need.source.isNotEmpty)
                                          Text(
                                            item.need.source,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              color: AppTokens.faint,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.need.unit.label,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      appQty(item.need.quantity),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      appQty(item.need.available),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: item.need.available <= 0
                                            ? AppTokens.red
                                            : AppTokens.green,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.need.shortage <= 0
                                          ? '—'
                                          : appQty(item.need.shortage),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: item.need.shortage <= 0
                                            ? AppTokens.green
                                            : AppTokens.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_unmatched.isNotEmpty) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Не сопоставлено со складом',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTokens.amber,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final line in _unmatched)
                                    Text(
                                      '• $line',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        height: 1.45,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Сумма по сметам: ${appMoney(_amount)} · остатки проверяются '
            'по свободному количеству с учётом резервов.',
            style: const TextStyle(fontSize: 10.5, color: AppTokens.faint),
          ),
        ],
      ),
    );
  }
}

class _BulkNeed {
  const _BulkNeed({required this.need, required this.orders});

  final OrderMaterialNeed need;
  final int orders;
}
