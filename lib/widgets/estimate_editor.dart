import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/price_list.dart';
import '../services/estimate.dart';

/// Редактор сметы прямо во вкладке «Смета»: меняем название, количество и
/// цену строки, скрываем лишнее, добавляем свои позиции.
class EstimateEditor extends StatelessWidget {
  const EstimateEditor({
    super.key,
    required this.project,
    required this.prices,
    required this.onChanged,
    this.captureKey,
    this.title = 'Смета на заказ',
  });

  final OrderProject project;
  final PriceList prices;
  final ValueChanged<OrderProject> onChanged;
  final GlobalKey? captureKey;
  final String title;

  @override
  Widget build(BuildContext context) {
    final base = Estimate.of(
      project.copyWith(estimateEdits: const {}, manualEstimateLines: const []),
      prices,
      markupPercentOverride: project.estimateMarkupPercent,
      discountPercentOverride: project.estimateDiscountPercent,
    );
    final estimate = Estimate.of(
      project,
      prices,
      markupPercentOverride: project.estimateMarkupPercent,
      discountPercentOverride: project.estimateDiscountPercent,
    );
    final lines = base.lines;
    return Container(
      color: const Color(0xFFE7EBF2),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, minWidth: 920),
            child: RepaintBoundary(
              key: captureKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('estimate-add-line'),
                          onPressed: () => onChanged(
                            project.copyWith(
                              manualEstimateLines: [
                                ...project.manualEstimateLines,
                                const ManualEstimateLine(),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Добавить позицию'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        SizedBox(width: 36, child: Text('№', style: _h)),
                        Expanded(
                          flex: 5,
                          child: Text('Наименование', style: _h),
                        ),
                        SizedBox(width: 100, child: Text('Кол-во', style: _h)),
                        SizedBox(width: 80, child: Text('Ед.', style: _h)),
                        SizedBox(width: 120, child: Text('Цена', style: _h)),
                        SizedBox(width: 120, child: Text('Сумма', style: _h)),
                        SizedBox(width: 36),
                      ],
                    ),
                    const Divider(height: 14),
                    for (var i = 0; i < lines.length; i++)
                      if (project.estimateEdits[i]?.hidden != true)
                        _AutoLineRow(
                          index: i,
                          line: lines[i],
                          edit: project.estimateEdits[i],
                          project: project,
                          onChanged: onChanged,
                        ),
                    for (var i = 0; i < project.manualEstimateLines.length; i++)
                      _ManualLineRow(
                        index: i,
                        line: project.manualEstimateLines[i],
                        project: project,
                        onChanged: onChanged,
                      ),
                    const Divider(height: 28),
                    _totalRow('Подытог', estimate.subtotal),
                    if (estimate.markupPercent > 0)
                      _totalRow(
                        'Наценка ${_pct(estimate.markupPercent)}',
                        estimate.markupAmount,
                      ),
                    if (estimate.discountPercent > 0)
                      _totalRow(
                        'Скидка ${_pct(estimate.discountPercent)}',
                        -estimate.discountAmount,
                      ),
                    if (estimate.vatAmount > 0)
                      _totalRow(
                        'НДС ${_pct(estimate.vatPercent)}',
                        estimate.vatAmount,
                      ),
                    _totalRow('ИТОГО', estimate.total, bold: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        const Spacer(),
        SizedBox(
          width: 260,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(2).replaceAll('.', ',')} ₽',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _pct(double value) =>
      '${value.toStringAsFixed(1).replaceAll('.', ',')} %';
}

const InputDecoration _fieldDecoration = InputDecoration(
  isDense: true,
  border: InputBorder.none,
  contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
);

const TextStyle _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);

class _AutoLineRow extends StatelessWidget {
  const _AutoLineRow({
    required this.index,
    required this.line,
    required this.edit,
    required this.project,
    required this.onChanged,
  });

  final int index;
  final EstimateLine line;
  final EstimateLineEdit? edit;
  final OrderProject project;
  final ValueChanged<OrderProject> onChanged;

  void _set({String? title, double? quantity, double? unitPrice}) {
    final edits = Map<int, EstimateLineEdit>.from(project.estimateEdits);
    edits[index] = (edits[index] ?? const EstimateLineEdit()).copyWith(
      title: title,
      quantity: quantity,
      unitPrice: unitPrice,
    );
    onChanged(project.copyWith(estimateEdits: edits));
  }

  @override
  Widget build(BuildContext context) {
    return _row(
      index,
      edit?.title ?? line.title,
      edit?.quantity ?? line.quantity,
      line.unit,
      edit?.unitPrice ?? line.unitPrice,
      (edit?.quantity ?? line.quantity) * (edit?.unitPrice ?? line.unitPrice),
      onTitle: (v) => _set(title: v),
      onQty: (v) => _set(quantity: double.tryParse(v.replaceAll(',', '.'))),
      onPrice: (v) => _set(unitPrice: double.tryParse(v.replaceAll(',', '.'))),
      onDelete: () {
        final edits = Map<int, EstimateLineEdit>.from(project.estimateEdits);
        edits[index] = (edits[index] ?? const EstimateLineEdit()).copyWith(
          hidden: true,
        );
        onChanged(project.copyWith(estimateEdits: edits));
      },
    );
  }
}

class _ManualLineRow extends StatelessWidget {
  const _ManualLineRow({
    required this.index,
    required this.line,
    required this.project,
    required this.onChanged,
  });

  final int index;
  final ManualEstimateLine line;
  final OrderProject project;
  final ValueChanged<OrderProject> onChanged;

  void _set(ManualEstimateLine next) {
    final lines = [...project.manualEstimateLines];
    lines[index] = next;
    onChanged(project.copyWith(manualEstimateLines: lines));
  }

  @override
  Widget build(BuildContext context) {
    return _row(
      index,
      line.title,
      line.quantity,
      line.unit,
      line.unitPrice,
      line.quantity * line.unitPrice,
      manual: true,
      onTitle: (v) => _set(line.copyWith(title: v)),
      onQty: (v) => _set(
        line.copyWith(quantity: double.tryParse(v.replaceAll(',', '.'))),
      ),
      onPrice: (v) => _set(
        line.copyWith(unitPrice: double.tryParse(v.replaceAll(',', '.'))),
      ),
      onDelete: () {
        final lines = [...project.manualEstimateLines]..removeAt(index);
        onChanged(project.copyWith(manualEstimateLines: lines));
      },
    );
  }
}

Widget _row(
  int index,
  String title,
  double quantity,
  String unit,
  double unitPrice,
  double amount, {
  required ValueChanged<String> onTitle,
  required ValueChanged<String> onQty,
  required ValueChanged<String> onPrice,
  required VoidCallback onDelete,
  bool manual = false,
}) {
  return Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F2))),
    ),
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 36, child: Text('${index + 1}')),
        Expanded(
          flex: 5,
          child: TextFormField(
            initialValue: title,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onTitle,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue: '${quantity.toStringAsFixed(2)}',
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onQty,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 80, child: Text(unit)),
        const SizedBox(width: 6),
        SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: unitPrice.toStringAsFixed(2),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onPrice,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 120,
          child: Text(
            '${amount.toStringAsFixed(2).replaceAll('.', ',')} ₽',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 36,
          child: IconButton(
            tooltip: manual ? 'Удалить строку' : 'Убрать из сметы',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
      ],
    ),
  );
}
