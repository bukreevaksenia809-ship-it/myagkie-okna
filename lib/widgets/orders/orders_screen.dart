import 'package:flutter/material.dart';

import '../../data/order_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../models/order_project.dart';
import '../../models/order_record.dart';
import '../../models/price_list.dart';
import '../../services/order_materials.dart';
import '../design/app_kit.dart';
import '../warehouse/bulk_materials_dialog.dart';
import 'new_order_dialog.dart';
import 'order_details_dialog.dart';

/// Открывает доску заказов отдельным экраном.
Future<void> showOrdersBoardScreen(
  BuildContext context, {
  ValueChanged<OrderRecord>? onOpenProject,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrdersBoardScreen(
        onOpenProject: onOpenProject,
      ),
    ),
  );
}

enum OrdersView {
  board('Доска', Icons.view_kanban_outlined),
  calendar('Календарь', Icons.calendar_month_outlined),
  list('Список', Icons.table_rows_outlined);

  const OrdersView(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Доска заказов в стиле Jira: колонки статусов, drag-and-drop, фильтры,
/// календарь, список, массовые действия и карточка заказа.
class OrdersBoardScreen extends StatefulWidget {
  const OrdersBoardScreen({
    super.key,
    this.embedded = false,
    this.onOpenProject,
    this.prices = const PriceList.defaults(),
  });

  final bool embedded;
  final ValueChanged<OrderRecord>? onOpenProject;
  final PriceList prices;

  @override
  State<OrdersBoardScreen> createState() => _OrdersBoardScreenState();
}

class _OrdersBoardScreenState extends State<OrdersBoardScreen> {
  final _repo = OrderRepository.instance;
  List<OrderRecord> _orders = const [];
  Map<String, OrderCardStats> _stats = const {};
  OrderFilter _filter = const OrderFilter();
  OrdersView _view = OrdersView.board;
  final Set<String> _selected = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String _message = '';
  bool _messageError = false;
  List<String> _assignees = const [];
  List<String> _labels = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await _repo.list();
      final stats = await _repo.stats();
      final assignees = await _repo.assignees();
      final labels = await _repo.labels();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _stats = stats;
        _assignees = assignees;
        _labels = labels;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Не удалось прочитать заказы: $error';
        _messageError = true;
      });
    }
  }

  List<OrderRecord> get _visible => _filter.apply(_orders);

  List<OrderRecord> get _active =>
      _orders.where((order) => !order.archived).toList();

  int get _overdue => _active.where((order) => order.isOverdue).length;

  int get _soon => _active
      .where((order) => order.deadlineState == DeadlineState.soon)
      .length;

  double get _activeAmount =>
      _active.fold(0.0, (sum, order) => sum + order.amount);

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

  Future<void> _create([OrderStatus? status]) async {
    final input = await showNewOrderDialog(
      context,
      assignees: _assignees,
      labels: _labels,
      initialStatus: status,
    );
    if (input == null) return;
    final order = await _repo.create(
      title: input.title,
      customer: input.customer,
      phone: input.phone,
      address: input.address,
      priority: input.priority,
      assignee: input.assignee,
      labels: input.labels,
      deadline: input.deadline,
      comment: input.comment,
      status: status ?? input.status ?? OrderStatus.newOrder,
    );
    await _load();
    if (!mounted) return;
    if (widget.onOpenProject != null) {
      widget.onOpenProject!(order);
      _toast('Заказ ${order.number} создан и открыт в конструкторе');
    } else {
      await _openDetails(order);
    }
  }

  Future<void> _openDetails(OrderRecord order) async {
    final changed = await showOrderDetailsDialog(
      context,
      order,
      onOpenProject: widget.onOpenProject,
    );
    if (changed) await _load();
  }

  Future<void> _move(OrderRecord order, OrderStatus status) async {
    if (order.status == status) return;
    final result = await _repo.setStatus(order.id, status);
    final warehouse = result.ok ? await _syncWarehouse(order, status) : null;
    _toast(
      [result.message, ?warehouse].join('\n'),
      error: !result.ok,
    );
    await _load();
  }

  /// Автоматическая связь статуса со складом:
  /// производство — резерв, готовность — списание, отмена — возврат.
  Future<String?> _syncWarehouse(
    OrderRecord order,
    OrderStatus status,
  ) async {
    final warehouse = WarehouseRepository.instance;
    if (status == OrderStatus.production) {
      final plan = await OrderMaterialsService().plan(_repo.projectOf(order));
      final result = await warehouse.reserveOrder(order.id, plan.needs);
      return result.ok
          ? 'Материалы зарезервированы автоматически'
          : 'Резерв не создан: ${result.message}';
    }
    if (status == OrderStatus.ready) {
      final result = await warehouse.issueOrder(order.id);
      return result.ok
          ? 'Материалы списаны в заказ'
          : 'Списание: ${result.message}';
    }
    if (status == OrderStatus.cancelled) {
      final result = await warehouse.returnOrder(order.id);
      return result.ok ? 'Материалы возвращены на склад' : result.message;
    }
    return null;
  }

  Future<void> _bulkMaterials() async {
    final selected = _orders
        .where((order) => _selected.contains(order.id))
        .toList();
    if (selected.isEmpty) return;
    await showBulkMaterialsDialog(
      context,
      orders: _orders,
      initialSelected: _selected,
      prices: widget.prices,
    );
  }

  Future<void> _bulkStatus(OrderStatus status) async {
    final selected = [..._selected];
    var changed = 0;
    for (final id in selected) {
      final order = _orders.where((item) => item.id == id).firstOrNull;
      if (order == null) continue;
      final result = await _repo.setStatus(id, status);
      if (result.ok) {
        changed++;
        await _syncWarehouse(order, status);
      }
    }
    _toast('Обновлено заказов: $changed');
    setState(() => _selected.clear());
    await _load();
  }

  Future<void> _bulkPriority(OrderPriority priority) async {
    final result = await _repo.bulkUpdate(
      _selected.toList(),
      priority: priority,
    );
    _toast(result.message, error: !result.ok);
    setState(() => _selected.clear());
    await _load();
  }

  Future<void> _bulkArchive(bool archived) async {
    final result = await _repo.bulkUpdate(
      _selected.toList(),
      archived: archived,
    );
    _toast(result.message, error: !result.ok);
    setState(() => _selected.clear());
    await _load();
  }

  Future<void> _bulkAssignee(String assignee) async {
    final result = await _repo.bulkUpdate(
      _selected.toList(),
      assignee: assignee,
    );
    _toast(result.message, error: !result.ok);
    setState(() => _selected.clear());
    await _load();
  }

  void _toggleSelected(OrderRecord order) {
    setState(() {
      if (!_selected.remove(order.id)) _selected.add(order.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gapL,
              AppTokens.gapL,
              AppTokens.gapL,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 16),
                _metrics(),
                const SizedBox(height: 14),
                _toolbar(),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  AppBanner(
                    message: _message,
                    tone: _messageError ? AppTokens.red : AppTokens.green,
                    icon: _messageError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    action: IconButton(
                      onPressed: () => setState(() => _message = ''),
                      icon: const Icon(Icons.close, size: 17),
                    ),
                  ),
                ],
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _bulkBar(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _view == OrdersView.board
                ? _board()
                : _view == OrdersView.calendar
                ? _calendar()
                : _listView(),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTokens.cream,
      appBar: AppBar(
        title: const Text('Заказы'),
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
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    return AppPageHeader(
      eyebrow: 'Производство · заказы',
      title: 'Заказы',
      subtitle:
          'Доска производства: сроки, приоритеты, ответственные и материалы. '
          'Карточку можно перетаскивать между статусами.',
      actions: [
        if (narrow && _overdue + _soon > 0)
          _NotificationsButton(
            overdue: _overdue,
            soon: _soon,
            onPressed: _showNotifications,
          ),
        if (!narrow)
          OutlinedButton.icon(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none, size: 18),
            label: Text(
              _overdue + _soon == 0
                  ? 'Напоминания'
                  : 'Напоминания · ${_overdue + _soon}',
            ),
          ),
        FilledButton.icon(
          key: const Key('orders-new'),
          onPressed: () => _create(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Новый заказ'),
        ),
      ],
    );
  }

  Widget _metrics() {
    return AppResponsiveGrid(
      minItemWidth: 175,
      maxColumns: 4,
      children: [
        AppMetricCard(
          label: 'Активных заказов',
          value: '${_active.length}',
          hint: '${_orders.where((o) => o.archived).length} в архиве',
          icon: Icons.work_outline,
          tone: AppTokens.blue,
        ),
        AppMetricCard(
          label: 'В производстве',
          value:
              '${_active.where((o) => o.status == OrderStatus.production).length}',
          hint: 'на доске',
          icon: Icons.precision_manufacturing_outlined,
          tone: AppTokens.copper,
        ),
        AppMetricCard(
          label: 'Просрочено',
          value: '$_overdue',
          hint: _soon == 0 ? 'сроки в норме' : '$_soon сдают в ближайшие 2 дня',
          icon: Icons.warning_amber_outlined,
          tone: _overdue == 0 ? AppTokens.green : AppTokens.red,
          onTap: () => setState(
            () => _filter = _filter.copyWith(onlyOverdue: true),
          ),
        ),
        AppMetricCard(
          label: 'Сумма активных',
          value: appMoneyShort(_activeAmount),
          hint: 'по сохранённым сметам',
          icon: Icons.payments_outlined,
          tone: AppTokens.green,
        ),
      ],
    );
  }

  Widget _toolbar() {
    return AppSurface(
      padding: const EdgeInsets.all(10),
      shadow: false,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ViewSwitcher(
            value: _view,
            onChanged: (value) => setState(() => _view = value),
          ),
          SizedBox(
            width: 260,
            child: AppSearchField(
              hint: 'Заказ, клиент, адрес, телефон',
              onChanged: (value) =>
                  setState(() => _filter = _filter.copyWith(query: value)),
            ),
          ),
          _FilterMenu(
            label: 'Статус',
            active: _filter.statuses.length,
            items: [
              for (final status in OrderStatus.values)
                _menuCheck(
                  value: status.label,
                  checked: _filter.statuses.contains(status),
                  onTap: () {
                    final next = {..._filter.statuses};
                    if (!next.remove(status)) next.add(status);
                    setState(
                      () => _filter = _filter.copyWith(statuses: next),
                    );
                  },
                ),
            ],
          ),
          _FilterMenu(
            label: 'Приоритет',
            active: _filter.priorities.length,
            items: [
              for (final priority in OrderPriority.values)
                _menuCheck(
                  value: priority.label,
                  checked: _filter.priorities.contains(priority),
                  onTap: () {
                    final next = {..._filter.priorities};
                    if (!next.remove(priority)) next.add(priority);
                    setState(
                      () => _filter = _filter.copyWith(priorities: next),
                    );
                  },
                ),
            ],
          ),
          if (_assignees.isNotEmpty)
            _FilterMenu(
              label: _filter.assignee.isEmpty
                  ? 'Ответственный'
                  : _filter.assignee,
              active: _filter.assignee.isEmpty ? 0 : 1,
              items: [
                _menuCheck(
                  value: 'Все',
                  checked: _filter.assignee.isEmpty,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(assignee: ''),
                  ),
                ),
                for (final assignee in _assignees)
                  _menuCheck(
                    value: assignee,
                    checked: _filter.assignee == assignee,
                    onTap: () => setState(
                      () => _filter = _filter.copyWith(assignee: assignee),
                    ),
                  ),
              ],
            ),
          if (_labels.isNotEmpty)
            _FilterMenu(
              label: _filter.label.isEmpty ? 'Метки' : _filter.label,
              active: _filter.label.isEmpty ? 0 : 1,
              items: [
                _menuCheck(
                  value: 'Все',
                  checked: _filter.label.isEmpty,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(label: ''),
                  ),
                ),
                for (final label in _labels)
                  _menuCheck(
                    value: label,
                    checked: _filter.label == label,
                    onTap: () => setState(
                      () => _filter = _filter.copyWith(label: label),
                    ),
                  ),
              ],
            ),
          FilterChip(
            label: const Text('Просроченные'),
            selected: _filter.onlyOverdue,
            onSelected: (value) => setState(
              () => _filter = _filter.copyWith(onlyOverdue: value),
            ),
          ),
          FilterChip(
            label: const Text('2 дня'),
            selected: _filter.onlySoon,
            onSelected: (value) => setState(
              () => _filter = _filter.copyWith(onlySoon: value),
            ),
          ),
          FilterChip(
            label: const Text('Архив'),
            selected: _filter.includeArchived,
            onSelected: (value) => setState(
              () => _filter = _filter.copyWith(includeArchived: value),
            ),
          ),
          _FilterMenu(
            label: 'Сортировка: ${_filter.sort.label}',
            active: 0,
            items: [
              for (final sort in OrderSort.values)
                _menuCheck(
                  value: sort.label,
                  checked: _filter.sort == sort,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(sort: sort),
                  ),
                ),
            ],
          ),
          if (_filter.isActive)
            TextButton.icon(
              onPressed: () => setState(
                () => _filter = const OrderFilter(),
              ),
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Сбросить'),
            ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 19),
          ),
          if (_selected.isEmpty)
            TextButton.icon(
              onPressed: () => setState(() {
                _selected.addAll(_visible.map((order) => order.id));
              }),
              icon: const Icon(Icons.checklist, size: 16),
              label: const Text('Выбрать всё'),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _selected.clear()),
              icon: const Icon(Icons.close, size: 16),
              label: Text('Снять выбор (${_selected.length})'),
            ),
        ],
      ),
    );
  }

  Widget _bulkBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.ink,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTokens.shadowLift,
      ),
      child: Row(
        children: [
          Text(
            'Выбрано ${_selected.length}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 14),
          PopupMenuButton<OrderStatus>(
            tooltip: 'Статус',
            onSelected: _bulkStatus,
            itemBuilder: (context) => [
              for (final status in OrderStatus.values)
                PopupMenuItem(value: status, child: Text(status.label)),
            ],
            child: const _BulkButton(
              icon: Icons.swap_horiz,
              label: 'Статус',
            ),
          ),
          PopupMenuButton<OrderPriority>(
            tooltip: 'Приоритет',
            onSelected: _bulkPriority,
            itemBuilder: (context) => [
              for (final priority in OrderPriority.values)
                PopupMenuItem(value: priority, child: Text(priority.label)),
            ],
            child: const _BulkButton(
              icon: Icons.flag_outlined,
              label: 'Приоритет',
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ответственный',
            onSelected: _bulkAssignee,
            itemBuilder: (context) => [
              for (final assignee in _assignees)
                PopupMenuItem(value: assignee, child: Text(assignee)),
            ],
            child: const _BulkButton(
              icon: Icons.person_outline,
              label: 'Ответственный',
            ),
          ),
          _BulkButton(
            icon: Icons.inventory_2_outlined,
            label: 'Материалы',
            onTap: _bulkMaterials,
          ),
          _BulkButton(
            icon: Icons.archive_outlined,
            label: 'В архив',
            onTap: () => _bulkArchive(true),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Снять выбор',
            onPressed: () => setState(() => _selected.clear()),
            icon: const Icon(Icons.close, color: Colors.white70, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _board() {
    final visible = _visible;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gapL,
        0,
        AppTokens.gapL,
        AppTokens.gapL,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in OrderStatus.values)
            _column(
              status,
              visible.where((order) => order.status == status).toList(),
            ),
        ],
      ),
    );
  }

  Widget _column(OrderStatus status, List<OrderRecord> orders) {
    final amount = orders.fold(0.0, (sum, order) => sum + order.amount);
    return DragTarget<OrderRecord>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => _move(details.data, status),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return Container(
          width: 306,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: active
                ? AppTokens.copperSoft.withValues(alpha: 0.55)
                : const Color(0xFFF7F1E8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? AppTokens.copper : AppTokens.lineSoft,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(status),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            status.label,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTokens.white,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${orders.length}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Новый заказ в этом статусе',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _create(status),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                    if (orders.isNotEmpty)
                      Text(
                        appMoneyShort(amount),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTokens.faint,
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Column(
                    children: [
                      if (orders.isEmpty)
                        Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTokens.line,
                              style: BorderStyle.solid,
                            ),
                            color: AppTokens.white.withValues(alpha: 0.45),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                color: AppTokens.faint,
                                size: 22,
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Перетащите заказ сюда',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppTokens.faint,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final order in orders) _card(order),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(OrderRecord order) {
    final stats = _stats[order.id];
    final selected = _selected.contains(order.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Draggable<OrderRecord>(
        data: order,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 286,
            child: Transform.rotate(
              angle: -0.02,
              child: _cardBody(
                order,
                stats,
                dragging: true,
                selected: selected,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _cardBody(order, stats),
        ),
        child: _cardBody(
          order,
          stats,
          selected: selected,
          onTap: () => _openDetails(order),
          onLongPress: () => _toggleSelected(order),
          // Галочки показываем только когда идёт массовый выбор: в обычном
          // режиме карточка — заказ, а не задача.
          onCheck: _selected.isEmpty ? null : () => _toggleSelected(order),
        ),
      ),
    );
  }

  Widget _cardBody(
    OrderRecord order,
    OrderCardStats? stats, {
    bool dragging = false,
    bool selected = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onCheck,
  }) {
    final deadlineColor = switch (order.deadlineState) {
      DeadlineState.overdue => AppTokens.red,
      DeadlineState.today || DeadlineState.soon => AppTokens.amber,
      _ => AppTokens.muted,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: AppTokens.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppTokens.copper
                  : dragging
                  ? AppTokens.copper
                  : AppTokens.lineSoft,
              width: selected || dragging ? 1.4 : 1,
            ),
            boxShadow: dragging ? AppTokens.shadowLift : AppTokens.shadowSoft,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    color: order.priority.color,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (onCheck != null)
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: (_) => onCheck(),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              Text(
                                order.number,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: AppTokens.faint,
                                ),
                              ),
                              const Spacer(),
                              if (stats != null && stats.hasMaterials)
                                Tooltip(
                                  message: stats.issuedMaterials > 0
                                      ? 'Материалы списаны'
                                      : 'Материалы зарезервированы',
                                  child: Icon(
                                    stats.issuedMaterials > 0
                                        ? Icons.check_circle_outline
                                        : Icons.lock_outline,
                                    size: 13,
                                    color: stats.issuedMaterials > 0
                                        ? AppTokens.green
                                        : AppTokens.copper,
                                  ),
                                ),
                              if (stats != null && stats.comments > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${stats.comments}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: AppTokens.faint,
                                  ),
                                ),
                                const Icon(
                                  Icons.forum_outlined,
                                  size: 11,
                                  color: AppTokens.faint,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            order.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.28,
                            ),
                          ),
                          if (order.customer.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              order.customer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTokens.muted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Icon(
                                order.deadlineState == DeadlineState.overdue
                                    ? Icons.warning_amber_rounded
                                    : Icons.schedule,
                                size: 12,
                                color: deadlineColor,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  order.deadlineLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: deadlineColor,
                                  ),
                                ),
                              ),
                              Text(
                                appMoneyShort(order.amount),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTokens.inkSoft,
                                ),
                              ),
                            ],
                          ),
                          if (order.labels.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final label in order.labels.take(3))
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTokens.cream,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: AppTokens.muted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              if (order.assignee.isNotEmpty)
                                _Avatar(
                                  name: order.assignee,
                                  size: 21,
                                ),
                              if (order.assignee.isNotEmpty)
                                const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  order.assignee.isEmpty
                                      ? 'Без ответственного'
                                      : order.assignee,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: AppTokens.faint,
                                  ),
                                ),
                              ),
                              if (stats != null && stats.checklistTotal > 0)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.checklist,
                                      size: 11,
                                      color: AppTokens.faint,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${stats.checklistDone}/${stats.checklistTotal}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: AppTokens.faint,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listView() {
    final rows = _visible;
    if (rows.isEmpty) {
      return AppEmptyState(
        icon: Icons.view_list_outlined,
        title: 'Заказов нет',
        message: 'Создайте первый заказ или снимите фильтры.',
        action: FilledButton.icon(
          onPressed: () => _create(),
          icon: const Icon(Icons.add),
          label: const Text('Новый заказ'),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gapL,
        0,
        AppTokens.gapL,
        AppTokens.gapL,
      ),
      child: AppSurface(
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          children: [
            const AppTableHeader(
              cells: [
                '',
                'Заказ',
                'Клиент',
                'Статус',
                'Приоритет',
                'Срок',
                'Ответственный',
                'Сумма',
                '',
              ],
              flex: [1, 4, 3, 2, 2, 2, 2, 2, 1],
            ),
            for (final order in rows) _listRow(order),
          ],
        ),
      ),
    );
  }

  Widget _listRow(OrderRecord order) {
    final selected = _selected.contains(order.id);
    return Material(
      color: selected ? AppTokens.copperSoft.withValues(alpha: 0.45) : null,
      child: InkWell(
        onTap: () => _openDetails(order),
        onLongPress: () => _toggleSelected(order),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.gapM,
            vertical: 10,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelected(order),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${order.number} · ${order.title}',
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
              _cell(order.customer.isEmpty ? '—' : order.customer, flex: 3),
              Expanded(
                flex: 2,
                child: AppPill(
                  label: order.status.label,
                  color: _statusColor(order.status),
                  dense: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: AppPill(
                  label: order.priority.label,
                  color: order.priority.color,
                  dense: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  order.deadlineLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: order.isOverdue ? AppTokens.red : AppTokens.muted,
                  ),
                ),
              ),
              _cell(
                order.assignee.isEmpty ? '—' : order.assignee,
                flex: 2,
              ),
              _cell(appMoneyShort(order.amount), flex: 2, bold: true),
              SizedBox(
                width: 34,
                child: IconButton(
                  tooltip: 'Открыть',
                  onPressed: () => _openDetails(order),
                  icon: const Icon(Icons.chevron_right, size: 19),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, {int flex = 1, bool bold = false}) => Expanded(
    flex: flex,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: AppTokens.inkSoft,
      ),
    ),
  );

  Widget _calendar() {
    final visible = _visible;
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = (first.weekday - 1) % 7;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final width = MediaQuery.sizeOf(context).width;
    final cellHeight = width < 760 ? 98.0 : 126.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gapL,
        0,
        AppTokens.gapL,
        AppTokens.gapL,
      ),
      child: AppSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Предыдущий месяц',
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${_monthName(_month)} ${_month.year}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  tooltip: 'Следующий месяц',
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _month = DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                    ),
                  ),
                  icon: const Icon(Icons.today, size: 16),
                  label: const Text('Сегодня'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _create(),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Заказ'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final day in const [
                  'Пн',
                  'Вт',
                  'Ср',
                  'Чт',
                  'Пт',
                  'Сб',
                  'Вс',
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTokens.faint,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row < rows; row++)
              SizedBox(
                height: cellHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < 7; column++)
                      Expanded(
                        child: _calendarCell(
                          row * 7 + column - leading + 1,
                          visible,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _calendarCell(int day, List<OrderRecord> visible) {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = DateTime(_month.year, _month.month, day);
    final valid = day >= 1 && day <= DateTime(_month.year, _month.month + 1, 0).day;
    final orders = valid
        ? visible
              .where(
                (order) =>
                    order.deadline != null &&
                    DateUtils.dateOnly(order.deadline!) == date,
              )
              .toList()
        : const <OrderRecord>[];
    final isToday = valid && date == today;
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: !valid
            ? Colors.transparent
            : isToday
            ? AppTokens.copperSoft.withValues(alpha: 0.55)
            : AppTokens.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isToday ? AppTokens.copper : AppTokens.lineSoft,
        ),
      ),
      child: !valid
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isToday ? AppTokens.copper : AppTokens.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    if (orders.isNotEmpty)
                      Text(
                        '${orders.length}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTokens.faint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                for (final order in orders.take(3))
                  GestureDetector(
                    onTap: () => _openDetails(order),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(order.status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        order.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(order.status),
                        ),
                      ),
                    ),
                  ),
                if (orders.length > 3)
                  Text(
                    '+${orders.length - 3}',
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: AppTokens.faint,
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _showNotifications() async {
    final items = _active
        .where(
          (order) =>
              order.deadlineState == DeadlineState.overdue ||
              order.deadlineState == DeadlineState.soon ||
              order.deadlineState == DeadlineState.today,
        )
        .toList()
      ..sort((a, b) => (a.deadline ?? DateTime(0)).compareTo(
        b.deadline ?? DateTime(0),
      ));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: AppTokens.copper),
            SizedBox(width: 8),
            Text('Напоминания'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: items.isEmpty
              ? const Text('Ближайших сроков нет.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final order in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          order.isOverdue
                              ? Icons.warning_amber_rounded
                              : Icons.schedule,
                          color: order.isOverdue
                              ? AppTokens.red
                              : AppTokens.amber,
                        ),
                        title: Text('${order.number} · ${order.displayTitle}'),
                        subtitle: Text(
                          '${order.deadlineLabel} · ${order.assignee.isEmpty ? 'без ответственного' : order.assignee}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openDetails(order);
                        },
                      ),
                  ],
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

  String _monthName(DateTime date) => const [
    '',
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ][date.month];

  Widget _statusDot(OrderStatus status) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: _statusColor(status),
      shape: BoxShape.circle,
    ),
  );

  Color _statusColor(OrderStatus status) => switch (status) {
    OrderStatus.newOrder => AppTokens.blue,
    OrderStatus.measured => const Color(0xFF0B62C4),
    OrderStatus.production => AppTokens.copper,
    OrderStatus.ready => AppTokens.green,
    OrderStatus.installed => AppTokens.inkSoft,
    OrderStatus.cancelled => AppTokens.red,
  };
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.value, required this.onChanged});

  final OrdersView value;
  final ValueChanged<OrdersView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTokens.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final view in OrdersView.values)
            Material(
              color: value == view ? AppTokens.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(view),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        view.icon,
                        size: 15,
                        color: value == view
                            ? AppTokens.copper
                            : AppTokens.faint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        view.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: value == view
                              ? AppTokens.ink
                              : AppTokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.items,
    this.active = 0,
  });

  final String label;
  final List<PopupMenuEntry<void>> items;
  final int active;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: label,
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        ...items,
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active > 0 ? AppTokens.copperSoft : AppTokens.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active > 0 ? AppTokens.copper : AppTokens.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active > 0 ? AppTokens.copper : AppTokens.inkSoft,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 15, color: AppTokens.faint),
          ],
        ),
      ),
    );
  }
}

PopupMenuItem<void> _menuCheck({
  required String value,
  required bool checked,
  required VoidCallback onTap,
}) {
  return PopupMenuItem<void>(
    value: null,
    onTap: onTap,
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: checked
              ? const Icon(Icons.check, size: 16, color: AppTokens.copper)
              : null,
        ),
        Text(value),
      ],
    ),
  );
}

class _BulkButton extends StatelessWidget {
  const _BulkButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({
    required this.overdue,
    required this.soon,
    required this.onPressed,
  });

  final int overdue;
  final int soon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Напоминания о сроках',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: overdue + soon > 0,
        label: Text('${overdue + soon}'),
        child: Icon(
          overdue > 0 ? Icons.notifications_active : Icons.notifications_none,
          color: overdue > 0 ? AppTokens.red : AppTokens.ink,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 26});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = appAvatarColor(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.33),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          appInitials(name),
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}
