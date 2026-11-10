// Единый выбор складской номенклатуры по цепочке
// категория → тип → ширина → цвет.
//
// Нужен там, где однотипных позиций много: настройки прайса, инвентаризация,
// приход/закупка и себестоимость. Список берётся из склада, каждая цветная
// позиция остаётся отдельной строкой; дубли по одному и тому же ключу
// схлопываются.
import 'package:flutter/material.dart';

import '../../models/price_list.dart';
import '../../models/warehouse.dart';
import '../../models/window_params.dart';
import '../../services/catalog_index.dart';

/// Что показывать в строке: ничего, цену продажи или закупочную цену.
enum CatalogPriceMode { none, sale, purchase }

/// Строка каталога: товар склада плюс (необязательно) остаток.
@immutable
class CatalogItem {
  const CatalogItem({required this.product, this.stock});

  final WarehouseProduct product;
  final WarehouseStock? stock;

  String get id => product.id;
  String get category => catalogCategoryOf(product);
  String get type => catalogTypeOf(product);
  String? get widthLabel => catalogWidthLabelOf(product);
  String get colorLabel => catalogColorOf(product);
  Color get swatch => catalogSwatchColor(product.color);
  String get searchText => catalogSearchTextOf(product);
  String get dedupeKey => catalogDedupeKey(product);

  double priceFor(CatalogPriceMode mode) => switch (mode) {
    CatalogPriceMode.sale => product.salePrice,
    CatalogPriceMode.purchase => product.purchasePrice,
    CatalogPriceMode.none => 0,
  };

  /// Список из товаров склада без архива, без дублей по id и priceKey.
  static List<CatalogItem> fromProducts(
    Iterable<WarehouseProduct> products, {
    Iterable<WarehouseStock> stocks = const <WarehouseStock>[],
    bool includeArchived = false,
  }) {
    final stockByProduct = {
      for (final stock in stocks) stock.product.id: stock,
    };
    final seen = <String>{};
    final result = <CatalogItem>[];
    for (final product in products) {
      if (!includeArchived && product.archived) continue;
      final key = product.priceKey.trim().isNotEmpty
          ? 'key:${product.priceKey}'
          : 'id:${product.id}';
      if (!seen.add(key)) continue;
      result.add(CatalogItem(product: product, stock: stockByProduct[product.id]));
    }
    result.sort(
      (a, b) => a.product.name.toLowerCase().compareTo(
        b.product.name.toLowerCase(),
      ),
    );
    return result;
  }

  /// Список из остатков склада: архивированные скрываются.
  static List<CatalogItem> fromStocks(
    Iterable<WarehouseStock> stocks, {
    bool includeArchived = false,
  }) => fromProducts(
    [for (final stock in stocks) stock.product],
    stocks: stocks,
    includeArchived: includeArchived,
  );
}

/// Цветной кружок цвета складской позиции.
Color catalogSwatchColor(String raw) {
  final normalized = normalizeCatalogColor(raw);
  for (final color in EdgeColor.values) {
    if (normalizeCatalogColor(color.label) == normalized) {
      return Color(color.value);
    }
  }
  const extra = <String, int>{
    'серебристый': 0xFFC0C5CB,
    'прозрачный': 0xFFEAF4FA,
    'тонированный': 0xFF4A4F55,
    'натуральный': 0xFFC8A97E,
    'латунь': 0xFFB08D45,
    'нержавейка': 0xFFB9BEC5,
    'без цвета': 0xFFD9D9D9,
  };
  final value = extra[normalized];
  if (value != null) return Color(value);
  // Стабильный цвет из хэша: один и тот же цвет всегда одного оттенка.
  final hue = (normalized.hashCode.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.32, 0.62).toColor();
}

/// Кружок цвета с рамкой — светлые цвета не сливаются с фоном.
class CatalogSwatch extends StatelessWidget {
  const CatalogSwatch({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x33000000)),
      ),
    );
  }
}

