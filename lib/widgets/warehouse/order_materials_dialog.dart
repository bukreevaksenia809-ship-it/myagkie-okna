import 'package:flutter/material.dart';

import '../../data/order_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../models/order_record.dart';
import '../../models/warehouse.dart';
import '../../services/order_materials.dart';
import '../design/app_kit.dart';

/// Диалог связи заказа со складом: потребность, резерв, списание, возврат.
Future<bool> showOrderMaterialsDialog(
  BuildContext context,
  OrderRecord order,
) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OrderMaterialsDialog(order: order),
  );
  return changed == true;
}

class _OrderMaterialsDialog extends StatefulWidget {
  const _OrderMaterialsDialog({required this.order});

  final OrderRecord order;

  @override
  State<_OrderMaterialsDialog> createState() => _OrderMaterialsDialogState();
}

class _OrderMaterialsDialogState extends State<_OrderMaterialsDialog> {
  final _orders = OrderRepository.instance;
  final _warehouse = WarehouseRepository.instance;
  final _materials = OrderMaterialsService();

  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  OrderNeedPlan? _plan;
  List<OrderMaterial> _links = const [];
  List<WarehouseStock> _stocks = const [];
  String? _message;
  bool _messageError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final project = _orders.projectOf(widget.order);
    final plan = await _materials.plan(project);
    final links = await _warehouse.orderMaterials(widget.order.id);
    final snapshot = await _warehouse.snapshot(includeArchived: true);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _links = links;
      _stocks = snapshot.stocks
          .where((stock) => !stock.product.archived)
          .toList();
      _loading = false;
    });
  }

  Future<void> _run(Future<StockActionResult> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = [
        result.message,
        if (result.shortages.isNotEmpty) ...result.shortages,
      ].join('\n');
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _reserve() async {
    final plan = _plan;
    if (plan == null) return;
    await _run(
      () => _warehouse.reserveOrder(widget.order.id, plan.needs),
    );
  }

  Future<void> _issue() async {
    await _run(() => _warehouse.issueOrder(widget.order.id));
  }

  Future<void> _release() async {
    await _run(() => _warehouse.releaseOrder(widget.order.id));
  }

  Future<void> _return() async {
    await _run(() => _warehouse.returnOrder(widget.order.id));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 900;
    final plan = _plan;
    final linksByProduct = {for (final link in _links) link.productId: link};

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 32,
        vertical: narrow ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
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
                      color: AppTokens.blueSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTokens.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Материалы · ${widget.order.number}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          widget.order.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _summary(plan, linksByProduct),
                          const SizedBox(height: 14),
                          if (!_loading && _stocks.isEmpty)
                            const AppBanner(
                              message:
                                  'На складе нет товаров. Добавьте номенклатуру — '
                                  'после этого заказ сможет резервировать материалы.',
                              tone: AppTokens.amber,
                              icon: Icons.warning_amber_outlined,
                            )
                          else ...[
                            _actions(),
                            if ((plan?.shortageCount ?? 0) > 0) ...[
                              const SizedBox(height: 10),
                              _shortageList(plan!),
                            ],
                            if (_message != null) ...[
                              const SizedBox(height: 12),
                              AppBanner(
                                message: _message!,
                                tone: _messageError
                                    ? AppTokens.red
                                    : AppTokens.green,
                                icon: _messageError
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (plan != null && plan.needs.isEmpty)
                              const AppEmptyState(
                                compact: true,
                                icon: Icons.link_off,
                                title: 'Потребность не сопоставлена',
                                message:
                                    'В смете заказа нет строк, которые удалось '
                                    'связать с номенклатурой склада. Проверьте '
                                    'названия товаров и единицы измерения.',
                              )
                            else if (plan != null)
                              _needsTable(plan, linksByProduct, narrow),
                            if (plan != null && plan.unmatched.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _unmatched(plan.unmatched),
                            ],
                            if (_links.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _linkedTable(narrow),
                            ],
                          ],
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Резерв не даёт продать материал другому заказу. '
                      'Списание уменьшает остаток по FIFO.',
                      style: TextStyle(fontSize: 10.5, color: AppTokens.faint),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(_changed),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
    OrderNeedPlan? plan,
    Map<String, OrderMaterial> linksByProduct,
  ) {
    // Складывать штуки, метры и рулоны нельзя — показываем число позиций.
    final reserved = linksByProduct.values
        .where((link) => link.reservedQty > 0.000001)
        .length;
    final issued = linksByProduct.values
        .where((link) => link.issuedQty > 0.000001)
        .length;
    return AppResponsiveGrid(
      minItemWidth: 150,
      maxColumns: 4,
      children: [
        AppMetricCard(
          label: 'Позиций в потребности',
          value: '${plan?.needs.length ?? 0}',
          icon: Icons.list_alt,
          tone: AppTokens.blue,
        ),
        AppMetricCard(
          label: 'Позиций в резерве',
          value: '$reserved',
          icon: Icons.lock_outline,
          tone: AppTokens.copper,
          hint: _links.isEmpty ? 'Резерв не создан' : null,
        ),
        AppMetricCard(
          label: 'Позиций списано',
          value: '$issued',
          icon: Icons.check_circle_outline,
          tone: AppTokens.green,
        ),
        AppMetricCard(
          label: 'Дефицит',
          value: '${plan?.shortageCount ?? 0}',
          icon: Icons.warning_amber_outlined,
          tone: plan != null && plan.shortageCount > 0
              ? AppTokens.red
              : AppTokens.green,
        ),
      ],
    );
  }

  Widget _actions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _reserve,
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Зарезервировать'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _issue,
          style: FilledButton.styleFrom(backgroundColor: AppTokens.green),
          icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
          label: const Text('Списать в заказ'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _release,
          icon: const Icon(Icons.lock_open, size: 18),
          label: const Text('Снять резерв'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _return,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Вернуть на склад'),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  /// Список «докупить»: чего не хватает под этот заказ.
  Widget _shortageList(OrderNeedPlan plan) {
    final lines = plan.needs
        .where((need) => need.shortage > 0)
        .map(
          (need) =>
              '${need.name}: нужно ${appQty(need.quantity)} ${need.unit.label}, '
              'доступно ${appQty(need.available)} — докупить '
              '${appQty(need.shortage)} ${need.unit.label}',
        )
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return AppSurface(
      padding: const EdgeInsets.all(12),
      shadow: false,
      color: AppTokens.amberSoft,
      borderColor: const Color(0xFFEAD7B5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_cart_outlined, size: 17, color: AppTokens.amber),
              SizedBox(width: 7),
              Text(
                'Докупить под заказ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          for (final line in lines)
            Text(
              '• $line',
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
        ],
      ),
    );
  }

  Widget _needsTable(
    OrderNeedPlan plan,
    Map<String, OrderMaterial> links,
    bool narrow,
  ) {
    if (narrow) {
      return Column(
        children: [
          for (final need in plan.needs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _needCard(need, links[need.productId]),
            ),
        ],
      );
    }
    return AppSurface(
      padding: EdgeInsets.zero,
      shadow: false,
      clip: true,
      child: Column(
        children: [
          const AppTableHeader(
            cells: [
              'Товар',
              'Нужно',
              'Доступно',
              'Дефицит',
              'Резерв',
              'Списано',
              'Состояние',
            ],
            flex: [3, 1, 1, 1, 1, 1, 2],
          ),
          for (final need in plan.needs)
            _needRow(need, links[need.productId]),
        ],
      ),
    );
  }

  Widget _needRow(OrderMaterialNeed need, OrderMaterial? link) {
    final state = link?.state;
    final shortage = need.shortage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapM, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  need.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (need.source.isNotEmpty)
                  Text(
                    need.source,
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
          _cell('${appQty(need.quantity)} ${need.unit.shortLabel}'),
          _cell(appQty(need.available)),
          _cell(
            shortage > 0 ? appQty(shortage) : '—',
            color: shortage > 0 ? AppTokens.red : AppTokens.green,
          ),
          _cell(appQty(link?.reservedQty ?? 0)),
          _cell(appQty(link?.issuedQty ?? 0)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppPill(
                label: state?.label ?? 'Не зарезервировано',
                color: _stateColor(state),
                dense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _needCard(OrderMaterialNeed need, OrderMaterial? link) {
    final shortage = need.shortage;
    return AppSurface(
      padding: const EdgeInsets.all(12),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  need.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AppPill(
                label: link?.state.label ?? 'Не зарезервировано',
                color: _stateColor(link?.state),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Нужно ${appQty(need.quantity)} ${need.unit.label} · доступно '
            '${appQty(need.available)}'
            '${shortage > 0 ? ' · дефицит ${appQty(shortage)}' : ''}',
            style: TextStyle(
              fontSize: 11,
              color: shortage > 0 ? AppTokens.red : AppTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {Color? color}) => Expanded(
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? AppTokens.inkSoft,
      ),
    ),
  );

  Widget _linkedTable(bool narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle(
          title: 'Связанные материалы заказа',
          subtitle: 'Сохранённые резервы и списания по этому заказу',
        ),
        const SizedBox(height: 8),
        AppSurface(
          padding: EdgeInsets.zero,
          shadow: false,
          clip: true,
          child: Column(
            children: [
              const AppTableHeader(
                cells: ['Товар', 'Нужно', 'Резерв', 'Списано', 'Состояние'],
                flex: [3, 1, 1, 1, 2],
              ),
              for (final link in _links)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gapM,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTokens.lineSoft),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          link.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _cell('${appQty(link.requiredQty)} ${link.unit.shortLabel}'),
                      _cell(appQty(link.reservedQty)),
                      _cell(appQty(link.issuedQty)),
                      Expanded(
                        flex: 2,
                        child: AppPill(
                          label: link.state.label,
                          color: _stateColor(link.state),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unmatched(List<String> unmatched) {
    return AppSurface(
      padding: const EdgeInsets.all(14),
      shadow: false,
      color: AppTokens.amberSoft,
      borderColor: const Color(0xFFEAD7B5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.link_off,
                size: 18,
                color: AppTokens.amber,
              ),
              SizedBox(width: 8),
              Text(
                'Не сопоставлено со складом',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in unmatched)
            Text(
              '• $line',
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppTokens.inkSoft,
              ),
            ),
        ],
      ),
    );
  }

  Color _stateColor(OrderMaterialState? state) => switch (state) {
    OrderMaterialState.reserved => AppTokens.copper,
    OrderMaterialState.issued => AppTokens.green,
    OrderMaterialState.returned => AppTokens.blue,
    OrderMaterialState.released => AppTokens.faint,
    OrderMaterialState.required || null => AppTokens.muted,
  };
}
