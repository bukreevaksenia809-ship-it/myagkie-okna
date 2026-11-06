import 'package:flutter/material.dart';

import '../services/cost_catalog.dart';

/// Первичная настройка себестоимости: для каждой производственной позиции
/// вписывается закупочная цена. Если позиция не используется — галочка
/// снимается, и она больше не попадает в себестоимость заказов.
Future<CostCatalog?> showCostCatalogDialog(
  BuildContext context,
  CostCatalog catalog, {
  bool firstRun = false,
}) {
  return showDialog<CostCatalog>(
    context: context,
    barrierDismissible: !firstRun,
    builder: (context) =>
        _CostCatalogDialog(catalog: catalog, firstRun: firstRun),
  );
}

class _CostCatalogDialog extends StatefulWidget {
  const _CostCatalogDialog({required this.catalog, required this.firstRun});

  final CostCatalog catalog;
  final bool firstRun;

  @override
  State<_CostCatalogDialog> createState() => _CostCatalogDialogState();
}

class _CostCatalogDialogState extends State<_CostCatalogDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final position in costPositions)
      position.key: TextEditingController(
        text: (widget.catalog.costs[position.key] ?? 0) > 0
            ? widget.catalog.costs[position.key]!.toStringAsFixed(2)
            : '',
      ),
  };
  late final Set<String> _disabled = {...widget.catalog.disabled};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final costs = <String, double>{};
    for (final position in costPositions) {
      if (_disabled.contains(position.key)) continue;
      final raw = _controllers[position.key]!.text.replaceAll(',', '.').trim();
      final value = double.tryParse(raw) ?? 0;
      if (value > 0) costs[position.key] = value;
    }
    Navigator.of(
      context,
    ).pop(CostCatalog(costs: costs, disabled: _disabled, configured: true));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Себестоимость материалов',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Впишите закупочную цену за единицу. Если позиция не '
                          'используется — снимите галочку.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF66748A),
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
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                itemCount: costPositions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final position = costPositions[index];
                  final enabled = !_disabled.contains(position.key);
                  return Row(
                    children: [
                      Checkbox(
                        key: Key('cost-enabled-${position.key}'),
                        value: enabled,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _disabled.remove(position.key);
                          } else {
                            _disabled.add(position.key);
                          }
                        }),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              position.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₽ за ${position.unit}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF7A8798),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          key: Key('cost-value-${position.key}'),
                          controller: _controllers[position.key],
                          enabled: enabled,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: '₽',
                            hintText: '0',
                            border: const OutlineInputBorder(),
                            filled: !enabled,
                            fillColor: const Color(0xFFF0F3F7),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Эти цены используются для себестоимости заказов на доске и в финансах.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    key: const Key('cost-catalog-save'),
                    onPressed: _save,
                    child: Text(
                      widget.firstRun
                          ? 'Сохранить и открыть склад'
                          : 'Сохранить',
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
}