/// Дерево выбора номенклатуры с поиском.
class GroupedCatalogPicker extends StatefulWidget {
  const GroupedCatalogPicker({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedId,
    this.initialCategory,
    this.priceMode = CatalogPriceMode.sale,
    this.showStock = false,
    this.showProductName = false,
    this.searchHint = 'Поиск: название, тип, цвет, ширина',
    this.pickerKey = 'grouped-catalog',
    this.dense = false,
  });

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onSelected;
  final String? selectedId;
  final String? initialCategory;
  final CatalogPriceMode priceMode;
  final bool showStock;
  final bool showProductName;
  final String searchHint;
  final String pickerKey;
  final bool dense;

  /// Модальный выбор: возвращает выбранную строку или null.
  static Future<CatalogItem?> show(
    BuildContext context, {
    required List<CatalogItem> items,
    String title = 'Выбрать позицию',
    String? selectedId,
    String? initialCategory,
    CatalogPriceMode priceMode = CatalogPriceMode.sale,
    bool showStock = false,
    bool showProductName = false,
    String pickerKey = 'grouped-catalog',
  }) {
    return showDialog<CatalogItem>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      key: Key('$pickerKey-close'),
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GroupedCatalogPicker(
                    items: items,
                    selectedId: selectedId,
                    initialCategory: initialCategory,
                    priceMode: priceMode,
                    showStock: showStock,
                    showProductName: showProductName,
                    pickerKey: pickerKey,
                    onSelected: (item) => Navigator.of(context).pop(item),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<GroupedCatalogPicker> createState() => _GroupedCatalogPickerState();
}

class _GroupedCatalogPickerState extends State<GroupedCatalogPicker> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _expanded.add(widget.initialCategory!);
    }
    final selected = _selectedItem;
    if (selected != null) {
      _expandChain(selected);
    } else if (widget.initialCategory == null && widget.items.isNotEmpty) {
      _expanded.add(widget.items.first.category);
    }
  }

  CatalogItem? get _selectedItem {
    for (final item in widget.items) {
      if (item.id == widget.selectedId) return item;
    }
    return null;
  }

  void _expandChain(CatalogItem item) {
    _expanded.add(item.category);
    _expanded.add('${item.category}\u0000${item.type}');
    final width = item.widthLabel;
    if (width != null) {
      _expanded.add('${item.category}\u0000${item.type}\u0000$width');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: Key('${widget.pickerKey}-search'),
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: widget.searchHint,
            prefixIcon: const Icon(Icons.search, size: 19),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.clear, size: 18),
                  ),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Нет подходящих позиций',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _query.trim().isEmpty
              ? _tree(filtered)
              : _searchResults(filtered),
        ),
      ],
    );
  }

  List<CatalogItem> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    final tokens = query.split(RegExp(r'\s+'));
    return [
      for (final item in widget.items)
        if (tokens.every(item.searchText.toLowerCase().contains)) item,
    ];
  }

  /// Дерево: категория → тип → ширина (если есть) → цвет.
  Widget _tree(List<CatalogItem> items) {
    final categories = <String, List<CatalogItem>>{};
    for (final item in items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }
    final names = categories.keys.toList()..sort();
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (context, index) {
        final category = names[index];
        final categoryItems = categories[category]!;
        final expanded = _expanded.contains(category);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _groupHeader(
              key: Key('${widget.pickerKey}-category-$category'),
              label: category,
              count: categoryItems.length,
              level: 0,
              expanded: expanded,
              onTap: () => _toggle(category),
            ),
            if (expanded) ...[
              for (final typeEntry in _groupByType(categoryItems).entries)
                _typeGroup(category, typeEntry.key, typeEntry.value),
            ],
          ],
        );
      },
    );
  }

  Map<String, List<CatalogItem>> _groupByType(List<CatalogItem> items) {
    final types = <String, List<CatalogItem>>{};
    for (final item in items) {
      types.putIfAbsent(item.type, () => []).add(item);
    }
    final sorted = <String, List<CatalogItem>>{};
    for (final key in types.keys.toList()..sort()) {
      final list = types[key]!;
      list.sort((a, b) {
        final left = a.widthLabel ?? '';
        final right = b.widthLabel ?? '';
        final byWidth = left.compareTo(right);
        return byWidth != 0
            ? byWidth
            : a.colorLabel.toLowerCase().compareTo(b.colorLabel.toLowerCase());
      });
      sorted[key] = list;
    }
    return sorted;
  }

  Widget _typeGroup(String category, String type, List<CatalogItem> items) {
    final key = '$category\u0000$type';
    final expanded = _expanded.contains(key);
    final widths = <String?, List<CatalogItem>>{};
    for (final item in items) {
      widths.putIfAbsent(item.widthLabel, () => []).add(item);
    }
    final hasWidths = widths.keys.any((width) => width != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupHeader(
          key: Key('${widget.pickerKey}-type-$category/$type'),
          label: type,
          count: items.length,
          level: 1,
          expanded: expanded,
          onTap: () => _toggle(key),
        ),
        if (expanded) ...[
          if (hasWidths) ...[
            for (final widthEntry in _sortedWidths(widths))
              _widthGroup(category, type, widthEntry.$1, widthEntry.$2),
            for (final item in widths[null] ?? const <CatalogItem>[])
              _leaf(item, level: 2),
          ] else
            for (final item in widths[null]!) _leaf(item, level: 2),
        ],
      ],
    );
  }

  List<(String, List<CatalogItem>)> _sortedWidths(
    Map<String?, List<CatalogItem>> widths,
  ) {
    final entries = widths.entries.toList()
      ..sort((a, b) => (a.key ?? '').compareTo(b.key ?? ''));
    return [
      for (final entry in entries)
        if (entry.key != null) (entry.key!, entry.value),
    ];
  }

  Widget _widthGroup(
    String category,
    String type,
    String width,
    List<CatalogItem> items,
  ) {
    final key = '$category\u0000$type\u0000$width';
    final expanded = _expanded.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupHeader(
          key: Key('${widget.pickerKey}-width-$category/$type/$width'),
          label: width,
          count: items.length,
          level: 2,
          expanded: expanded,
          onTap: () => _toggle(key),
        ),
        if (expanded)
          for (final item in items) _leaf(item, level: 3),
      ],
    );
  }

  Widget _groupHeader({
    required Key key,
    required String label,
    required int count,
    required int level,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(10.0 + level * 16, 9, 10, 9),
        decoration: level == 0
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE4E9F1)),
                ),
              )
            : null,
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: const Color(0xFF66748A),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: level == 0 ? 13 : 12,
                  fontWeight: level == 0 ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF8B98AA),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaf(CatalogItem item, {required int level}) {
    final theme = Theme.of(context);
    final selected = item.id == widget.selectedId;
    return InkWell(
      key: Key('${widget.pickerKey}-item-${item.id}'),
      onTap: () => widget.onSelected(item),
      child: Container(
        color: selected ? const Color(0xFFEAF2FC) : null,
        padding: EdgeInsets.fromLTRB(20.0 + level * 16, 7, 10, 7),
        child: Row(
          children: [
            CatalogSwatch(color: item.swatch),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.showProductName
                        ? item.product.name
                        : item.colorLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (widget.showProductName && item.colorLabel.isNotEmpty)
                    Text(
                      item.colorLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF7C8798),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showStock && item.stock != null)
              Text(
                formatQty(item.stock!.available, item.product.unit.label),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF66748A),
                ),
              ),
            if (widget.priceMode != CatalogPriceMode.none) ...[
              const SizedBox(width: 10),
              Text(
                formatRubles(item.priceFor(widget.priceMode)),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF2B3440),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 16, color: Color(0xFF0B62C4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchResults(List<CatalogItem> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final width = item.widthLabel;
        return InkWell(
          key: Key('${widget.pickerKey}-item-${item.id}'),
          onTap: () => widget.onSelected(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                CatalogSwatch(color: item.swatch),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      Text(
                        '${item.category} · ${item.type}'
                        '${width == null ? '' : ' · $width'} · ${item.colorLabel}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF7C8798),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.showStock && item.stock != null)
                  Text(
                    formatQty(item.stock!.available, item.product.unit.label),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF66748A),
                    ),
                  ),
                if (widget.priceMode != CatalogPriceMode.none) ...[
                  const SizedBox(width: 10),
                  Text(
                    formatRubles(item.priceFor(widget.priceMode)),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggle(String key) {
    setState(() {
      if (!_expanded.remove(key)) _expanded.add(key);
    });
  }
}

/// Количество с единицей без лишних нулей.
String formatQty(double value, String unit) {
  if (!value.isFinite) return '—';
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return unit.isEmpty ? text : '$text $unit';
}
