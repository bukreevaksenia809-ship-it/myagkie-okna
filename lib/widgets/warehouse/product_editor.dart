import 'package:flutter/material.dart';

import '../../models/warehouse.dart';
import '../design/app_kit.dart';

/// Редактор номенклатуры склада.
Future<WarehouseProduct?> showProductEditor(
  BuildContext context, {
  WarehouseProduct? product,
}) {
  return showDialog<WarehouseProduct>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ProductEditorDialog(product: product),
  );
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({this.product});

  final WarehouseProduct? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _material;
  late final TextEditingController _color;
  late final TextEditingController _thickness;
  late final TextEditingController _width;
  late final TextEditingController _length;
  late final TextEditingController _weight;
  late final TextEditingController _min;
  late final TextEditingController _purchase;
  late final TextEditingController _sale;
  late final TextEditingController _supplier;
  late final TextEditingController _location;
  late final TextEditingController _barcode;
  late final TextEditingController _note;
  late StockUnit _unit;
  late bool _archived;
  String? _error;

  static const _categories = [
    'Полотно',
    'Окантовка',
    'Люверсы',
    'Фурнитура',
    'Крепёж',
    'Расходники',
    'Инструмент',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _material = TextEditingController(text: p?.material ?? '');
    _color = TextEditingController(text: p?.color ?? '');
    _thickness = TextEditingController(
      text: p == null || p.thicknessMm == 0 ? '' : appQty(p.thicknessMm),
    );
    _width = TextEditingController(
      text: p == null || p.widthMm == 0 ? '' : appQty(p.widthMm),
    );
    _length = TextEditingController(
      text: p == null || p.lengthMm == 0 ? '' : appQty(p.lengthMm),
    );
    _weight = TextEditingController(
      text: p == null || p.weightKg == 0 ? '' : appQty(p.weightKg),
    );
    _min = TextEditingController(text: p == null ? '' : appQty(p.minQuantity));
    _purchase = TextEditingController(
      text: p == null ? '' : appQty(p.purchasePrice),
    );
    _sale = TextEditingController(text: p == null ? '' : appQty(p.salePrice));
    _supplier = TextEditingController(text: p?.supplier ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _note = TextEditingController(text: p?.note ?? '');
    _unit = p?.unit ?? StockUnit.piece;
    _archived = p?.archived ?? false;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _category,
      _material,
      _color,
      _thickness,
      _width,
      _length,
      _weight,
      _min,
      _purchase,
      _sale,
      _supplier,
      _location,
      _barcode,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Укажите название товара');
      return;
    }
    final purchase = _number(_purchase);
    final sale = _number(_sale);
    if (purchase < 0 || sale < 0) {
      setState(() => _error = 'Цены не могут быть отрицательными');
      return;
    }
    final id = widget.product?.id ??
        'prd-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      WarehouseProduct(
        id: id,
        name: _name.text.trim(),
        category: _category.text.trim(),
        material: _material.text.trim(),
        color: _color.text.trim(),
        thicknessMm: _number(_thickness),
        unit: _unit,
        widthMm: _number(_width),
        lengthMm: _number(_length),
        weightKg: _number(_weight),
        minQuantity: _number(_min),
        purchasePrice: purchase,
        salePrice: sale,
        supplier: _supplier.text.trim(),
        location: _location.text.trim(),
        barcode: _barcode.text.trim(),
        archived: _archived,
        note: _note.text.trim(),
        createdAt: widget.product?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    final purchase = _number(_purchase);
    final sale = _number(_sale);
    final markup = purchase > 0 ? (sale - purchase) / purchase * 100 : 0;

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
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTokens.copperSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTokens.copper,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product == null
                              ? 'Новая номенклатура'
                              : 'Карточка товара',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const Text(
                          'Название, размеры, цены, поставщик, место и штрихкод',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Section(
                      title: 'Основное',
                      icon: Icons.sell_outlined,
                      child: Column(
                        children: [
                          AppField(
                            label: 'Название *',
                            controller: _name,
                            hint: 'Например: Плёнка ПВХ 500 мкм, рулон 2 × 50 м',
                            autofocus: true,
                          ),
                          const SizedBox(height: 10),
                          _two(
                            narrow,
                            AppField(
                              label: 'Категория',
                              controller: _category,
                              hint: 'Полотно / Окантовка / Фурнитура',
                            ),
                            _unitField(),
                          ),
                          const SizedBox(height: 10),
                          _two(
                            narrow,
                            AppField(
                              label: 'Материал',
                              controller: _material,
                              hint: 'ПВХ, скрин, тент, металл',
                            ),
                            AppField(
                              label: 'Цвет',
                              controller: _color,
                              hint: 'Прозрачный, коричневый',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _two(
                            narrow,
                            AppField(
                              label: 'Толщина, мм',
                              controller: _thickness,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                            AppField(
                              label: 'Вес единицы, кг',
                              controller: _weight,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final category in _categories)
                                ActionChip(
                                  label: Text(category),
                                  onPressed: () => setState(() {
                                    _category.text = category;
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Размеры и склад',
                      icon: Icons.straighten,
                      child: Column(
                        children: [
                          _two(
                            narrow,
                            AppField(
                              label: 'Ширина, мм',
                              controller: _width,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                            AppField(
                              label: 'Длина, мм',
                              controller: _length,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          if (_unit == StockUnit.roll) ...[
                            const SizedBox(height: 4),
                            Text(
                              _number(_width) > 0 && _number(_length) > 0
                                  ? 'Площадь одной единицы: '
                                        '${appQty(_number(_width) * _number(_length) / 1000000)} м²'
                                  : 'Укажите ширину и длину рулона — по ним считается площадь.',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTokens.faint,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          _two(
                            narrow,
                            AppField(
                              label: 'Минимальный остаток',
                              controller: _min,
                              hint: '0 — без предупреждения',
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                            AppField(
                              label: 'Место хранения',
                              controller: _location,
                              hint: 'Стеллаж A-3, склад',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _barcode,
                            decoration: const InputDecoration(
                              labelText: 'Штрихкод / QR',
                              hintText: 'Отсканируйте или введите вручную',
                              prefixIcon: Icon(Icons.qr_code_2, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Цены',
                      icon: Icons.payments_outlined,
                      child: Column(
                        children: [
                          _two(
                            narrow,
                            AppField(
                              label: 'Закупочная цена, ₽',
                              controller: _purchase,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                            AppField(
                              label: 'Цена продажи, ₽',
                              controller: _sale,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTokens.cream,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.trending_up,
                                  size: 17,
                                  color: AppTokens.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    purchase <= 0
                                        ? 'Наценка появится после закупочной цены.'
                                        : 'Наценка ${markup.toStringAsFixed(1).replaceAll('.', ',')} % · '
                                              'маржа ${sale <= 0 ? '—' : '${((sale - purchase) / sale * 100).toStringAsFixed(1).replaceAll('.', ',')} %'}',
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
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Поставщик и заметки',
                      icon: Icons.local_shipping_outlined,
                      child: Column(
                        children: [
                          _two(
                            narrow,
                            AppField(
                              label: 'Поставщик',
                              controller: _supplier,
                            ),
                            const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 10),
                          AppField(
                            label: 'Примечание',
                            controller: _note,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _archived,
                            onChanged: (value) =>
                                setState(() => _archived = value),
                            title: const Text(
                              'В архиве',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              'Архивный товар не мешает работе, но история и остатки сохраняются.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      AppBanner(
                        message: _error!,
                        tone: AppTokens.red,
                        icon: Icons.error_outline,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '* обязательное поле',
                      style: TextStyle(fontSize: 10.5, color: AppTokens.faint),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('warehouse-product-save'),
                    onPressed: _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      widget.product == null ? 'Создать товар' : 'Сохранить',
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

  Widget _unitField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Единица',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<StockUnit>(
          initialValue: _unit,
          items: [
            for (final unit in StockUnit.values)
              DropdownMenuItem(
                value: unit,
                child: Text('${unit.label} (${unit.shortLabel})'),
              ),
          ],
          onChanged: (value) => setState(() => _unit = value ?? _unit),
        ),
      ],
    );
  }

  Widget _two(bool narrow, Widget left, Widget right) {
    if (narrow) {
      return Column(
        children: [
          left,
          if (right is! SizedBox) ...[const SizedBox(height: 10), right],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      shadow: false,
      color: AppTokens.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTokens.copper),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
