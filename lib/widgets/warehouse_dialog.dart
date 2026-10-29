import 'package:flutter/material.dart';

import '../models/window_params.dart';
import '../services/material_stock.dart';

/// Склад материалов: остатки рулонов и обрезков.
Future<void> showWarehouseDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _WarehouseDialog(),
  );
}

class _WarehouseDialog extends StatefulWidget {
  const _WarehouseDialog();

  @override
  State<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends State<_WarehouseDialog> {
  List<StockItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await MaterialStock.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  double get _area => _items.fold(0, (sum, item) => sum + item.areaM2);

  Future<void> _add() async {
    final item = await showDialog<StockItem>(
      context: context,
      builder: (context) => const _StockForm(),
    );
    if (item == null) return;
    final items = await MaterialStock.add(item);
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 22),
          SizedBox(width: 8),
          Text('Склад материалов'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Позиций: ${_items.length} · всего ${_area.toStringAsFixed(2).replaceAll('.', ',')} м²',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF66748A),
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('stock-add'),
                        onPressed: _add,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    const Text(
                      'Склад пуст. Добавь рулон или остаток — он сохранится на этом компьютере.',
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final item in _items)
                              Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  dense: true,
                                  title: Text(
                                    '${item.material.label} · ${item.widthMm.toStringAsFixed(0)} × ${item.lengthMm.toStringAsFixed(0)} мм',
                                  ),
                                  subtitle: Text(
                                    '${item.quantity} шт · ${item.areaM2.toStringAsFixed(2).replaceAll('.', ',')} м²'
                                    '${item.note.isEmpty ? '' : ' · ${item.note}'}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Удалить',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final items = await MaterialStock.remove(
                                        item.id,
                                      );
                                      if (mounted) {
                                        setState(() => _items = items);
                                      }
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
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
    );
  }
}

class _StockForm extends StatefulWidget {
  const _StockForm();

  @override
  State<_StockForm> createState() => _StockFormState();
}

class _StockFormState extends State<_StockForm> {
  FilmMaterial _material = FilmMaterial.clearPvc;
  final _width = TextEditingController(text: '2000');
  final _length = TextEditingController(text: '10000');
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double number(TextEditingController controller) =>
        double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    return AlertDialog(
      title: const Text('Новая позиция склада'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<FilmMaterial>(
              initialValue: _material,
              decoration: const InputDecoration(labelText: 'Материал'),
              items: [
                for (final material in FilmMaterial.values)
                  DropdownMenuItem(
                    value: material,
                    child: Text(material.label),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _material = value ?? _material),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    decoration: const InputDecoration(
                      labelText: 'Ширина, мм',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _length,
                    decoration: const InputDecoration(
                      labelText: 'Длина, мм',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _quantity,
              decoration: const InputDecoration(
                labelText: 'Количество, шт',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Место / примечание',
                isDense: true,
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
        FilledButton(
          key: const Key('stock-save'),
          onPressed: () {
            Navigator.of(context).pop(
              StockItem(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                material: _material,
                widthMm: number(_width),
                lengthMm: number(_length),
                quantity: number(_quantity).round(),
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
