import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/finance_repository.dart';
import '../data/order_repository.dart';
import '../models/finance.dart';
import '../models/order_project.dart';
import '../models/order_record.dart';
import '../models/order_json.dart';
import '../services/cost_catalog.dart';
import '../services/estimate.dart';
import '../services/file_saver.dart';
import 'design/app_kit.dart';
import 'orders/finance_dialogs.dart';

enum _FinancePeriod {
  month('Этот месяц'),
  previousMonth('Прошлый месяц'),
  quarter('Квартал'),
  year('Год'),
  all('Всё время');

  const _FinancePeriod(this.label);

  final String label;

  (DateTime?, DateTime?) get range {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return switch (this) {
      _FinancePeriod.month => (DateTime(now.year, now.month), end),
      _FinancePeriod.previousMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0, 23, 59, 59, 999),
      ),
      _FinancePeriod.quarter => (DateTime(now.year, now.month - 2), end),
      _FinancePeriod.year => (DateTime(now.year), end),
      _FinancePeriod.all => (null, null),
    };
  }
}

/// Финансы производства: долги, касса, расходы и маржа.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    this.embedded = false,
    this.onOpenOrder,
    this.onOpenOrders,
    this.prices = const PriceList.defaults(),
  });

  final bool embedded;
  final Future<void> Function(OrderRecord)? onOpenOrder;
  final VoidCallback? onOpenOrders;
  final PriceList prices;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final _repo = FinanceRepository.instance;
  final _orders = OrderRepository.instance;
  _FinancePeriod _period = _FinancePeriod.month;
  FinanceSummary? _summary;
  List<(OrderRecord, OrderFinance)> _debtors = const [];
  List<CashEntry> _cash = const [];
  List<(OrderRecord, OrderFinance)> _orderFinances = const [];
  List<OrderRecord> _allOrders = const [];
  Map<String, double> _catalogCosts = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _period.range;
      final results = await Future.wait<Object>([
        _repo.summary(from: from, to: to),
        _repo.debtors(),
        _repo.cashEntries(from: from, to: to),
        _orders.list(includeArchived: false),
        _repo.orderFinances(),
      ]);
      final catalog = await CostCatalog.instance.load();
      final costs = <String, double>{};
      for (final order in results[3] as List<OrderRecord>) {
        try {
          final project = orderFromJson(
            (jsonDecode(order.projectJson) as Map).cast<String, dynamic>(),
          );
          costs[order.id] = catalog.orderCost(
            Estimate.of(project, widget.prices),
          );
        } catch (_) {
          costs[order.id] = 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _summary = results[0] as FinanceSummary;
        _catalogCosts = costs;
        _debtors = results[1] as List<(OrderRecord, OrderFinance)>;
        _cash = results[2] as List<CashEntry>;
        _allOrders = results[3] as List<OrderRecord>;
        _orderFinances = results[4] as List<(OrderRecord, OrderFinance)>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось прочитать финансы: $error';
      });
    }
  }

  Future<OrderRecord?> _pickOrder({bool onlyDebtors = false}) async {
    final orders = onlyDebtors
        ? [for (final item in _debtors) item.$1]
        : _allOrders
              .where((order) => order.status != OrderStatus.cancelled)
              .toList();
    if (orders.isEmpty) return null;
    var query = '';
    final selected = await showDialog<OrderRecord>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final visible = orders.where((order) {
            final text =
                '${order.number} ${order.displayTitle} ${order.customer}'
                    .toLowerCase();
            return text.contains(query.trim().toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Выберите заказ'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Номер, клиент или название',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setLocal(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final order = visible[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${order.number} · ${order.displayTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${order.customer.isEmpty ? 'без клиента' : order.customer}'
                            ' · ${appMoneyShort(order.amount)}',
                          ),
                          onTap: () => Navigator.of(context).pop(order),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ],
          );
        },
      ),
    );
    return selected;
  }

  Future<void> _addPayment({OrderRecord? order}) async {
    final target = order ?? await _pickOrder();
    if (target == null || !mounted) return;
    final finance = await _repo.orderFinance(target);
    if (!mounted) return;
    final changed = await showOrderPaymentDialog(
      context,
      order: target,
      finance: finance,
      author: target.assignee,
    );
    if (changed) await _load();
  }

  Future<void> _addExpense({OrderRecord? order}) async {
    final target = order ?? await _pickOrder();
    if (target == null || !mounted) return;
    final changed = await showOrderExpenseDialog(
      context,
      order: target,
      author: target.assignee,
    );
    if (changed) await _load();
  }

  Future<void> _exportCsv() async {
    final summary = _summary;
    if (summary == null) return;
    final buffer = StringBuffer();
    buffer.writeln('Финансы · ${_period.label}');
    buffer.writeln('Выручка;${_plain(summary.revenue)}');
    buffer.writeln('Получено;${_plain(summary.received)}');
    buffer.writeln('Долги;${_plain(summary.debt)}');
    buffer.writeln(
      'Расходы;${_plain(summary.materialCost + summary.expenses)}',
    );
    buffer.writeln('Прибыль;${_plain(summary.profit)}');
    buffer.writeln();
    buffer.writeln('Дата;Заказ;Тип;Статья;Сумма;Приход/расход');
    for (final entry in _cash) {
      buffer.writeln(
        '${appDate(entry.at)};${entry.orderNumber};'
        '${entry.isIncome ? 'Оплата' : 'Расход'};${entry.label};'
        '${_plain(entry.amount)};${entry.isIncome ? '+' : '−'}',
      );
    }
    final saved = await saveBytes(
      Uint8List.fromList(utf8.encode('\uFEFF$buffer')),
      'Финансы-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV сохранён: ${saved.destination}')),
    );
  }

  String _plain(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _header(),
          const SizedBox(height: 16),
          if (_error != null) ...[
            AppBanner(
              title: 'Ошибка финансов',
              message: _error!,
              tone: AppTokens.red,
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 12),
          ],
          _filters(),
          const SizedBox(height: 14),
          if (_summary == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _metrics(_summary!),
            const SizedBox(height: 16),
            _debtsSection(),
            const SizedBox(height: 16),
            _marginSection(),
            const SizedBox(height: 16),
            _cashSection(),
            const SizedBox(height: 16),
            _costsSection(_summary!),
            const SizedBox(height: 16),
            _catalogCostSection(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTokens.cream,
      appBar: AppBar(title: const Text('Финансы')),
      body: body,
    );
  }

  Widget _header() {
    return AppPageHeader(
      eyebrow: 'Производство · деньги',
      title: 'Финансы',
      subtitle:
          'Оплаты, долги, себестоимость и маржа по заказам. Материалы со '
          'склада считаются по FIFO автоматически.',
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _addExpense(),
          icon: const Icon(Icons.add_card, size: 18),
          label: const Text('Расход'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _exportCsv,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('CSV'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : () => _addPayment(),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Оплата'),
        ),
      ],
    );
  }

  Widget _filters() {
    return AppSurface(
      padding: const EdgeInsets.all(12),
      shadow: false,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final period in _FinancePeriod.values)
            ChoiceChip(
              label: Text(period.label),
              selected: _period == period,
              onSelected: (_) {
                setState(() => _period = period);
                _load();
              },
            ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _metrics(FinanceSummary summary) {
    final marginTone = summary.profit >= 0 ? AppTokens.green : AppTokens.red;
    return AppResponsiveGrid(
      minItemWidth: 160,
      maxColumns: 5,
      children: [
        AppMetricCard(
          label: 'Выручка',
          value: appMoneyShort(summary.revenue),
          hint: '${summary.ordersCount} заказов',
          icon: Icons.receipt_long_outlined,
          tone: AppTokens.inkSoft,
        ),
        AppMetricCard(
          label: 'Получено',
          value: appMoneyShort(summary.received),
          hint: 'за период',
          icon: Icons.payments_outlined,
          tone: AppTokens.green,
        ),
        AppMetricCard(
          label: 'Долги',
          value: appMoneyShort(summary.debt),
          hint: '${summary.debtorsCount} заказов',
          icon: Icons.account_balance_wallet_outlined,
          tone: summary.debt > 0 ? AppTokens.red : AppTokens.green,
        ),
        AppMetricCard(
          label: 'Расходы',
          value: appMoneyShort(summary.materialCost + summary.expenses),
          hint: 'материалы + работы',
          icon: Icons.inventory_2_outlined,
          tone: AppTokens.copper,
        ),
        AppMetricCard(
          label: 'Прибыль',
          value: appMoneyShort(summary.profit),
          hint: summary.marginPercent == null
              ? null
              : '${summary.marginPercent!.toStringAsFixed(1)}% маржи',
          icon: Icons.trending_up,
          tone: marginTone,
        ),
      ],
    );
  }

  Widget _debtsSection() {
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Row(
              children: [
                const Expanded(
                  child: AppSectionTitle(
                    title: 'Долги по заказам',
                    subtitle: 'Все неоплаченные заказы, независимо от периода',
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenOrders,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Все заказы'),
                ),
              ],
            ),
          ),
          if (_debtors.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Долгов нет — все заказы оплачены.',
                  style: TextStyle(fontSize: 12, color: AppTokens.green),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  return Column(
                    children: [
                      for (final item in _debtors.take(30))
                        _debtCard(item.$1, item.$2),
                    ],
                  );
                }
                return Column(
                  children: [
                    const AppTableHeader(
                      cells: [
                        'Заказ',
                        'Клиент',
                        'Сумма',
                        'Оплачено',
                        'Долг',
                        '',
                      ],
                      flex: [2, 3, 2, 2, 2, 1],
                    ),
                    for (final item in _debtors.take(30))
                      _debtRow(item.$1, item.$2),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _debtRow(OrderRecord order, OrderFinance finance) {
    return InkWell(
      onTap: widget.onOpenOrder == null
          ? null
          : () async {
              await widget.onOpenOrder!(order);
              if (mounted) await _load();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                order.number.isEmpty ? order.displayTitle : order.number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                order.customer.isEmpty ? order.displayTitle : order.customer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(flex: 2, child: Text(appMoney(order.amount))),
            Expanded(flex: 2, child: Text(appMoney(finance.paid))),
            Expanded(
              flex: 2,
              child: Text(
                appMoney(finance.due),
                style: const TextStyle(
                  color: AppTokens.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Оплатить',
              onPressed: () => _addPayment(order: order),
              icon: const Icon(Icons.add_card, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marginSection() {
    final (from, to) = _period.range;
    final rows = [
      for (final row in _orderFinances)
        if (_inPeriod(row.$1.createdAt, from, to)) row,
    ]..sort((a, b) => a.$2.margin.compareTo(b.$2.margin));
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: AppSectionTitle(
              title: 'Маржа по заказам',
              subtitle: 'За выбранный период, сначала с самой низкой маржой',
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Нет заказов для расчёта.',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  return Column(
                    children: [
                      for (final row in rows.take(30))
                        _marginCard(row.$1, row.$2),
                    ],
                  );
                }
                return Column(
                  children: [
                    const AppTableHeader(
                      cells: ['Заказ', 'Сумма', 'Расходы', 'Маржа', 'Долг'],
                      flex: [3, 2, 2, 2, 2],
                    ),
                    for (final row in rows.take(30)) _marginRow(row.$1, row.$2),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  bool _inPeriod(DateTime? at, DateTime? from, DateTime? to) {
    if (at == null) return from == null && to == null;
    if (from != null && at.isBefore(from)) return false;
    if (to != null && at.isAfter(to)) return false;
    return true;
  }

  Widget _marginRow(OrderRecord order, OrderFinance finance) {
    return InkWell(
      onTap: widget.onOpenOrder == null
          ? null
          : () async {
              await widget.onOpenOrder!(order);
              if (mounted) await _load();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${order.number} · ${order.customer.isEmpty ? order.displayTitle : order.customer}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(flex: 2, child: Text(appMoney(order.amount))),
            Expanded(flex: 2, child: Text(appMoney(finance.totalCost))),
            Expanded(
              flex: 2,
              child: Text(
                appMoney(finance.margin),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: finance.margin >= 0 ? AppTokens.green : AppTokens.red,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                appMoney(finance.due),
                style: TextStyle(
                  color: finance.due > 0 ? AppTokens.red : AppTokens.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marginCard(OrderRecord order, OrderFinance finance) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${order.number} · ${order.customer.isEmpty ? order.displayTitle : order.customer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                'Сумма ${appMoney(order.amount)}',
                style: const TextStyle(fontSize: 10.5),
              ),
              Text(
                'Расходы ${appMoney(finance.totalCost)}',
                style: const TextStyle(fontSize: 10.5),
              ),
              Text(
                'Маржа ${appMoney(finance.margin)}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: finance.margin >= 0 ? AppTokens.green : AppTokens.red,
                ),
              ),
              Text(
                'Долг ${appMoney(finance.due)}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: finance.due > 0 ? AppTokens.red : AppTokens.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debtCard(OrderRecord order, OrderFinance finance) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.number} · ${order.customer.isEmpty ? order.displayTitle : order.customer}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Сумма ${appMoney(order.amount)} · оплачено '
                  '${appMoney(finance.paid)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTokens.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Долг ${appMoneyShort(finance.due)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.red,
                ),
              ),
              TextButton(
                onPressed: () => _addPayment(order: order),
                child: const Text('Оплатить', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cashSection() {
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: AppSectionTitle(
              title: 'Движение денег',
              subtitle: 'Оплаты клиентов и расходы за выбранный период',
            ),
          ),
          if (_cash.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'За период движений нет.',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted),
                ),
              ),
            )
          else
            for (final entry in _cash.take(80))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.isIncome ? Icons.south_west : Icons.north_east,
                      size: 17,
                      color: entry.isIncome ? AppTokens.green : AppTokens.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.label} · ${entry.orderNumber}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              appDate(entry.at),
                              if (entry.note.isNotEmpty) entry.note,
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
                    Text(
                      '${entry.isIncome ? '+' : '−'}${appMoney(entry.amount)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: entry.isIncome ? AppTokens.green : AppTokens.red,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _catalogCostSection() {
    final rows = [
      for (final order in _allOrders)
        if ((_catalogCosts[order.id] ?? 0) > 0) order,
    ];
    if (rows.isEmpty) {
      return const AppSurface(
        padding: EdgeInsets.all(16),
        shadow: false,
        child: Text(
          'Себестоимость по позициям появится после заполнения склада.',
          style: TextStyle(fontSize: 11.5, color: AppTokens.muted),
        ),
      );
    }
    return AppSurface(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: AppSectionTitle(
              title: 'Себестоимость по позициям',
              subtitle: 'Из цен, заполненных при первом открытии склада',
            ),
          ),
          for (final order in rows.take(30))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${order.number} · ${order.displayTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${appMoney(_catalogCosts[order.id]!)} ₽',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.copper,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _costsSection(FinanceSummary summary) {
    final categories = {
      ExpenseCategory.materials:
          summary.materialCost +
          (summary.byCategory[ExpenseCategory.materials] ?? 0),
      ExpenseCategory.labor: summary.byCategory[ExpenseCategory.labor] ?? 0,
      ExpenseCategory.delivery:
          summary.byCategory[ExpenseCategory.delivery] ?? 0,
      ExpenseCategory.installation:
          summary.byCategory[ExpenseCategory.installation] ?? 0,
      ExpenseCategory.other: summary.byCategory[ExpenseCategory.other] ?? 0,
    };
    final total = categories.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    return AppSurface(
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Структура расходов',
            subtitle: 'Материалы со склада и ручные расходы',
          ),
          const SizedBox(height: 10),
          for (final entry in categories.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      entry.key.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: total > 0 ? entry.value / total : 0,
                        backgroundColor: AppTokens.lineSoft,
                        color: entry.key == ExpenseCategory.materials
                            ? AppTokens.copper
                            : AppTokens.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 100,
                    child: Text(
                      appMoneyShort(entry.value),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Итого: ${appMoney(total)}',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
