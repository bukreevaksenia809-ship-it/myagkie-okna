// Индекс складской номенклатуры для группового выбора.
//
// Чистый Dart: строковые ключи, категории, типы, ширины и цвета выводятся из
// полей WarehouseProduct. По этим данным `GroupedCatalogPicker` строит дерево
// «категория → тип → ширина → цвет», а синхронизация прайса — базовые ключи
// без цветового суффикса (`edge100:brown` → `edge100`).
import '../models/warehouse.dart';

/// Базовый ключ прайса: `edge100:brown` → `edge100`.
String catalogBasePriceKey(String priceKey) {
  final key = priceKey.trim();
  final colon = key.indexOf(':');
  return colon > 0 ? key.substring(0, colon) : key;
}

/// Категория товара для верхнего уровня дерева.
String catalogCategoryOf(WarehouseProduct product) {
  final category = product.category.trim();
  if (category.isNotEmpty) return category;
  final material = product.material.trim();
  return material.isNotEmpty ? material : 'Без категории';
}

/// Тип внутри категории: из названия убираем цвет и ширину.
///
/// «Окантовка тент 100 мм — Серый» → «Тент»,
/// «Люверс круглый Ø10 — Серый» → «Люверс круглый Ø10».
String catalogTypeOf(WarehouseProduct product) {
  var name = product.name.trim();
  if (name.isEmpty) {
    final material = product.material.trim();
    return material.isEmpty ? 'Без типа' : material;
  }
  // Хвост «— Цвет» / «- Цвет» / «– Цвет».
  final color = product.color.trim();
  if (color.isNotEmpty) {
    for (final separator in const [' — ', ' – ', ' - ', '—', '–']) {
      final index = name.lastIndexOf(separator);
      if (index > 0) {
        final tail = name.substring(index + separator.length).trim();
        if (tail.toLowerCase() == color.toLowerCase()) {
          name = name.substring(0, index).trim();
          break;
        }
      }
    }
  }
  // Ширина в названии: «100 мм», «1,5 м».
  name = name
      .replaceAll(RegExp(r'\s+\d+([.,]\d+)?\s*мм(?=\s|$)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+\d+([.,]\d+)?\s*см(?=\s|$)', caseSensitive: false), '')
      .trim();
  // Категория в начале названия: «Окантовка тент …» → «тент …».
  final category = catalogCategoryOf(product);
  if (category.isNotEmpty &&
      name.toLowerCase().startsWith(category.toLowerCase())) {
    name = name.substring(category.length).trim();
  }
  if (name.isEmpty) {
    final material = product.material.trim();
    return material.isEmpty ? 'Без типа' : material;
  }
  return _capitalize(name);
}

/// Ширина позиции строкой или null, если ширины нет.
String? catalogWidthLabelOf(WarehouseProduct product) {
  final width = product.widthMm;
  if (!width.isFinite || width <= 0) return null;
  final text = width == width.roundToDouble()
      ? width.toStringAsFixed(0)
      : width.toStringAsFixed(1).replaceAll('.', ',');
  return '$text мм';
}

/// Цвет позиции; пустой цвет — «Без цвета».
String catalogColorOf(WarehouseProduct product) {
  final color = product.color.trim();
  return color.isEmpty ? 'Без цвета' : color;
}

/// Ключ дедупликации: priceKey, иначе нормализованные поля товара.
String catalogDedupeKey(WarehouseProduct product) {
  final key = product.priceKey.trim();
  if (key.isNotEmpty) return key;
  return [
    _normalize(product.name),
    _normalize(product.category),
    _normalize(product.material),
    _normalize(product.color),
    product.widthMm.toStringAsFixed(2),
  ].join('|');
}

/// Нормализованный цвет для сравнения: без регистра, «ё» → «е».
String normalizeCatalogColor(String raw) =>
    _normalize(raw).replaceAll('ё', 'е');

/// Текст для поиска по названию, цвету, ширине и категории.
String catalogSearchTextOf(WarehouseProduct product) => [
  product.name,
  product.category,
  product.material,
  product.color,
  catalogWidthLabelOf(product) ?? '',
  product.priceKey,
  product.barcode,
  product.supplier,
].where((part) => part.trim().isNotEmpty).join(' ');

String _normalize(String value) => value.trim().toLowerCase();

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
