import 'dart:math' as math;

import '../data/warehouse_repository.dart';
import '../models/order_project.dart';
import '../models/warehouse.dart';
import '../services/estimate.dart';

/// Потребность заказа в материалах: сопоставленные строки и то, что осталось
/// без товара на складе.
class OrderNeedPlan {
  const OrderNeedPlan({
    required this.needs,
    required this.unmatched,
    required this.estimateTotal,
  });

  final List<OrderMaterialNeed> needs;
  final List<String> unmatched;
  final double estimateTotal;

  bool get hasUnmatched => unmatched.isNotEmpty;

  int get shortageCount => needs.where((need) => need.shortage > 0).length;
}

/// Связывает смету заказа с номенклатурой склада.
///
/// Сопоставление прозрачное и предсказуемое: сначала по категории и материалу
/// (полотно/окантовка/люверсы/фурнитура), затем по вхождению названия. Если
/// единицы не совпадают, количество пересчитывается через площадь/длину
/// единицы товара; если пересчёт невозможен — строка попадает в «не
/// сопоставлено», а не пропадает молча.
class OrderMaterialsService {
  OrderMaterialsService({WarehouseRepository? warehouse})
    : _warehouse = warehouse ?? WarehouseRepository.instance;

  final WarehouseRepository _warehouse;

  Future<OrderNeedPlan> plan(
    OrderProject project, {
    PriceList prices = const PriceList.defaults(),
  }) async {
    final estimate = Estimate.of(project, prices);
    final products = await _warehouse.products();
    final merged = <String, OrderMaterialNeed>{};
    final unmatched = <String>[];

    for (final line in estimate.lines) {
      final product = _match(line.title, line.unit, products);
      if (product == null) {
        unmatched.add('${line.title} — ${line.quantityLabel}');
        continue;
      }
      final quantity = _convert(line.quantity, line.unit, product);
      if (quantity == null) {
        unmatched.add(
          '${line.title} — ${line.quantityLabel} (единицы не совпадают с '
          '«${product.name}», ${product.unit.label})',
        );
        continue;
      }
      final previous = merged[product.id];
      if (previous == null) {
        merged[product.id] = OrderMaterialNeed(
          productId: product.id,
          name: product.name,
          unit: product.unit,
          quantity: quantity,
          available: 0,
          reserved: 0,
          source: line.title,
          note: line.note ?? '',
        );
      } else {
        merged[product.id] = OrderMaterialNeed(
          productId: product.id,
          name: previous.name,
          unit: previous.unit,
          quantity: previous.quantity + quantity,
          available: 0,
          reserved: 0,
          source: '${previous.source}, ${line.title}',
          note: previous.note,
        );
      }
    }

    final needs = await _warehouse.checkNeeds(merged.values.toList());
    needs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return OrderNeedPlan(
      needs: needs,
      unmatched: unmatched,
      estimateTotal: estimate.total,
    );
  }

  WarehouseProduct? _match(
    String title,
    String unit,
    List<WarehouseProduct> products,
  ) {
    final lower = title.toLowerCase();
    final scored = <(WarehouseProduct, int)>[];
    for (final product in products) {
      if (product.archived) continue;
      var score = 0;
      final name = product.name.toLowerCase();
      final category = product.category.toLowerCase();
      final material = product.material.toLowerCase();
      final haystack = '$name $category $material ${product.color.toLowerCase()}';

      // Материал в строке сметы должен совпасть с товаром. Иначе «скрин»
      // цепляется за ПВХ и заказ резервирует не то полотно.
      if (lower.contains('скрин') &&
          !(material.contains('скрин') || name.contains('скрин'))) {
        continue;
      }
      if (lower.contains('тонир') &&
          !(material.contains('тонир') || name.contains('тонир'))) {
        continue;
      }
      if (lower.contains('сетк') &&
          !(material.contains('сетк') || name.contains('сетк'))) {
        continue;
      }

      if (lower.contains('люверс') && name.contains('люверс')) score += 40;
      if ((lower.contains('скоба') || lower.contains('замок')) &&
          (name.contains('скоб') ||
              name.contains('замок') ||
              category.contains('фурнитур'))) {
        score += 24;
      }
      if (lower.contains('ремень') && name.contains('ремен')) score += 40;
      if (lower.contains('молния') && name.contains('молни')) score += 40;
      if (lower.contains('окантов') &&
          (name.contains('окант') ||
              name.contains('тент') ||
              category.contains('окант'))) {
        score += 36;
      }
      if ((lower.contains('полотно') || lower.contains('плёнка')) &&
          (category.contains('полотно') ||
              category.contains('плён') ||
              material.contains('пвх') ||
              material.contains('скрин') ||
              name.contains('плён') ||
              name.contains('скрин'))) {
        score += 28;
      }
      if (lower.contains('скрин') && (material.contains('скрин') || name.contains('скрин'))) {
        score += 30;
      }
      if (lower.contains('тонир') &&
          (material.contains('тонир') || name.contains('тонир'))) {
        score += 26;
      }
      if (lower.contains('сетк') &&
          (material.contains('сетк') || name.contains('сетк'))) {
        score += 26;
      }
      if (lower.contains('фартук') && name.contains('фартук')) score += 24;
      if (lower.contains('ремен') && name.contains('ремен')) score += 20;
      if (lower.contains('груз') && name.contains('груз')) score += 20;

      // Точное вхождение названия товара в строку сметы — сильный признак.
      if (name.length >= 4 && lower.contains(name)) score += 18;
      // Общие слова длиннее трёх букв.
      final words = lower
          .split(RegExp(r'[^a-zа-яё0-9]+'))
          .where((word) => word.length > 3)
          .toSet();
      for (final word in words) {
        if (haystack.contains(word)) score += 3;
      }

      // Единица совпадает — приоритет.
      if (product.unit.label == unit) score += 8;
      if (product.unit == StockUnit.roll && unit == 'м²') score += 4;

      if (score > 0) scored.add((product, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return a.$1.name.length.compareTo(b.$1.name.length);
    });
    return scored.first.$1;
  }

  double? _convert(double quantity, String unit, WarehouseProduct product) {
    if (quantity <= 0) return 0;
    if (unit == product.unit.label) return quantity;
    if (unit == 'м²') {
      if (product.unit == StockUnit.roll && product.unitAreaM2 > 0) {
        return quantity / product.unitAreaM2;
      }
      if (product.unit == StockUnit.meter && product.widthMm > 0) {
        return quantity / (product.widthMm / 1000);
      }
    }
    if (unit == 'м') {
      if (product.unit == StockUnit.roll && product.lengthMm > 0) {
        return quantity / (product.lengthMm / 1000);
      }
    }
    if (unit == 'шт' && product.unit == StockUnit.piece) return quantity;
    if (unit == 'рулон' && product.unit == StockUnit.roll) return quantity;
    // Несовместимые единицы: показываем как есть, но помечаем в примечании.
    return math.max(0.0, quantity);
  }
}
